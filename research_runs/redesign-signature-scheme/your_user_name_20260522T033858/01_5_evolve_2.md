# 01 — Scope & Plan

**Topic:** In BitVM3, garbled circuits are used to do off-chain proof verification based on a signed proof put on the Bitcoin chain. The signed proof is input into the garbled circuit as input labels. In most existing designs, the signature scheme is a Lamport signature, which is verifiable by Bitcoin. Can you provide a re-design using Winternitz signatures instead of Lamport signatures?

**Note:** 

**Model:** `claude-sonnet-4-6`  
**Tokens:** in=3,038 out=5,054  
**Cost:** $0.0849

---

# BitVM3 Winternitz Signature Integration: Revised Design Document

---

### 1. Candidate Solutions

#### Direction A: Standard Forward W-OTS+ with Two-Level PRF Label Derivation (Clean Hierarchical Construction)

Use standard forward-chain W-OTS+ (the NIST-standardized variant with randomized hash inputs) for all on-chain Bitcoin Script verification, combined with a two-level PRF label derivation that cleanly separates the on-chain authentication function from the off-chain label binding function. Concretely:

- **On-chain:** For a 256-bit proof hash partitioned into `⌈256/log₂(w)⌉` chunks, sign chunk `i` with value `v_i ∈ [0, w-1]` by revealing `r_i = H^{v_i}(sk_i)`. Bitcoin Script verifies via: the signer provides `v_i` explicitly as a witness stack element, and Script applies exactly `w - v_i` sequential `OP_SHA256` operations to `r_i` and checks the result equals `pk_i = H^w(sk_i)`. This avoids branching on `v_i` and keeps Script linear per chunk. The public key elements `{pk_i}` are committed in a Taproot leaf as a Merkle root `PK_root = MerkleRoot({pk_i})`.

- **Off-chain label binding:** Binary wire labels are derived as `L_{i,j,b} = HMAC-SHA256(sk_i, i ‖ j ‖ b)` for chunk `i`, bit position `j ∈ [0, log₂(w)-1]`, and bit value `b ∈ {0,1}`. Since `sk_i` is never revealed on-chain (only `H^{v_i}(sk_i)` is), all labels remain computationally hidden from the evaluator except those explicitly delivered by the garbler. The garbler pre-commits to `Label_root = MerkleRoot({H(L_{i,j,b})})` on-chain before proof submission.

- **Checksum:** For `w=16` and 64 message chunks, checksum `C = Σ(15 - v_i) ∈ [0, 960]` requires `⌈log₁₆(961)⌉ = 3` additional checksum chunks, for a total of 67 signed chunks. Script computes the checksum sum via `OP_ADD` over revealed `v_i` witness elements and verifies the checksum chunk values satisfy the fixed-sum constraint.

- **Label delivery:** After the on-chain WOTS signature is confirmed, the garbler delivers `{L_{i,j,b_{i,j}}}` (the correct labels for each wire) off-chain as part of the garbled circuit package. The garbled circuit includes a small internal verification sub-circuit (~`4 × 67 = 268` HMAC-SHA256 gate-equivalents) confirming label consistency with `PK_root` and `Label_root`. Liveness is enforced via a time-locked collateral output: if the garbler fails to deliver within `T` blocks, the verifier claims the collateral.

#### Direction B: WOTS with Explicit Chunk-Value Witness and Per-Chunk Tapscript Leaf Splitting

Address the Tapscript opcode budget constraint directly by splitting the WOTS verification across `k` Tapscript leaves in a MAST structure, where each leaf verifies a disjoint subset of chunks. This makes the on-chain verification budget problem tractable without requiring `OP_CAT` or other unavailable opcodes, and enables a clean encoding of chunk values as explicit witness elements.

- **On-chain structure:** The Taproot tree contains `d` leaves, each verifying `⌈67/d⌉` chunks. For `d=7` and 67 total chunks, each leaf handles ~10 chunks. Each chunk verification in Script: (1) pop `v_i` and `r_i` from witness, (2) apply `w - v_i` times `OP_SHA256` to `r_i` — implemented as `w-1` sequential `OP_SHA256` calls with `OP_IF`/`OP_DROP` guards — (3) check result equals `pk_i` (hardcoded in script). For `w=16`, one chunk requires at most 15 `OP_SHA256` + comparison = ~40 opcodes; 10 chunks per leaf = ~400 opcodes, well within the 10,000-byte Tapscript limit. The checksum verification (3 chunks) occupies its own leaf.

