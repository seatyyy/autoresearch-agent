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

#### Direction A: Commit-then-Reveal Label Binding with WOTS Chain as Authenticator

Decouple label generation from the WOTS hash chain entirely, resolving the asymmetric leakage problem at its root. The garbler independently samples all input wire labels `{L_i^0, L_i^1}` for each binary wire as in standard garbling, then commits to them on-chain via a hash tree root before the protocol begins. The WOTS signature is used exclusively as an **authenticator** — it proves that the prover endorses a specific chunk value `v_i`, but the label selection mechanism is a separate one-way derivation: `L_i^{b_j} = PRF(seed_i, j || b_j)` where `seed_i = H(sk_i)` (the bottom of the chain, never revealed on-chain). The WOTS reveal of `H^{v_i}(sk_i)` authenticates `v_i` on-chain; the evaluator receives `L_i^{b_j}` for the correct bit values of chunk `i` as part of a non-interactive off-chain label delivery protocol (e.g., included in the garbled circuit package keyed to the committed WOTS public key). Bitcoin Script verifies the WOTS chain and confirms the on-chain commitment to the label tree root, while the evaluator uses labels that are seeded from `sk_i` — which is never exposed — making all non-selected labels computationally hidden regardless of which chain position is revealed. This design directly addresses the leakage asymmetry: since `H^{v_i}(sk_i)` is one-way with respect to `sk_i`, and labels are derived from `sk_i` rather than from `H^{v_i}(sk_i)`, revealing higher chain positions does not expose lower-index labels or the seed, and the full label set remains hidden to the evaluator except for those explicitly delivered.

#### Direction B: Reversed Hash Chain with Bottom-Anchored Label Derivation

Exploit the directionality of the WOTS hash chain to construct a **cryptographically sound direct label binding** without decoupling. In standard WOTS, signing chunk value `v` reveals `H^v(sk_i)`, leaking chain values for `v' > v` by forward iteration. This direction reverses the chain direction for label derivation: define the signing operation so that to sign chunk value `v ∈ [0, w-1]`, the signer reveals `H^{w-1-v}(sk_i)`, i.e., the chain is indexed from the top. Under this convention, the revealed value is at depth `w-1-v` from the root `sk_i`, and an observer can iterate forward to reach `H^{w-1}(sk_i) = pk_i`, but **cannot** iterate backward to recover values at depths less than `w-1-v` — preserving one-wayness downward. Labels for each binary bit position `j` within chunk `i` are then derived as `L_i^{b_j} = PRF(H^{w-1-v_i}(sk_i), i || j || b_j)`. An evaluator who receives `H^{w-1-v_i}(sk_i)` can compute the labels for chunk value `v_i` but cannot compute `H^{w-1-v'}(sk_i)` for any `v' > v_i` (those are deeper in the chain and unreachable by forward hashing from the revealed value). Labels for `v' < v_i` correspond to shallower chain positions reachable by forward hashing, but those chunk values are *higher-cost to sign* (requiring fewer applications), meaning the WOTS checksum prevents their forgery — the leakage of those labels is exactly what WOTS security accounts for through the checksum mechanism. Bitcoin Script verifies by checking `H^{v_i}(revealed) == pk_i` (i.e., applying `v_i` more forward hashes). This is a clean, direct construction with no separate commitment required.

#### Direction C: WOTS with Per-Chunk Oblivious Label Delivery via Pre-Committed Encrypted Labels

Keep the standard (forward) WOTS chain for on-chain Bitcoin Script compatibility and resolve the leakage problem through an **encrypted label table committed on-chain**. For each chunk `i`, the garbler constructs `w` encryptions: `E_j = Enc(H^j(sk_i), L_i^{v=j})` for `j ∈ [0, w-1]`, where `Enc` is a symmetric authenticated encryption keyed by the chain value at depth `j`. These `w` ciphertexts per chunk are committed on-chain (or in a Taproot leaf) as part of the circuit setup transaction. The evaluator, upon learning `H^{v_i}(sk_i)` from the on-chain WOTS signature, decrypts exactly `E_{v_i}` to obtain `L_i^{v_i}` — the correct input label. Crucially, decrypting `E_j` for `j > v_i` requires `H^j(sk_i)`, which is computable from `H^{v_i}(sk_i)` by forward iteration. This apparent leakage is neutralized by ensuring the garbled circuit is constructed so that labels `L_i^{v=j}` for `j > v_i` decrypt garbled gates to **incorrect or random outputs** — they are semantically invalid labels. Labels for `j < v_i` require chain values unreachable from `H^{v_i}(sk_i)`, so those remain computationally hidden. Security relies on the WOTS checksum preventing the adversary from substituting a smaller chunk value (which would correspond to a "deeper" chain reveal). The encrypted label table is compact: `w` ciphertexts per chunk, each ~32–64 bytes, totalling ~2KB for `w=16` over 64 chunks for a 256-bit message. Bitcoin Script verifies the WOTS chain identically to Direction A/B; the encrypted label table is placed in a Taproot leaf or an `OP_RETURN` commitment.

