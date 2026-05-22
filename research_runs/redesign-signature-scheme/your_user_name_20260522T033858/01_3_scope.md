# 01 — Scope & Plan

**Topic:** In BitVM3, garbled circuits are used to do off-chain proof verification based on a signed proof put on the Bitcoin chain. The signed proof is input into the garbled circuit as input labels. In most existing designs, the signature scheme is a Lamport signature, which is verifiable by Bitcoin. Can you provide a re-design using Winternitz signatures instead of Lamport signatures?

**Note:** 

**Model:** `claude-sonnet-4-6`  
**Tokens:** in=3,038 out=5,054  
**Cost:** $0.0849

---

# BitVM3 Winternitz Signature Integration: Scope Document

---

### 1. Candidate Solutions

#### Direction A: Direct WOTS-to-Binary-Label Mapping via Hash Chain Depth Selection

Replace each Lamport bit-pair `(sk_i[0], sk_i[1])` with a WOTS chunk of `log₂(w)` bits, then **decompose each chunk back into individual binary wire labels** inside the garbled circuit. For chunk `i` with Winternitz parameter `w`, the signer reveals `H^(v_i)(sk_i)` on-chain. The evaluator derives `log₂(w)` binary garbled circuit input labels by applying a domain-separated PRF to the revealed chain value: `L_i^(b_j) = PRF(H^(v_i)(sk_i), j || b_j)` for each bit position `j` within the chunk. The garbled circuit is structured identically to the Lamport case at the wire level — it accepts binary inputs — but the label selection mechanism is mediated through the WOTS reveal. Bitcoin Script verifies the WOTS signature by iterating `OP_SHA256` up to `w` times per chunk and checking against committed public key elements. The checksum is verified in Script via arithmetic opcodes, and the checksum chunk values feed additional binary wires into the garbled circuit in the same manner.

#### Direction B: Native Multi-Valued Garbling with WOTS Chunk Labels

Redesign the garbled circuit to natively accept **base-`w` inputs** rather than binary inputs, eliminating the chunk-to-binary decomposition step. For each WOTS chunk `i`, construct `w` possible input labels `{L_i^0, ..., L_i^(w-1)}`, one per possible chunk value. The garbled gates at the input layer are replaced with **w-row garbled tables** that decrypt correctly only when the evaluator holds `L_i^(v_i)`. The label for value `v_i` is derived as `L_i^(v_i) = PRF(H^(v_i)(sk_i), "gc-label" || i)`. All downstream gates remain binary. Bitcoin Script verification is identical to Direction A. The key innovation is that the garbled circuit evaluator receives exactly one label per chunk — the one for the correct value — without needing to reconstruct individual bits. This is a garbling-layer change only; the underlying circuit logic (expressed in binary) is preserved in the gate garbling by expanding input gate tables from 4 rows to `w × 2` rows at input boundaries.

#### Direction C: WOTS+ with Deterministic Randomness Masks Committed On-Chain

Adopt the **WOTS+ variant** (Hülsing, 2013) where each hash application is XORed with a public randomization mask: `H(r_i XOR sk_i)`, `H(r_{i,2} XOR H(r_{i,1} XOR sk_i))`, etc., with masks `r_{i,j}` being public parameters. The masks are committed on-chain as part of the verification script or as a Taproot leaf parameter, enabling a security reduction to second-preimage resistance rather than one-wayness. The label binding and Bitcoin Script structure follow Direction A (binary decomposition) but with the hash chain computation adjusted to include the public masks. The on-chain script embeds the mask values as `OP_PUSH` constants in the hash chain verification loop. This provides a **tighter security proof** under weaker assumptions and is the basis for XMSS/SPHINCS+ security arguments, making it appropriate if the BitVM3 deployment targets long-term security guarantees.

#### Direction D: Hybrid WOTS-Lamport Construction with Tiered Signing