- **Challenge protocol:** The dispute protocol proceeds by challenging the prover to execute the specific Tapscript leaf corresponding to the contested chunk subset. This is fully compatible with BitVM3's challenge-response architecture; the challenger specifies which leaf to execute, and the prover must provide the witness for that leaf.

- **Label binding:** Same two-level PRF derivation as Direction A (`L_{i,j,b} = HMAC-SHA256(sk_i, i ‖ j ‖ b)`), with `sk_i` kept secret. The key structural difference from Direction A is that label delivery and verification are tied to individual Tapscript leaves, allowing the challenge to be narrowed to the specific chunk(s) in dispute — reducing the on-chain challenge cost to `1/d` of the total verification script in the common case.

- **Efficiency:** At `w=16`, the full WOTS signature witness is `67 × 32 = 2,144` bytes of hash reveals plus `67 × 1 = 67` bytes of explicit `v_i` values = ~2,211 bytes total, versus ~8,192 bytes for 256-bit Lamport. Each Tapscript leaf is ~400 opcodes / ~500 bytes. The prover commits the Taproot tree root on-chain in a single 32-byte output; execution of any one leaf costs ~500 witness bytes + `P2TR` overhead.

#### Direction C: W-OTS+ with Hash-Chain-Position Label Derivation and Checksum-Augmented Circuit Input

Construct a direct binding between W-OTS+ chain reveals and garbled circuit labels by using the revealed chain value itself — not `sk_i` — as the PRF key for label derivation, but only after establishing that the forward-chain leakage is semantically harmless in the BitVM3 correctness-only security model. This eliminates the off-chain label delivery requirement entirely, giving the same non-interactive evaluator experience as Lamport-based BitVM3.