#### Direction D: WOTS with Chunk-to-Bit Expansion via Independent Per-Bit Lamport Sub-Keys Derived from WOTS Seed

Construct a **two-level key hierarchy** in which each WOTS chunk key `sk_i` is also the root of a small Lamport sub-key tree covering the `log_2(w)` bits of that chunk. Specifically: for chunk `i` covering bits `{b_{i,0}, ..., b_{i,log_2(w)-1}}`, derive per-bit Lamport key pairs as `(lk_{i,j,0}, lk_{i,j,1}) = (PRF(sk_i, i || j || 0), PRF(sk_i, i || j || 1))` for `j ∈ [0, log_2(w)-1]`. The on-chain WOTS signature authenticates each chunk's value by revealing `H^{v_i}(sk_i)`. The garbled circuit input labels are the Lamport sub-keys for the correct bit values: `L_{i,j} = lk_{i,j, b_{i,j}}`. These labels are derived from `sk_i` (not from `H^{v_i}(sk_i)`), so revealing the chain value does not expose the sub-keys — `sk_i` is never revealed on-chain. The evaluator receives the Lamport sub-key labels off-chain as part of the garbled circuit package (pre-committed by the garbler before the proof is submitted). Bitcoin Script verifies the WOTS chain to confirm the chunk value is authentic; the garbled circuit internally verifies that the received Lamport sub-key labels are consistent with the WOTS-authenticated chunk value through a small verification sub-circuit. This direction preserves the **exact Lamport-style 1-bit-to-1-label correspondence** at the garbled circuit wire level while achieving WOTS-level compression for on-chain data.

---

### 2. Evaluate Directions

---

#### Direction A: Commit-then-Reveal Label Binding

| Metric | Assessment |
|---|---|
| On-chain script size | **Good.** WOTS chain verification requires `w-1` `OP_SHA256` calls per chunk maximum (15 for `w=16`). For 64 message chunks + ~18 checksum chunks at `w=16`, total script is approximately 2,500–3,500 opcodes across Tapscript leaves. Feasible under Tapscript (no 201-opcode limit). |
| On-chain transaction cost | **Good.** ~82 hash reveals for 256-bit message at `w=16`; roughly 3× cheaper than Lamport in witness bytes. The additional label tree root commitment is a single 32-byte hash, negligible overhead. |
| Signature size | **Good.** Same as standard WOTS: ~82 × 32 = ~2,624 bytes witness for 256-bit message at `w=16`, versus ~8,192 bytes for Lamport. ~3× compression. |
| Garbled circuit input label encoding efficiency | **Excellent.** Labels are generated independently of the chain; standard binary garbling is unchanged. No label encoding overhead versus the Lamport baseline. The label tree commitment is a one-time 32-byte on-chain cost. |
| Off-chain computation and communication overhead | **Moderate.** Garbler must pre-generate all labels and commit to the label tree root before proof submission. This is a one-time setup cost. Off-chain label delivery requires the garbler to transmit the correct labels to the evaluator, which requires the garbler to be online at delivery time — a mild liveness requirement. |
| Security level | **Strong.** Label security rests on PRF security applied to `sk_i` (never revealed), eliminating chain leakage entirely. WOTS unforgeability provides on-chain authentication. The PRF assumption (e.g., HMAC-SHA256) is standard. Formal security requires a hybrid argument: WOTS unforgeability + PRF pseudorandomness + garbled circuit simulation security. |
| Script opcode compatibility | **Excellent.** Uses only `OP_SHA256`, `OP_EQUALVERIFY`, `OP_ADD`, and standard stack operations. No `OP_CAT` required. Fully compatible with current Bitcoin consensus. |
| Reduction in on-chain keys/commitments | **~3× at `w=16`, ~8× at `w=256`.** Full WOTS compression achieved. The label tree root replaces the per-bit Lamport public key array. |
| Round complexity | **Slightly increased.** Requires an off-chain label delivery step from garbler to evaluator after the on-chain WOTS signature is broadcast. This is one additional off-chain communication round versus the Lamport baseline, but no additional on-chain rounds. |
| Novelty | **Moderate-High.** The decoupled commit-then-authenticate construction is a principled and clean design. The key insight — using WOTS solely as an authenticator while keeping label generation independent — resolves the leakage problem in a structurally sound way. |