Use **WOTS for the bulk of the proof bits** (e.g., the 256-bit proof hash) and retain **Lamport for a small number of high-sensitivity bits** (e.g., the challenge-response nonce or circuit output bits). Concretely: the `n`-bit proof is split into two parts — a `k`-bit prefix signed with WOTS (achieving compression) and an `m`-bit suffix signed with Lamport (preserving the direct 1-bit-to-label mapping where it matters most, such as for the circuit's output wire labels or the fraud-proof trigger bits). The on-chain Bitcoin Script runs two sub-routines: a WOTS verifier for the prefix and a Lamport verifier for the suffix. The garbled circuit takes binary labels from both sources, unified at the input layer. This tiered approach allows the protocol designer to tune the compression/simplicity tradeoff per segment of the proof, and provides a migration path from an all-Lamport design.

#### Direction E: WOTS Signature with Off-Chain Label Expansion via Interactive OT

Rather than deriving all garbled circuit input labels directly from the WOTS reveals (which requires the full label set to be determined at signing time), use **oblivious transfer (OT) extension** off-chain to distribute labels, with the WOTS on-chain signature serving only as a **commitment binding** mechanism. The WOTS signature is verified on-chain as in Direction A, but its role is narrowed: the revealed chain values serve as OT chooser inputs rather than as direct label sources. The prover sends encrypted label pairs for each bit off-chain via OT, and the verifier uses the WOTS-derived values as OT selection strings to retrieve the correct labels without learning the others. This fully decouples the on-chain footprint (WOTS-sized) from the off-chain label distribution (OT-sized), but introduces an additional off-chain interactive round between prover and verifier before garbled circuit evaluation begins.

---

### 2. Evaluate Directions

---

#### Direction A: Direct WOTS-to-Binary-Label Mapping

| Metric | Assessment |
|---|---|
| On-chain script size | **Good.** For `w=16`, 64 chunk verifications each requiring up to 15 `OP_SHA256` calls plus checksum script. Approximately 3–4× smaller than Lamport script. |
| On-chain transaction cost | **Good.** Witness data reduced by ~3× for 256-bit proofs; fees proportionally lower. |
| Signature size | **Good.** ~82 hash reveals for 256-bit proof at `w=16` vs. 256 for Lamport; significant compression. |
| GC input label encoding efficiency | **Good.** PRF derivation from chunk values maps cleanly to binary wire labels; overhead is only the PRF call per bit per chunk, which is negligible off-chain. |
| Off-chain computation overhead | **Low.** Garbled circuit structure unchanged at the binary level; only label derivation logic is modified. |
| Security level | **Strong.** 128-bit security maintained under standard one-wayness of SHA-256; WOTS security well-understood. Checksum prevents substitution attacks. |
| Script opcode compatibility | **Good.** Requires only `OP_SHA256`, `OP_EQUALVERIFY`, `OP_ADD`, basic arithmetic; no `OP_CAT`. Feasible today. |
| Key/commitment reduction | **~3× compression** at `w=16`; ~8× at `w=256` (with higher script cost). |
| Round complexity | **Unchanged.** Same interaction pattern as Lamport-based BitVM3; no additional rounds introduced. |
| Novelty | **Moderate.** The PRF-mediated label derivation from WOTS chain depths is the novel contribution; the garbled circuit structure is not fundamentally changed. |

**Risks:** The PRF-based label derivation introduces a new assumption (PRF security) on top of WOTS security. The primary risk is a subtle mismatch between the security model of WOTS one-time use and the garbled circuit's label indistinguishability requirement — specifically, whether revealing `H^(v_i)(sk_i)` leaks information about `H^(v_j)(sk_i)` for `v_j > v_i`, which it does by hash chain structure, and whether this leaks the non-selected labels. This must be formally argued in the security proof.

---

#### Direction B: Native Multi-Valued Garbling with WOTS Chunk Labels

| Metric | Assessment |
|---|---|
| On-chain script size | **Good.** Same as Direction A; on-chain WOTS verification is identical. |
| On-chain transaction cost | **Good.** Same on-chain footprint as Direction A. |
| Signature size | **Good.** Same as Direction A. |
| GC input label encoding efficiency | **Moderate.** Requires `w` labels per input chunk (vs. 2 for binary wires), inflating the garbled circuit input layer by a factor of `w/2`. For `w=16`, input gate tables become 16-row structures, increasing off-chain garbled circuit size at the boundary. |
| Off-chain computation overhead | **Higher.** Garbled gate tables at chunk-input boundaries grow from 4 rows to `w × 2` rows. For `w=16`, this is an 8× expansion of input-layer table sizes, though inner circuit gates are unaffected. |
| Security level | **Strong.** Direct label derivation (no binary decomposition) eliminates the PRF-mediated intermediate step, simplifying the security argument at the cost of larger tables. |
| Script opcode compatibility | **Good.** No change to on-chain verification logic. |
| Key/commitment reduction | **Same as Direction A.** |
| Round complexity | **Unchanged.** |
| Novelty | **Higher.** Native multi-valued garbling adapted for WOTS chunk structure is a genuine circuit-level contribution; requires extending standard garbling definitions. |

**Risks:** The primary risk is **garbled circuit complexity inflation** at the input layer. For `w=256`, input-layer gate tables are 256 rows each, which may become impractical for large circuits. Additionally, multi-valued garbling schemes are less standardized, making formal security proofs harder to anchor to existing literature. The off-chain evaluator and garbler must agree on a precise encoding of multi-valued gates, introducing implementation complexity.

---

#### Direction C: WOTS+ with Deterministic On-Chain Masks

| Metric | Assessment |
|---|---|
| On-chain script size | **Higher.** Each hash step requires `OP_XOR`-equivalent logic (not natively available in Bitcoin Script without `OP_CAT` or workarounds), or the masks must be baked in as pre-computed intermediate values. Without `OP_CAT`, implementing the mask XOR requires significant script engineering, potentially doubling script size. |
| On-chain transaction cost | **Worse.** The mask embedding and hash step complexity increases witness data and execution cost. |
| Signature size | **Same as Direction A.** Compression ratio identical. |
| GC input label encoding efficiency | **Same as Direction A.** The WOTS+ chain values replace WOTS chain values as label seeds; derivation logic is identical. |
| Off-chain computation overhead | **Slightly higher.** Mask values must be distributed and applied during garbled circuit construction and verification. |
| Security level | **Best.** Tighter reduction to second-preimage resistance; better suited for long-term or post-quantum-adjacent deployments. Provides provable security under weaker hash assumptions. |
| Script opcode compatibility | **Problematic.** XOR is not natively supported in standard Bitcoin Script. Requires either `OP_CAT` (not currently active), or decomposition into byte-level operations that are unwieldy. This is a **significant constraint**. |
| Key/commitment reduction | **Same as Direction A.** |
| Round complexity | **Unchanged.** |
| Novelty | **Moderate.** Tighter security is the contribution; the integration mechanism is otherwise similar to Direction A. |

**Risks:** The critical risk is **Bitcoin Script incompatibility with XOR operations**. Without `OP_CAT` or a future soft fork, implementing WOTS+ mask application in Script is impractical. This direction is only viable if scoped to a future Bitcoin environment with expanded opcodes (e.g., post-OP_CAT activation via BIP 347), which significantly limits near-term deployability.

---

#### Direction D: Hybrid WOTS-Lamport Construction

| Metric | Assessment |
|---|---|
| On-chain script size | **Moderate.** The script contains two sub-routines; the WOTS portion compresses the bulk, but the Lamport suffix preserves the original per-bit cost for `m` bits. Net reduction depends on the split ratio. |
| On-chain transaction cost | **Moderate.** Better than pure Lamport but worse than pure WOTS; intermediate improvement. |
| Signature size | **Moderate.** Partial compression; the Lamport suffix still requires 2m hash values in the public key. |
| GC input label encoding efficiency | **Best.** The Lamport suffix preserves the perfect 1-to-1 mapping for the most sensitive wires; no label derivation complexity for those wires. |
| Off-chain computation overhead | **Low.** The Lamport portion of the circuit is unchanged from the baseline; only the WOTS prefix adds marginal complexity. |
| Security level | **Strong.** Each component is independently secure under its own assumptions; the hybrid inherits both. |
| Script opcode compatibility | **Good.** Both WOTS and Lamport verification use only `OP_SHA256` and `OP_EQUALVERIFY`. |
| Key/commitment reduction | **Partial.** Only the WOTS portion achieves compression; total reduction is proportional to `k/(k+m)`. For a balanced 50/50 split, only ~1.5× compression overall. |
| Round complexity | **Unchanged.** |
| Novelty | **Low.** This is a compositional design rather than a fundamental innovation; the hybrid design does not advance the state of the art beyond the sum of its parts. |

**Risks:** The main risk is **design fragmentation**: the hybrid introduces two verification code paths, two key management schemes, and a non-obvious security argument for the joint scheme. The choice of split boundary is protocol-specific and may require re-analysis for different proof systems. This direction solves the problem but is unlikely to be the optimal long-term design.

---

#### Direction E: WOTS with Off-Chain OT-Based Label Distribution

| Metric | Assessment |
|---|---|
| On-chain script size | **Best.** On-chain only contains the WOTS commitment and verification; garbled circuit labels are entirely off-chain. Minimal on-chain footprint. |
| On-chain transaction cost | **Best.** Minimal on-chain data; only the WOTS signature needs to be committed. |
| Signature size | **Best.** Smallest on-chain payload; label data moved entirely off-chain. |
| GC input label encoding efficiency | **Complex.** OT extension adds a full interactive protocol layer; labels are not directly derived from the signature but from OT executions seeded by signature values. Significantly more complex than direct derivation. |
| Off-chain computation overhead | **Highest.** OT extension requires multiple off-chain rounds and substantial cryptographic computation (base OT, OT extension protocol). This may dominate the total protocol cost. |
| Security level | **Strong.** OT-based label distribution provides composable security; the on-chain WOTS binding is tight. However, the security model is considerably more complex (combining OT and WOTS security in a UC-like framework). |
| Script opcode compatibility | **Good.** On-chain component is simple WOTS verification; no special opcodes needed. |
| Key/commitment reduction | **Maximum.** On-chain data is minimized beyond all other directions. |
| Round complexity | **Worse.** Introduces at least one additional interactive off-chain round between prover and verifier before circuit evaluation, increasing protocol latency and complexity. |
| Novelty | **Highest.** Combining WOTS on-chain binding with OT-based label distribution is a genuinely novel protocol design. However, it is a departure from the standard garbled circuit input label paradigm used in BitVM3. |

**Risks:** The fundamental risk is **protocol complexity and composability**. OT extension introduces an interactive phase that may conflict with BitVM3's non-interactive or minimally-interactive design goals. If the BitVM3 threat model assumes a non-cooperative prover (i.e., the verifier cannot rely on the prover responding off-chain), this direction may be entirely incompatible with the protocol's security model. Additionally, the OT layer introduces new trust and liveness assumptions not present in the on-chain-only verification model.

---

### 3. Chosen Direction

**Chosen: Direction A (Direct WOTS-to-Binary-Label Mapping via Hash Chain Depth Selection), with the label security argument from Direction B incorporated as a formal proof obligation.**

Direction A provides the best balance of on-chain efficiency, implementation feasibility with current Bitcoin Script capabilities, and minimal disruption to the existing garbled circuit architecture. Unlike Direction B, it does not inflate the off-chain garbled circuit structure; unlike Direction C, it does not require unavailable opcodes; unlike Direction D, it achieves full compression rather than partial; and unlike Direction E, it preserves the non-interactive nature of BitVM3's label-commitment model. The one genuine risk in Direction A — the security of PRF-mediated binary label derivation from WOTS hash chain values, given that the chain structure partially orders revealed secrets — is addressed by incorporating Direction B's insight: the security argument must formally demonstrate that the garbled circuit's label indistinguishability holds even when a subset of the hash chain is revealed on-chain, which is achievable by ensuring the PRF key schedule ensures labels for non-selected values are computationally hidden. This combined design forms the core technical contribution: **a WOTS-integrated BitVM3 garbled circuit protocol where on-chain WOTS reveals at specific hash chain depths are used as seeds to a domain-separated PRF to derive binary garbled circuit input wire labels, with formal security reduction to WOTS one-time unforgeability and PRF pseudorandomness.**

---

### 4. Key Questions

1. **Hash chain depth vs. label security**: Does the ordered structure of the WOTS hash chain — specifically that revealing `H^(v_i)(sk_i)` also implicitly reveals all values `H^j(sk_i)` for `j < v_i` via iterated hashing — allow an adversary to derive non-selected garbled circuit input labels for wire values `v_j < v_i` of the same chunk, and if so, does PRF domain separation with chunk index and value prevent this leakage?

2. **Optimal Winternitz parameter `w` for Bitcoin Script constraints**: For a representative BitVM3 proof size (e.g., a 256-bit STARK/SNARK output hash), what value of `w ∈ {4, 16, 256}` minimizes total on-chain cost (script bytes + witness bytes) while remaining within Bitcoin's per-input script size limits and 201-opcode limit per script execution path?

3. **Checksum wire integration into the garbled circuit**: The WOTS checksum adds `⌈log_w(n · (w-1))⌉` additional chunks that are committed on-chain and must also feed into the garbled circuit as input labels — what is the exact number of additional input wires introduced, and does the checksum verification in Bitcoin Script remain within stack depth and opcode budget for the chosen `w`?

4. **PRF choice and its impact on garbled circuit construction**: Which PRF construction (e.g., HMAC-SHA256, SHA256 in Davies-Meyer mode, or AES-based) minimizes the combined cost of off-chain label derivation and on-chain verifiability, and can the PRF evaluation be made verifiable in Bitcoin Script if needed for dispute resolution?

5. **One-time key reuse security boundary**: Since both WOTS and garbled circuits are one-time primitives, what is the precise protocol-level mechanism that prevents a prover from reusing a WOTS key across multiple proof submissions, and how is this enforced on-chain without requiring interactive revocation?

6. **Compression ratio vs. circuit input overhead**: For varying proof sizes (128-bit, 256-bit, 512-bit message lengths), what is the net reduction in total on-chain bytes (signature payload + verification script) after accounting for the WOTS checksum overhead, and at what proof size does WOTS at `w=16` yield diminishing returns compared to WOTS at `w=4`?

7. **Formal security reduction structure**: Can the full protocol security — binding the on-chain WOTS signature to the off-chain garbled circuit evaluation — be proven under a standard composition theorem (e.g., UC framework or game-based hybrid argument), and what are the exact security assumptions required beyond standard WOTS one-time unforgeability and garbled circuit simulation security?

8. **Bitcoin Script implementation feasibility for iterative hashing**: Can the WOTS chain verification for parameter `w=16` (requiring up to 15 sequential `OP_SHA256` applications with conditional branching based on the chunk value) be implemented within a single Bitcoin Script execution path without exceeding the 520-byte stack element limit or the script execution budget, and what is the exact opcode count per chunk verification?