- **Security model clarification:** In BitVM3, the prover is the garbler and the verifier is the evaluator. The security requirement is **soundness only** (a malicious prover cannot make the circuit accept an invalid proof); input privacy (hiding `v_i` from the evaluator) is **not required** because the evaluator is the verifier who is supposed to learn the proof's validity. Given this, the forward-chain leakage — that `H^{v_i}(sk_i)` allows forward iteration to compute `H^{v_i+1}(sk_i), ..., H^{w-1}(sk_i)` — is benign: those are labels for chunk values `v' > v_i`, and under the soundness-only model, the evaluator learning those labels does not enable any attack.

- **Label binding:** For chunk `i` with revealed value `r_i = H^{v_i}(sk_i)`, derive labels as `L_i^{v_i} = HMAC-SHA256(r_i, i ‖ "label")`. The evaluator, upon receiving `r_i` on-chain in the WOTS signature, computes `L_i^{v_i}` locally without any additional communication with the garbler. This is the exact interaction pattern of Lamport-based BitVM3 — no additional round.

- **Garbled circuit input structure:** Since each chunk covers `log₂(w)` bits, the garbled circuit receives `log₂(w)` binary wires per chunk, but the input label for all `log₂(w)` bits of chunk `i` is derived from the single WOTS chain value `r_i`. Specifically: the binary decomposition `(b_{i,0}, ..., b_{i,log₂(w)-1})` of `v_i` determines the wire values, and all `log₂(w)` wire labels for chunk `i` are derived as `L_{i,j} = HMAC-SHA256(r_i, i ‖ j)` for `j ∈ [0, log₂(w)-1]`. The evaluator receives `r_i` and computes all `log₂(w)` wire labels locally. The garbled circuit is constructed with these labels as the `v_i`-selected inputs; no modification to standard binary garbling is required.

- **Checksum integration:** The checksum chunk values are also signed under WOTS and their chain reveals appear in the on-chain witness. The evaluator uses these reveals to derive checksum wire labels by the same mechanism. The checksum chunk values are a deterministic function of the message chunk values, so their wire labels are derivable once all message chunk reveals are known — optionally, the garbled circuit can include a sub-circuit that verifies the checksum constraint internally, or it can be verified externally in Script.

#### Direction D: W-OTS+ with Batched Chunk Verification via Recursive Hash Accumulator in Script

Reduce the total Script opcode count for full WOTS verification by replacing per-chunk individual hash chain unrolling with a **hash accumulator** pattern: rather than verifying each of the 67 chain completions individually in Script, the Script verifies a single aggregated commitment formed by hashing all chain completions together. This enables verification of the entire WOTS signature in a single compact Tapscript leaf.

- **Accumulator construction:** The garbler computes `ACC = H(H^{w-v_1}(r_1) ‖ H^{w-v_2}(r_2) ‖ ... ‖ H^{w-v_67}(r_67))` — a hash of all completed chains — and commits `ACC` alongside the WOTS public key root `PK_root` in the setup transaction. Bitcoin Script verifies: given the 67 chain completions `{c_i = H^{w-v_i}(r_i)}` as witness elements (pre-computed off-chain by the prover and pushed onto the witness stack), Script checks `H(c_1 ‖ c_2 ‖ ... ‖ c_67) == ACC` (requiring `OP_CAT` or a hash-tree structure) and checks `c_i == pk_i` for each `i`.

- **OP_CAT dependency analysis:** The accumulator `ACC` requires concatenation of 67 × 32 = 2,144 bytes before hashing. This requires `OP_CAT`, which is not currently available in Bitcoin but is included in the BIP-347 proposal (CTV+CAT softfork). This direction is therefore **conditional on OP_CAT availability** and serves as a forward-looking design for post-softfork Bitcoin.

- **Without OP_CAT fallback:** Replace the flat accumulator with a balanced binary Merkle tree over the `{c_i}` values. Verify the Merkle root in Script without `OP_CAT` by using pairwise `OP_SHA256(c_i ‖ c_{i+1})` — but this still requires `OP_CAT`. A pure-`OP_SHA256` alternative is a sequential hash chain: `A_0 = H(c_1)`, `A_i = H(A_{i-1} ‖ c_{i+1})` — also requiring `OP_CAT`. Without `OP_CAT`, this direction degrades to per-chunk verification (Direction B), so Direction D is exclusively for OP_CAT-enabled Bitcoin.

- **Label binding:** Same two-level PRF derivation as Direction A; `sk_i` never revealed on-chain. The accumulator provides a compact on-chain footprint: the prover provides `{r_i, v_i, c_i}` per chunk as witness elements, and Script verifies chain completions and accumulator in one leaf of ~200 opcodes total (since the per-chain work is pushed to the witness rather than re-executed in Script).

---

### 2. Evaluate Directions

---

#### Direction A: Standard Forward W-OTS+ with Two-Level PRF Label Derivation

| Metric | Assessment |
|---|---|
| **On-chain script size** | For `w=16`, each chunk verification: pop `v_i` (1 op), push `r_i` (1 op), apply up to 15 `OP_SHA256` with `OP_IF`/`OP_DROP` guards (~35 opcodes/chunk), compare to hardcoded `pk_i` (~5 ops). Total: ~40 opcodes × 67 chunks = ~2,680 opcodes. At ~1 byte/opcode average, ~2,680 bytes of Script — within Tapscript's 10,000-byte limit in a single leaf. Plus checksum `OP_ADD` chain: ~70 opcodes. Grand total: ~2,750 opcodes / ~3,000 bytes. **Feasible in a single Tapscript leaf.** |
| **On-chain transaction cost** | WOTS signature witness: 67 hash reveals × 32 bytes + 67 `v_i` values × 1 byte = 2,211 bytes witness. `Label_root` commitment: 32 bytes. `PK_root` in Tapscript: 67 × 32 = 2,144 bytes (hardcoded in script). Total on-chain payload: ~4,400 bytes witness + script. Versus Lamport: 256 × 32 = 8,192 bytes signature + 512 × 32 = 16,384 bytes public key in script = ~24,576 bytes. **~5.5× total reduction.** |
| **Signature size (on-chain payload)** | 67 × 33 bytes (hash + chunk value) = **2,211 bytes** versus 8,192 bytes for Lamport 256-bit. ~3.7× compression on signature alone. |
| **Garbled circuit input label encoding efficiency** | Standard binary garbling unchanged. Labels `L_{i,j,b}` are 256 binary wires for a 256-bit hash input, same count as Lamport. The 67-chunk WOTS structure maps to 256 binary wires internally (64 chunks × 4 bits + 3 checksum chunks × 4 bits = 268 bits, close to 256). Internal verification sub-circuit: ~268 HMAC-SHA256 evaluations = ~268 × ~52 AES-equivalent gates ≈ 14,000 gates overhead on a 10M-gate circuit = **0.14% overhead**. Negligible. |
| **Off-chain computation and communication overhead** | Garbler pre-derives 67 × 4 × 2 = 536 labels via HMAC-SHA256. Off-chain garbled circuit package includes correct 268 labels (~268 × 32 = 8,576 bytes). One additional off-chain round for label delivery post-WOTS confirmation. Time-locked collateral enforces liveness. Computation: trivially fast (<1ms for HMAC-SHA256 × 536). |
| **Security level and cryptographic soundness** | W-OTS+ provides tight unforgeability under chosen-message attacks (unlike standard WOTS). Labels are derived from `sk_i` via HMAC-SHA256 (PRF under ROM). Security reduces to: W-OTS+ unforgeability (reduces to preimage resistance of SHA256 with tightness) + HMAC-SHA256 PRF pseudorandomness + half-gates garbled circuit simulation security. Each component at 128-bit security. No hybrid slack in the reduction for PRF step; W-OTS+ tightness adds ~`log(n)` slack, negligible at 128-bit target. **Full 128-bit security maintained.** |
| **Script opcode compatibility** | Uses only `OP_SHA256`, `OP_EQUALVERIFY`, `OP_ADD`, `OP_IF`, `OP_DROP`, `OP_DUP`. **No `OP_CAT` required.** Fully compatible with current Bitcoin consensus. The explicit `v_i` witness pattern avoids script-level branching on unknown values. |
| **Reduction in on-chain keys/commitments** | Public key reduced from 512 × 32 bytes (Lamport) to a single 32-byte `PK_root` Merkle root + 67 × 32 bytes hardcoded in Script (~2.2KB). Label commitment: single 32-byte `Label_root` versus per-bit Lamport keys. **~7× reduction in on-chain key material.** |
| **Round complexity** | One additional off-chain round (label delivery) versus the Lamport baseline. On-chain rounds unchanged. The time-locked collateral mechanism mitigates the liveness risk without adding on-chain rounds. **+1 off-chain round.** |
| **Novelty** | Principled composition of W-OTS+ (not plain WOTS) with two-level PRF hierarchy is novel in the BitVM context. The explicit `v_i`-as-witness Script pattern for avoiding branching is a concrete engineering contribution. The time-locked liveness enforcement for label delivery is a standard Bitcoin pattern applied in a new context. |

**Risks:** The off-chain label delivery liveness assumption remains: if the prover withholds labels after committing on-chain, the evaluator is stalled until the time-lock expires. The time-lock `T` must be chosen carefully — too short risks network delays causing false collateral claims; too long delays the dispute resolution. Additionally, the internal verification sub-circuit that checks label consistency with `PK_root` must be correctly garbled, creating a bootstrapping dependency: the circuit verifies the labels used to evaluate the circuit. This requires careful protocol ordering (labels delivered before circuit evaluation begins) and is not circular in practice but requires explicit specification.

---

#### Direction B: WOTS with Explicit Chunk-Value Witness and Per-Chunk Tapscript Leaf Splitting

| Metric | Assessment |
|---|---|
| **On-chain script size** | Each Tapscript leaf handles 10 chunks × ~40 opcodes = ~400 opcodes / ~500 bytes per leaf. 7 leaves total = ~3,500 bytes of Script across the tree. Individual leaf execution during a challenge costs ~500 bytes Script + ~320 bytes witness (10 chunks × 32 bytes). **Per-challenge Script execution is ~6× smaller than full Direction A verification.** The Taproot tree itself adds a Merkle path overhead of `log₂(7) × 32 ≈ 100` bytes per challenge. |
| **On-chain transaction cost** | Full setup: 1 P2TR output (34 bytes). Challenge execution: ~320 bytes witness + ~500 bytes Script + ~100 bytes Merkle path = ~920 bytes per challenged leaf, versus ~2,211 bytes for full WOTS verification in Direction A. **Challenge transactions are ~2.4× cheaper than Direction A per challenged leaf.** If only 1 of 7 leaves is ever disputed (common case), total on-chain challenge cost is minimal. |
| **Signature size (on-chain payload)** | Same as Direction A: 67 × 33 = 2,211 bytes for the complete WOTS signature. The leaf-splitting affects Script cost, not signature size. |
| **Garbled circuit input label encoding efficiency** | Identical to Direction A: two-level PRF label derivation, 268 binary wires, ~14,000 gate overhead. No change from Direction A on this metric. **Same as Direction A.** |
| **Off-chain computation and communication overhead** | Same off-chain label delivery requirement as Direction A. However, the per-leaf structure enables optimized dispute: the challenger can identify which 10-chunk subset is contested and only execute the corresponding leaf, reducing on-chain cost for the dispute case. Off-chain overhead is unchanged. |
| **Security level and cryptographic soundness** | Identical to Direction A — same W-OTS+ and PRF security arguments apply. The leaf-splitting does not affect cryptographic security; it is a pure Script engineering optimization. The challenge protocol must ensure that MAST leaf selection by the challenger does not enable selective verification attacks (i.e., the challenger cannot choose to skip certain chunks). This is enforced by the protocol structure: all 7 leaves must be executable, and the prover must provide valid witnesses for all of them when challenged. **Full 128-bit security maintained.** |
| **Script opcode compatibility** | Identical to Direction A. No `OP_CAT` required. Each leaf uses only standard hash and comparison opcodes. |
| **Reduction in on-chain keys/commitments** | Same as Direction A: ~7× reduction in key material. The Taproot MAST structure adds no key overhead. |
| **Round complexity** | Potentially more on-chain rounds in a dispute: the challenger must execute multiple Tapscript leaves to verify all chunks if the prover contests multiple subsets. In the worst case (all chunks contested), 7 on-chain challenge transactions are needed versus 1 for Direction A. **+0 to +6 on-chain rounds in adversarial case.** In the common case (dispute localized to 1 leaf), this is strictly better than Direction A. |
| **Novelty** | The MAST leaf-splitting pattern for WOTS chunk verification is a concrete Bitcoin engineering contribution. The interaction between WOTS chunk boundaries and Tapscript leaf boundaries — ensuring that a dispute can be narrowed to the minimum on-chain footprint — requires non-trivial protocol design. |

**Risks:** The worst-case on-chain round count (7 challenge transactions) could be exploited by a malicious prover to inflate the challenger's on-chain costs (a griefing vector). The protocol must include fee deposits or collateral to disincentivize excessive challenges. Additionally, the leaf-splitting creates a protocol complexity risk: the Taproot tree structure must be committed before proof submission, but the optimal leaf boundaries may depend on the proof structure, requiring a careful setup phase.

---

#### Direction C: W-OTS+ with Hash-Chain-Position Label Derivation (Soundness-Only Model)

| Metric | Assessment |
|---|---|
| **On-chain script size** | Identical to Direction A: ~2,750 opcodes / ~3,000 bytes. The label derivation mechanism is off-chain and does not affect Script size. |
| **On-chain transaction cost** | Identical to Direction A: ~2,211 bytes signature witness. No `Label_root` commitment needed (labels derived locally by evaluator). **Slightly cheaper than Direction A** by one 32-byte commitment omission — negligible difference. |
| **Signature size (on-chain payload)** | Identical to Direction A: 67 × 33 = **2,211 bytes**. |
| **Garbled circuit input label encoding efficiency** | Labels derived locally from `r_i` by evaluator: `L_{i,j} = HMAC-SHA256(r_i, i ‖ j)`. No additional communication required — **zero additional off-chain rounds**, same interaction pattern as Lamport. Garbled circuit construction: evaluator receives `r_i` on-chain, computes all `log₂(w)=4` wire labels for chunk `i` locally. Clean `log₂(w)` binary wires per chunk, total 268 wires. Internal verification sub-circuit not needed since labels are derived from publicly verifiable chain values. **Best label encoding efficiency of all directions.** |
| **Off-chain computation and communication overhead** | **None beyond garbled circuit distribution.** The evaluator computes labels locally from on-chain WOTS reveals. No label delivery step; no liveness requirement on the garbler post-setup. This is the minimal-interaction design. |
| **Security level and cryptographic soundness** | **Scoped to soundness-only security.** In the BitVM3 threat model where the prover is the garbler and the verifier is the evaluator, input privacy is not required — the verifier is supposed to learn whether the proof is valid. Forward-chain leakage (evaluator can compute `H^{v_i+1}(sk_i), ..., H^{w-1}(sk_i)` from `r_i`) allows the evaluator to derive labels for higher chunk values `v' > v_i`. Under soundness-only, this is benign. W-OTS+ unforgeability ensures the prover cannot substitute a different chunk value post-commitment. Security reduces to: W-OTS+ unforgeability + HMAC-SHA256 PRF pseudorandomness + half-gates garbled circuit soundness. **128-bit soundness maintained; input privacy explicitly not guaranteed (by design choice, not a defect).** |
| **Script opcode compatibility** | Identical to Direction A. No `OP_CAT` required. |
| **Reduction in on-chain keys/commitments** | Same WOTS compression (~7×). No `Label_root` commitment needed. **Slightly better than Direction A** on this metric. |
| **Round complexity** | **Zero additional off-chain rounds.** Same as Lamport-based BitVM3. This is the key advantage of this direction. |
| **Novelty** | The explicit scoping of the security model to soundness-only — and the resulting justification for using chain-position label derivation without privacy concerns — is a precise and useful clarification of the BitVM3 security requirement that has not been made explicit in the literature. The direct label derivation from WOTS chain values is technically simpler than the two-level hierarchy, and its correctness under the soundness-only model is the non-obvious contribution. |