**Risks:** The liveness requirement for the garbler (must deliver labels off-chain after on-chain WOTS verification) could be a problem if the prover is non-cooperative after committing. If the prover withholds labels, the evaluator cannot proceed. This must be mitigated by a time-locked fallback or by including label delivery in the on-chain commitment, which partially undermines the compression. Additionally, the security argument requires careful composition of the WOTS authentication with the label commitment scheme; any gap in the binding between the WOTS-authenticated chunk value and the pre-committed label set could allow a malicious prover to swap labels post-commitment.

---

#### Direction B: Reversed Hash Chain with Bottom-Anchored Label Derivation

| Metric | Assessment |
|---|---|
| On-chain script size | **Good.** Script verification structure changes slightly: given revealed value `r_i`, Bitcoin Script must compute `H^{v_i}(r_i)` and check against `pk_i`. Since `v_i` is encoded in the signature and `pk_i = H^{w-1}(sk_i)`, the script applies `v_i` forward hashes to `r_i`. For `w=16`, up to 15 sequential `OP_SHA256` with conditional logic. Total script size comparable to standard WOTS. |
| On-chain transaction cost | **Good.** Same compression as standard WOTS; ~3× cheaper than Lamport for a 256-bit message at `w=16`. No additional on-chain data versus standard WOTS. |
| Signature size | **Good.** Identical to standard WOTS. ~82 × 32 bytes for a 256-bit message at `w=16`. |
| Garbled circuit input label encoding efficiency | **Good.** Labels derived directly from the revealed chain value via PRF; evaluator can compute correct labels immediately upon receiving the WOTS reveal without additional communication. Direct binding similar in spirit to Lamport, but with multi-bit chunks. No additional off-chain round for label delivery. |
| Off-chain computation and communication overhead | **Low.** Evaluator derives labels locally from the revealed `H^{w-1-v_i}(sk_i)` without contacting the garbler. Same interaction pattern as Lamport-based BitVM3. |
| Security level | **Good but requires careful analysis.** The key claim — that `H^{w-1-v_i}(sk_i)` does not leak labels for `v' > v_i` — is sound because `H^{w-1-v'}(sk_i)` for `v' > v_i` requires computing `H^{w-1-v'}(sk_i) = H^{v_i - v'}(H^{w-1-v_i}(sk_i))`, which requires *backward* hash computation, i.e., finding a preimage — computationally infeasible. Labels for `v' < v_i` (shallower positions, reachable by forward iteration) are derivable by the evaluator, but the WOTS checksum prevents forging signatures with smaller chunk values, so this leakage is benign from a WOTS security standpoint. **However**, the garbled circuit security model requires that non-selected labels remain computationally hidden from the evaluator — if the evaluator can derive labels for `v' < v_i`, this violates garbled circuit input privacy for those chunk values, potentially leaking information about the circuit. This requires explicit analysis. |
| Script opcode compatibility | **Excellent.** Same as standard WOTS verification; uses only `OP_SHA256` and comparison opcodes. |
| Reduction in on-chain keys/commitments | **~3× at `w=16`.** Full WOTS compression; no additional commitments needed. |
| Round complexity | **Unchanged.** Same round structure as Lamport-based BitVM3; no additional interactions. This is a significant advantage. |
| Novelty | **High.** The reversed chain direction as a structural mechanism to enforce one-wayness in the label-leakage direction is a non-obvious and technically precise contribution. |