**Risks:** The critical risk is **misapplication to a context where input privacy is required**. If the BitVM3 deployment requires the proof to remain confidential (e.g., the proof encodes private data), this direction is insecure. The protocol specification must explicitly document the soundness-only assumption. A secondary risk: if the garbled circuit is re-used across multiple evaluations (violating one-time use), the disclosed chain values accumulate and may leak the full chain structure. The WOTS one-time use enforcement mechanism (see Key Question 5) must be rigorously enforced. A third risk: in some BitVM3 variants, the "evaluator" role may be partially adversarial even though they are nominally the verifier — this depends on the specific dispute protocol instantiation and must be verified against the threat model.

---

#### Direction D: W-OTS+ with Batched Verification via Hash Accumulator (OP_CAT-Dependent)

| Metric | Assessment |
|---|---|
| **On-chain script size** | **With OP_CAT:** Single Tapscript leaf of ~200 opcodes for accumulator verification: push 67 `c_i` values, `OP_CAT` chain, `OP_SHA256`, `OP_EQUALVERIFY` against committed `ACC`. Plus 67 `OP_EQUALVERIFY` checks against `{pk_i}`. Total: ~270 opcodes / ~350 bytes. **~8× smaller Script than Direction A.** Without OP_CAT: degrades to Direction A/B; no benefit. |
| **On-chain transaction cost** | **With OP_CAT:** Witness = 67 × 32 (reveals) + 67 × 32 (completions `c_i`) + 67 × 1 (`v_i` values) = ~4,355 bytes. Larger witness than Direction A because completions are pre-computed off-chain and pushed as witness elements. The Script execution cost is minimal (evaluator does the hash work off-chain). Net vbyte cost comparable to Direction A despite larger witness, because Script size (which affects the script tree UTXO cost) is dramatically smaller. |
| **Signature size (on-chain payload)** | Larger than Directions A/B/C: 67 × (32 + 32 + 1) = ~4,355 bytes versus ~2,211 bytes, because the prover must provide both the raw reveals `r_i` and the pre-computed chain completions `c_i`. **~2× larger on-chain witness than Direction A**, offsetting the Script size saving. |
| **Garbled circuit input label encoding efficiency** | Same two-level PRF label derivation as Direction A. No change on this metric. |
| **Off-chain computation and communication overhead** | Prover must compute all `c_i = H^{w-v_i}(r_i)` before the on-chain transaction. This is `O(w × 67)` hash operations — trivially fast. The off-chain label delivery requirement is the same as Direction A. |
| **Security level and cryptographic soundness** | Same as Direction A with one additional assumption: the accumulator `ACC = H(c_1 ‖ ... ‖ c_67)` must be binding (collision resistance of SHA256 ensures this). If the prover can find a collision in `H`, they can forge the accumulator — but this is already assumed infeasible in the W-OTS+ security proof. **Security unchanged from Direction A**, with the addition of collision resistance of SHA256 as an explicit assumption (already implicit in WOTS). |
| **Script opcode compatibility** | **Critical dependency on `OP_CAT`.** Not available in current Bitcoin consensus. Requires BIP-347 or equivalent soft fork. Without `OP_CAT`, this direction provides zero benefit. **Not deployable on current Bitcoin mainnet.** For a research contribution, this is a future-oriented design. |
| **Reduction in on-chain keys/commitments** | `PK_root` reduced to a single 32-byte commitment (same as Direction A), but `ACC` adds another 32 bytes. Net: essentially same as Direction A on key material reduction. The Script saving is the primary benefit, not key material reduction. |
| **Round complexity** | Same as Direction A: +1 off-chain label delivery round. |
| **Novelty** | The hash accumulator pattern for batch-verifying WOTS chain completions in Bitcoin Script is novel and technically interesting for the post-`OP_CAT` Bitcoin ecosystem. The construction of compressing 67 chain verifications into a single hash check is a useful Bitcoin engineering pattern. |