**Risks:** The critical risk is the residual label leakage for values `v' < v_i`. Specifically, the evaluator who receives `H^{w-1-v_i}(sk_i)` can forward-iterate to compute `H^{w-1-v'}(sk_i)` for any `v' < v_i`, obtaining the PRF seeds for those chunk values and thereby deriving their labels. In a privacy-preserving garbled circuit, this may allow the evaluator to learn whether their chunk is consistent with certain values, potentially leaking information about the proof structure. Whether this constitutes a real attack depends on the semantic security requirements of the garbled circuit in the BitVM3 context. If the circuit does not require input privacy (only correctness), this leakage is acceptable. If input privacy is required, this direction is insecure as stated.

---

#### Direction C: Pre-Committed Encrypted Label Table

| Metric | Assessment |
|---|---|
| On-chain script size | **Good.** WOTS chain verification script is identical to Direction A. The encrypted label table is stored off-chain or in a Taproot leaf, not inline in the verification script. Bitcoin Script only verifies the WOTS chain and a hash commitment to the encrypted table. |
| On-chain transaction cost | **Moderate.** The encrypted label table (`w` ciphertexts per chunk × ~48 bytes each × ~82 chunks) totals approximately ~160KB for `w=16` — too large for direct on-chain storage. Must be committed via a Merkle root with individual ciphertexts revealed on-demand, or stored in a Taproot annex or off-chain with a hash anchor. This adds ~32 bytes on-chain for the commitment root but requires an off-chain availability assumption for the table itself. |
| Signature size | **Good.** On-chain WOTS signature is identical in size to standard WOTS. The encrypted table is off-chain; its cost is measured separately. |
| Garbled circuit input label encoding efficiency | **Good.** Evaluator decrypts exactly one ciphertext per chunk using the revealed WOTS chain value as the decryption key. Label retrieval is direct and non-interactive given the pre-committed table. The w ciphertexts per chunk cleanly encode the label-selection structure. |
| Off-chain computation and communication overhead | **Moderate.** Garbler must pre-compute and distribute `w × chunk_count` ciphertexts (~160KB for `w=16`, 256-bit message). This is a larger off-chain setup cost than Directions A or B but is a one-time garbling-time cost. Evaluator must download and decrypt the table, adding modest bandwidth overhead. |
| Security level | **Good with caveats.** Labels for `j > v_i` are derivable (forward chain iteration), but they decrypt to **wrong labels** in the garbled circuit by construction — the garbled circuit will not evaluate correctly for incorrect labels, providing soundness. Labels for `j < v_i` remain hidden (preimage hardness). The scheme is sound but not semantically hiding for higher-value chunks — a subtle point that requires the garbled circuit's security definition to explicitly account for "wrong label" distinguishability. If the garbled circuit encryptions are indistinguishable under wrong keys (which they should be under standard garbling), this is fine. |
| Script opcode compatibility | **Excellent.** On-chain script is pure WOTS verification; no special opcodes needed. |
| Reduction in on-chain keys/commitments | **~3× for on-chain WOTS payload.** The encrypted table is off-chain; only its 32-byte commitment hash is on-chain. This is actually a larger off-chain commitment than Directions A/B. |
| Round complexity | **Unchanged for on-chain; off-chain setup is non-interactive.** The encrypted table is pre-computed and published before the WOTS signature; no interactive label delivery needed at evaluation time. |
| Novelty | **Moderate.** Encrypted label tables are a known technique in garbled circuit literature; the novelty is in the specific binding to WOTS chain positions as decryption keys. |

**Risks:** The primary risk is **data availability of the encrypted label table**. If the garbler publishes the WOTS public key and commits the table hash on-chain but then refuses to reveal the table, the evaluator cannot proceed. This creates a griefing vector. Mitigation requires either on-chain table publication (expensive) or a data availability layer. Additionally, the security argument requires careful treatment of the "wrong label" decryption case — standard garbling schemes produce ciphertext that is indistinguishable from random under wrong keys, but this must be verified for the specific garbling scheme used.

---

#### Direction D: Two-Level WOTS-Lamport Hierarchy