**Risks:** The primary and potentially fatal risk is **`OP_CAT` non-availability** on current Bitcoin mainnet. This direction is not deployable today and may not be for years, depending on the soft fork timeline. For a research contribution intended for near-term BitVM3 deployment, this risk disqualifies Direction D as the primary design. It should be presented as a forward-looking extension. A secondary risk: the larger witness size (4,355 bytes vs. 2,211 bytes) partially cancels the Script size saving in terms of overall transaction fee impact, since witness data is also fee-bearing (at 1/4 the weight of non-witness data under SegWit).

---

### 3. Chosen Direction

**Chosen: Direction C for current deployment, with Direction A as the privacy-extended variant.**

The core insight from the feedback — that BitVM3's security requirement is **soundness-only** (the verifier is supposed to learn the proof validity, not be hidden from it) — directly enables Direction C as the cleanest and most practically deployable solution. Direction C eliminates the off-chain label delivery round entirely, matching the interaction simplicity of Lamport-based BitVM3 while achieving full WOTS compression (~3.7× on signature size). The labels are derived locally by the evaluator from on-chain WOTS reveals via `L_{i,j} = HMAC-SHA256(r_i, i ‖ j)`, and the security is fully justified under soundness-only with W-OTS+ unforgeability. The forward-chain leakage is explicitly not a defect but a deliberate consequence of the soundness-only security model. For deployments where input privacy is required, Direction A serves as a drop-in upgrade — same on-chain WOTS structure, with the addition of a `Label_root` commitment and one off-chain label delivery round — so the two directions form a coherent family parameterized by the security requirement.

The unified construction is as follows:
- **On-chain:** Standard forward W-OTS+ with `w=16`, explicit `v_i` witness elements, `H^{w-v_i}(r_i) == pk_i` Script verification, checksum verified via `OP_ADD` accumulation. All 67 chunk verifications in a single Tapscript leaf (~2,750 opcodes / ~3,000 bytes).
- **Off-chain (soundness-only):** Evaluator derives `L_{i,j} = HMAC-SHA256(r_i, i ‖ j)` locally from on-chain reveals. Zero additional communication rounds.
- **Off-chain (privacy-extended):** Garbler additionally commits `Label_root` on-chain and delivers correct labels off-chain; evaluator verifies consistency via internal sub-circuit.

---

### 4. Key Questions

1. **Bitcoin Script opcode budget (empirical):** Implement W-OTS+ chunk verification for `w ∈ {4, 16}` in Bitcoin Script using the explicit `v_i`-as-witness pattern (the signer pushes `v_i` and `r_i` onto the witness stack; Script applies exactly `w - v_i` sequential `OP_SHA256` calls implemented via a fixed `w-1` length unroll with `OP_IF`/`OP_DROP` guards). Using `btcdeb` or `python-bitcoinlib`, measure: (a) exact opcode count per chunk, (b) exact Script byte size per chunk, (c) total Script byte size for 67 chunks at `w=16`, and (d) whether the full 67-chunk verification fits within a single Tapscript leaf (10,000-byte limit). This directly answers the feasibility question with empirical data rather than estimates.