| Metric | Assessment |
|---|---|
| On-chain script size | **Good.** On-chain script performs standard WOTS chain verification only; the Lamport sub-key derivation is entirely off-chain. Script size is identical to standard WOTS verification — approximately 3× smaller than pure Lamport. |
| On-chain transaction cost | **Good.** Same on-chain footprint as standard WOTS; ~3× fee reduction versus Lamport for a 256-bit message at `w=16`. |
| Signature size | **Good.** On-chain WOTS signature: ~82 × 32 bytes for a 256-bit message at `w=16`. The Lamport sub-keys are not revealed on-chain; they are delivered off-chain as part of the garbled circuit package. |
| Garbled circuit input label encoding efficiency | **Excellent.** The garbled circuit receives standard binary Lamport-style labels at the wire level. The 1-bit-to-1-label correspondence is fully preserved. No modification to the garbled circuit construction or evaluation algorithm is needed; only the label derivation provenance changes. This is the lowest-friction path for garbled circuit integration. |
| Off-chain computation and communication overhead | **Moderate.** The garbler must pre-derive all Lamport sub-keys `lk_{i,j,b}` from WOTS seed keys `sk_i` and deliver the correct sub-keys to the evaluator. This requires the garbler to be online at label delivery time. The internal verification sub-circuit that checks Lamport sub-key consistency with the WOTS-authenticated chunk value adds a small number of gates (roughly `log_2(w)` hash-check gates per chunk), which is negligible in a large circuit. |
| Security level | **Strong.** Label secrecy rests on PRF security with `sk_i` as the key (never revealed). WOTS chain revelation does not expose `sk_i`. The garbled circuit receives standard Lamport-style labels, and the security argument reduces directly to standard garbled circuit security plus WOTS unforgeability plus PRF pseudorandomness — all well-understood assumptions. This is the cleanest security argument of all directions. |
| Script opcode compatibility | **Excellent.** On-chain script is pure WOTS; same opcode compatibility as standard WOTS verification. |
| Reduction in on-chain keys/commitments | **~3× at `w=16`.** Full WOTS compression for on-chain data. The Lamport sub-keys are off-chain and impose no on-chain cost. |
| Round complexity | **Slightly increased.** Requires off-chain label delivery from garbler to evaluator (same liveness requirement as Direction A). One additional off-chain communication round versus baseline. |
| Novelty | **Moderate-High.** The two-level hierarchy — WOTS for on-chain authentication, Lamport sub-keys for off-chain label binding — is a clean composition that has not been explicitly studied in the BitVM literature. The novelty lies in the hierarchical key derivation structure and the internal verification sub-circuit. |

**Risks:** The key risk is the **liveness and correctness of the label delivery step**. The garbler must deliver the correct Lamport sub-keys `lk_{i,j, b_{i,j}}` off-chain to the evaluator after the on-chain WOTS signature is confirmed. If the garbler is malicious and delivers incorrect sub-keys (for a chunk value `v_i' ≠ v_i`), the evaluator will obtain wrong labels and the circuit will produce an incorrect output. The internal verification sub-circuit guards against this by checking that the delivered labels are consistent with the WOTS-authenticated chunk value, but this check must itself be correctly garbled — a subtle circular dependency that requires careful construction. Additionally, the off-chain delivery requirement assumes the garbler is live and cooperative, which may conflict with adversarial BitVM3 settings.

---

### 3. Chosen Direction

**Chosen: Direction B (Reversed Hash Chain with Bottom-Anchored Label Derivation) for contexts where garbled circuit input privacy is not required (correctness-only model), combined with Direction D's two-level derivation structure as a drop-in upgrade for contexts where input privacy is required.**

**Unified construction:** Use the reversed hash chain for on-chain WOTS authentication. For each chunk `i`, sign value `v_i` by revealing `r_i = H^{w-1-v_i}(sk_i)`. Derive binary input wire labels as `L_{i,j,b} = PRF(sk_i, i || j || b)` — anchored at `sk_i` itself (the chain bottom), not at the revealed value. The evaluator receives `r_i` on-chain and the labels `{L_{i,j, b_{i,j}}}` off-chain in the garbled circuit package (pre-committed by their hash on-chain before proof submission). Bitcoin Script verifies `H^{v_i}(r_i) == pk_i` and checks the label package hash commitment. This construction inherits Direction B's elegant reversed-chain structure for on-chain authentication and Direction D's PRF-from-seed label derivation for full garbled circuit input privacy. The residual leakage risk of Direction B alone is eliminated because labels are derived from `sk_i` (unreachable from `r_i`), and the reversed chain provides a cleaner security argument than the forward chain for the on-chain verification direction. The result is a single unified design with: full WOTS compression on-chain (~3× at `w=16`), standard binary garbled circuit structure unchanged, input privacy preserved, one-way label binding to the chain bottom, and Bitcoin Script compatibility using only `OP_SHA256` and basic stack opcodes.