2. **Checksum computation in Script — exact arithmetic opcode count:** For `w=16` and 64 message chunks, the checksum `C = Σ(15 - v_i)` requires 63 `OP_ADD` operations plus stack manipulation to accumulate the sum, then comparison against the checksum chunk values. Implement this in Bitcoin Script and measure: (a) exact opcode count for the checksum verification component, (b) whether the sum accumulation fits within Bitcoin Script's integer width constraints (Script integers are bounded to 4 bytes = max value 2³¹-1, and `64 × 15 = 960` is well within this bound — but confirm), and (c) the total opcodes added to the 67-chunk verification Script by the checksum component.

3. **Net on-chain byte comparison across signature schemes and `w` values:** For a 256-bit Fiat-Shamir challenge hash (the representative BitVM3 proof payload), compute the exact on-chain byte totals for: Lamport, W-OTS+ `w=4`, W-OTS+ `w=16`, and W-OTS+ `w=256`, accounting for: (a) WOTS signature witness bytes (hash reveals + explicit chunk values), (b) WOTS public key / verification script bytes, (c) checksum chunk count and bytes for each `w`. Identify the `w` at which the marginal compression gain over the next smaller `w` drops below 10%, indicating the practical optimum. Specifically compute whether `w=16` or `w=256` is superior when accounting for checksum overhead, and provide the exact byte counts for both.