---

### 4. Key Questions

1. **Hash chain leakage quantification**: For the reversed chain construction, for each chunk value `v_i ∈ [0, w-1]`, exactly which chain positions are computable by an evaluator who receives `r_i = H^{w-1-v_i}(sk_i)` via forward and backward iteration? Specifically: for `w=16`, how many of the 16 possible PRF seeds `{H^j(sk_i) : j ∈ [0,15]}` are derivable from `r_i`, and does this set depend monotonically on `v_i`? (Answer should confirm that only positions shallower than `w-1-v_i` are reachable, confirming the reversed chain's one-way barrier for deeper positions.)

2. **Bitcoin Script opcode budget for WOTS chain verification**: For `w ∈ {4, 16}` and a 256-bit STARK output hash (yielding 64 message chunks + ~18 checksum chunks at `w=16`), what is the exact opcode count and byte size of a Tapscript leaf implementing the full WOTS verification (hash chain unrolling, checksum computation, and public key comparison), and does it remain within Tapscript's 10,000-byte script size limit and 1,000-element stack limit?

3. **Checksum chunk count and garbled circuit input wire overhead**: For `w ∈ {4, 16, 256}` applied to message lengths `n ∈ {128, 256, 512}` bits, what is the exact number of checksum chunks generated by the WOTS checksum formula `C = Σ_{i}(w-1-v_i)`, how many additional input wires does this add to the garbled circuit, and what is the total input wire count relative to the Lamport baseline?

4. **PRF selection for label derivation — security and on-chain verifiability**: If a dispute arises requiring on-chain verification that delivered labels `L_{i,j,b}` were correctly derived from committed seed `sk_i` (e.g., in a fraud proof), which PRF construction (HMAC-SHA256, SHA256 in Merkle-Damgård mode, or AES-128 in counter mode) supports the most compact Bitcoin Script implementation of `PRF(sk_i, i || j || b)`, and what is the per-label script size in each case?

5. **One-time key enforcement mechanism**: What is the minimal on-chain construction (e.g., Taproot output with keypath spend nullification, or time-locked P2WSH) that enforces WOTS key single-use — preventing a prover from broadcasting two different WOTS signatures under the same public key for two different proof values — and what is its on-chain byte overhead relative to the core WOTS commitment transaction?

6. **Net compression ratio after checksum overhead at representative proof sizes**: For a 256-bit Fiat-Shamir challenge hash from a FRI-based STARK (the most plausible BitVM3 proof payload), compute the total on-chain bytes (signature witness + verification script + label commitment) for Lamport, WOTS `w=4`, WOTS `w=16`, and WOTS `w=256`, accounting for checksum chunks in each case. At what `w` does the marginal compression gain from increasing `w` become less than 10% over the next smaller `w`, indicating diminishing returns?

7. **Internal verification sub-circuit gate cost**: In the unified Direction B+D construction, the garbled circuit must include a sub-circuit that verifies the delivered labels `L_{i,j,b_{i,j}}` are consistent with the WOTS-authenticated chunk value `v_i` — specifically, it verifies that `PRF(sk_i, i || j || b_{i,j})` matches the committed label. How many garbled gates does this sub-circuit require per chunk for `w=16`, and what is its total gate overhead as a fraction of a representative 10M-gate STARK verification circuit?

8. **Security reduction formalization for the unified construction**: In the game-based security model, can the protocol security (no PPT adversary causes the garbled circuit to accept an invalid proof with non-negligible probability) be reduced in a modular hybrid argument to: (i) WOTS one-time unforgeability, (ii) PRF pseudorandomness of HMAC-SHA256, and (iii) garbled circuit simulation security under the half-gates scheme — and if so, what is the exact security loss (in bits) introduced by each hybrid step for the concrete parameters `w=16`, `n=256`, and 128-bit target security?