4. **W-OTS+ versus plain WOTS security margin in the Bitcoin threat model:** W-OTS+ uses per-chunk randomization masks `r_i` (public parameters) to achieve a tight security reduction, whereas plain WOTS has a looser reduction with a factor of `n × w` security loss. For the concrete parameters `n=67` chunks, `w=16`, and target 128-bit security, compute the exact security loss (in bits) of plain WOTS versus W-OTS+ using the standard reduction bounds. Specifically: does plain WOTS at `n=67, w=16` still achieve 128-bit security with SHA-256 (256-bit hash output), or does the `n × w = 1,072` reduction factor require a longer hash (e.g., SHA-512) to maintain the 128-bit target? Conversely, does W-OTS+ maintain 128-bit security with SHA-256 at these parameters?

5. **WOTS one-time key enforcement on Bitcoin UTXO — minimal construction:** Design and implement (in pseudocode or Bitcoin Script) the minimal on-chain mechanism preventing a prover from broadcasting two different W-OTS signatures under the same public key for two different proof hash values. Candidate constructions: (a) a P2TR output whose keypath spend nullifies the WOTS key by burning a committed preimage, (b) a time-locked P2WSH that is invalidated after first spend, (c) a nonce commitment in the WOTS public key that is revealed on signing, preventing reuse. For each candidate, compute the on-chain byte overhead (additional script bytes and witness bytes) relative to the core W-OTS commitment transaction, and identify which construction has the smallest overhead while remaining enforceable without trusted parties.

6. **Label derivation security under HMAC-SHA256 for Direction C's soundness-only model:** For Direction C, where `L_{i,j} = HMAC-SHA256(r_i, i ‖ j)` and `r_i = H^{v_i}(sk_i)` is revealed on-chain, formally state (and verify against published WOTS security literature) the exact set of labels computable by an evaluator who observes all 67 WOTS chain reveals `{r_1, ..., r_67}`. Specifically: for chunk `i` with revealed `r_i = H^{v_i}(sk_i)`, list all `j ∈ [0, w-1]` for which `H^j(sk_i)` is computable from `r_i` by forward iteration, and confirm that this set is exactly `{j : j ≥ v_i}` (i.e., all chain values at depth ≥ `v_i`). Then confirm that under the soundness-only model, the evaluator learning these additional labels does not enable a forging attack, given that W-OTS+ checksum prevents substitution of smaller chunk values.

7. **Garbled circuit gate overhead for internal label consistency verification (Direction A privacy variant):** For the Direction A privacy-extended variant, the garbled circuit includes a sub-circuit verifying that received labels `L_{i,j,b}` satisfy `HMAC-SHA256(sk_i, i ‖ j ‖ b) == L_{i,j,b}` for the correct `b = b_{i,j}`. Since `sk_i` is a private input to this sub-circuit (it must be provided by the garbler as an input wire to the circuit, never revealed directly), estimate: (a) the number of garbled gates required to implement one HMAC-SHA256 evaluation in a binary garbled circuit (reference published gate counts for SHA-256 in garbled circuits, approximately 20,000–30,000 gates), (b) the total gate overhead for 67 chunks × `log₂(16) = 4` bits × 1 HMAC-SHA256 per label = 268 HMAC evaluations, and (c) this overhead as a fraction of a representative 10M-gate STARK verification circuit. Determine whether this overhead is practically acceptable or whether a lighter PRF (e.g., AES-128 in fixed-key mode, ~2,000 gates) should replace HMAC-SHA256 for the internal verification sub-circuit.

8. **Tapscript leaf splitting threshold for Direction B — when does splitting become necessary?** Direction B proposes splitting WOTS verification across `d=7` Tapscript leaves as a contingency for the single-leaf approach of Direction A exceeding Script limits. Using the empirical opcode counts from Key Question 1, determine: (a) the exact `w` threshold above which a single-leaf WOTS verification for a 256-bit message exceeds the 10,000-byte Tapscript limit, (b) the minimum number of leaves `d` required for `w=16` and `w=256`, and (c) the additional on-chain cost (Merkle path bytes per challenge transaction) incurred by leaf-splitting for each `d ∈ {2, 4, 8}`. This determines whether Direction B's leaf-splitting complexity is actually necessary for `w=16` (the recommended parameter) or is only needed for larger `w`.
