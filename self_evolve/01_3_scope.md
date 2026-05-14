# 01 — Scope & Plan

**Topic:** In BitVM3, garbled circuits are used to do off-chain proof verification based on a signed proof put on the Bitcoin chain. The signed proof is input into the garbled circuit as input labels. In most existing designs, the signature scheme is a Lamport signature, which is verifiable by Bitcoin. Can you provide a re-design using Winternitz signatures instead of Lamport signatures?

**Note:** 

**Model:** `claude-sonnet-4-6`  
**Tokens:** in=3,302 out=5,774  
**Cost:** $0.0965

---

# Scope Document: Winternitz Signatures in BitVM3 Garbled Circuit Architecture

---

## 1. Candidate Solutions

### Direction A: Direct WOTS+ Integration with Unrolled Tapscript Verification (w=4)

Replace the Lamport signature with a WOTS+ scheme parameterised at w=4 (2 bits per digit), where each digit position's verification is encoded as a fully unrolled 4-branch `OP_IF/OP_NOTIF` tree in Tapscript. Each of the L chain positions occupies a dedicated Tapscript leaf (or a compact leaf verifying one digit via branch logic). Wire labels for the garbled circuit are derived directly from the hash chain intermediate values: `WireLabel(i, d) = SHA256(C_{i,d} || nonce)`, where `C_{i,d} = H^d(s_i)` is the value revealed in the signature. Bitcoin script verifies each digit by completing the chain to the committed public key value `H^3(s_i)`. The checksum digits are handled symmetrically — treated as additional digit positions with their own chain verifications — and all L = L₁ + L₂ chain values serve as inputs to the garbled circuit. This direction stays within currently deployed Bitcoin consensus rules (Taproot, SegWit v1), requiring no soft fork.

### Direction B: Batched WOTS Verification via Recursive Hash Accumulator with w=16

Use w=16 (4 bits per digit) and aggregate the hash chain verification across all L=67 digit positions into a single compact Bitcoin script using an **accumulator pattern**: the unlocking witness provides all `(C_{i,d_i})` values sequentially on the stack, and the locking script iterates through a fixed-length unrolled sequence of operations that (a) completes each chain to the corresponding public key, (b) accumulates a running hash of all verified chain values, and (c) compares the final accumulator hash against a pre-committed aggregate value. This avoids per-digit Tapscript leaves by collapsing all verification into one script execution path. The wire label derivation uses `WireLabel(i, d_i) = PRF(C_{i,d_i} || circuit_id)`. The checksum is verified as part of a separate compact script segment that recomputes the checksum from the revealed digit indices (extracted via a lookup table encoded in the script) and checks against the revealed checksum chain values. The aggregation approach critically reduces the number of Tapscript leaves from O(L×w) to O(1), at the cost of a larger single script body.

### Direction C: Digit-to-Bit Decomposition Layer with Hybrid WOTS/Lamport Interface

Adopt a two-layer architecture: the **outer layer** uses WOTS+ at w=16 for compact on-chain signature verification, and the **inner layer** inserts a deterministic bit-decomposition adapter that maps each WOTS digit-level wire label into `log₂(w) = 4` bit-level wire label pairs consumed by the garbled circuit's standard bit-level input wires. Specifically, for digit position i with revealed value `C_{i,d_i}`, the adapter generates 4 bit wire labels as `BitLabel(i, j, b) = SHA256(C_{i,d_i} || i || j || b)` for bit position j ∈ {0,1,2,3} and bit value b ∈ {0,1}, where only `b = bit_j(d_i)` labels are revealed. The garbled circuit constructor generates both labels for each bit position but only the correct one is derivable from the on-chain `C_{i,d_i}`. This preserves full bit-level wire label semantics inside the garbled circuit while benefiting from WOTS compression at the Bitcoin layer. Bitcoin script verification follows the w=16 unrolled chain pattern with Tapscript branching. The adapter layer is computed entirely off-chain.

### Direction D: WOTS with OP_CAT-Enabled Compact Script (BIP-347 Contingent)

Design a BitVM3 WOTS integration that targets the proposed `OP_CAT` soft fork (BIP-347), using `OP_CAT` to construct and verify hash chain values inline within Bitcoin Script without explicit loop unrolling. With `OP_CAT`, a script can concatenate a running chain value with a fixed-length domain separator, apply `OP_SHA256`, and repeat this pattern compactly using recursive Tapscript introspection or covenant-style verification, reducing per-chain script size from O(w) opcodes to O(log w). The wire label binding uses `WireLabel(i, d) = SHA256(C_{i,d} CAT circuit_commitment)`, where the `CAT` operation is also used in the script itself to enforce the binding. Checksum verification becomes a compact arithmetic check enabled by `OP_CAT`-composed multi-byte arithmetic. This direction achieves the smallest possible script footprint for WOTS verification but is contingent on a soft fork that has not yet activated.

### Direction E: Pre-Computed Witness Table WOTS (Offline Garbling Optimisation)

Rather than modifying Bitcoin script verification, pre-commit the full WOTS hash chain for all digit positions in the garbled circuit's **input table** at circuit garbling time. The prover generates the complete chain `(s_i, H(s_i), H²(s_i), ..., H^{w-1}(s_i))` for each position i, and encodes all `w` possible wire labels per position in the garbled circuit's input encoding table — identical in structure to garbled circuit input encoding under the Free-XOR or Half-Gates scheme. Bitcoin script verification is kept minimal: it only checks the top of the chain against the public key for the single revealed digit per position, amounting to exactly one `OP_SHA256` and one `OP_EQUALVERIFY` per digit position regardless of d_i. The chain completion for verifying the revealed value is pushed entirely into the **unlocking witness**: the signer provides the full chain from `C_{i,d_i}` to `C_{i,w-1}` as an explicit witness suffix. This eliminates data-dependent branching from Bitcoin script entirely, at the cost of a larger witness per transaction, and preserves clean wire label binding via the pre-committed input table.

---

## 2. Evaluate Directions

### Direction A: Direct WOTS+ with Unrolled Tapscript (w=4)

| Metric | Assessment |
|---|---|
| **On-chain script size** | Moderate. Each digit position requires a 4-branch `OP_IF` tree ≈ 80–120 bytes per leaf. For L ≈ 136 digits (w=4, 256-bit proof), total script size ≈ 11–16 KB across leaves, within Tapscript limits but non-trivial |
| **On-chain transaction cost** | Moderate. Signature witness data ≈ 136 × 32 = 4,352 bytes. Witness discount applies; estimated ~2,500–3,000 vBytes per verification transaction |
| **Signature size** | ~4,352 bytes for 256-bit proof at w=4. Approximately 2× reduction over Lamport (~8 KB). Not maximum compression but achievable without soft forks |
| **GC input label compatibility** | Clean. Direct mapping: each of the 136 chain values `C_{i,d_i}` maps to one wire label group. Bit-level adapter not required if garbled circuit is designed at digit granularity (2-bit inputs per group) |
| **Cryptographic security** | Full 128-bit security under SHA-256 one-wayness. WOTS+ bitmask XORs provide tight security reduction. One-time property preserved by protocol structure |
| **Off-chain computation** | Minimal overhead vs. Lamport. Garbling 136 digit-level inputs vs. 256 bit-level inputs is comparable. Chain generation is O(L×w) = O(544) SHA-256 calls |
| **Script expressibility** | Good. w=4 requires only 4 cases per digit, cleanly expressible with 3 nested `OP_IF` opcodes per leaf. No soft fork required. Compatible with current Tapscript |
| **Soundness under composition** | Sound. One-time use enforced by the connector output structure. Checksum prevents digit substitution attacks. Tapscript spending enforces single-path execution |
| **Parameter flexibility** | Limited flexibility at w=4; the choice is conservative. Migrating to w=8 or w=16 would require redesigning scripts |
| **Novelty** | Moderate. Straightforward application of WOTS+ to BitVM3 with minimal architectural innovation beyond the direct substitution |

**Risks:** Script size may breach practical limits when combined with other BitVM3 script logic in the same leaf. The 2× improvement over Lamport may be insufficient motivation compared to the added complexity of chain-depth verification.

---

### Direction B: Batched WOTS with Accumulator (w=16)

| Metric | Assessment |
|---|---|
| **On-chain script size** | Potentially problematic. A single script body encoding 67 positions × 16-case branching unrolled inline could reach 50–100 KB, exceeding Bitcoin's 10 KB standard script size limit and pushing Tapscript limits |
| **On-chain transaction cost** | Lower witness data volume (67 × 32 = 2,144 bytes of chain values) but the large script itself contributes heavily to transaction weight |
| **Signature size** | Optimal: ~2,144 bytes for 256-bit proof at w=16, plus ~96 bytes of checksum digits = ~2,240 bytes total. Best-in-class compression among script-compatible approaches |
| **GC input label compatibility** | Moderate complexity. The accumulator pattern obscures the one-to-one mapping between chain value and wire label; extra care needed to ensure the binding is preserved end-to-end |
| **Cryptographic security** | Full 128-bit security. Aggregation does not weaken the one-way binding, only compresses script logic |
| **Off-chain computation** | Minor additional overhead for accumulator precomputation. Otherwise comparable to Direction A |
| **Script expressibility** | Problematic. Inline unrolling of 67 × 16-branch verification exceeds practical script size limits. The accumulator hash design requires careful engineering to fit within opcode and stack limits |
| **Soundness under composition** | Sound in principle, but the aggregated verification introduces a new attack surface: a malicious prover might exploit script logic bugs in the accumulator to pass invalid signatures. Requires rigorous formal verification of the script |
| **Parameter flexibility** | High — w=16 achieves maximum compression for the 256-bit proof case without soft forks |
| **Novelty** | High. The accumulator batching technique for WOTS is non-trivial and could generalise to other Bitcoin script verification contexts |

**Risks:** Script size is the fatal risk. Bitcoin's 10 KB script size limit (and Tapscript's per-leaf limits) may make the inline accumulator approach infeasible without further decomposition. The complexity of a single monolithic verification script is a significant auditability and correctness risk.

---

### Direction C: Digit-to-Bit Decomposition Adapter (w=16, Two-Layer)

| Metric | Assessment |
|---|---|
| **On-chain script size** | Moderate-to-large. Bitcoin script still needs to verify the WOTS signature at w=16, which requires 16-branch unrolling per digit (67 digits). Script size ≈ 25–40 KB across Tapscript leaves |
| **On-chain transaction cost** | Similar to Direction B for signature witness. Additional cost from larger garbled circuit due to bit-decomposition sub-structure |
| **Signature size** | ~2,240 bytes (same as Direction B, w=16) — optimal compression for the on-chain signature itself |
| **GC input label compatibility** | Excellent. The adapter layer explicitly bridges the digit/bit mismatch, producing a fully standard bit-level garbled circuit interface. Circuit designers need not know about WOTS internals |
| **Cryptographic security** | Sound, provided the adapter derivation `BitLabel(i, j, b) = SHA256(C_{i,d_i} \|\| ...)` is collision-resistant and the correct-bit extraction is injective. Formal proof required that the adapter preserves the binding |
| **Off-chain computation** | Moderate additional overhead. Prover must generate 4 bit-label pairs per digit position (4 × 67 = 268 bit-level labels) vs. 67 in the direct approach. Garbled circuit size increases accordingly for the adapter sub-circuit |
| **Script expressibility** | Identical challenges to Direction B for the Bitcoin-side verification. No simplification from the adapter layer (which is entirely off-chain) |
| **Soundness under composition** | Strong. The two-layer design provides clear separation of concerns: Bitcoin enforces WOTS soundness, the adapter enforces bit-level consistency, and the garbled circuit enforces computation correctness |
| **Parameter flexibility** | High at the Bitcoin layer; the adapter design is parameterisable over w |
| **Novelty** | High. The adapter abstraction layer is a genuine architectural contribution enabling plug-and-play compatibility between WOTS-compressed signatures and standard bit-level garbled circuit frameworks |

**Risks:** The adapter layer introduces an additional cryptographic assumption (the security of the label derivation function) that must be formally proven. The extra garbled circuit complexity may partially offset the on-chain savings. Script size for w=16 verification remains a concern.

---

### Direction D: WOTS with OP_CAT (BIP-347 Contingent)

| Metric | Assessment |
|---|---|
| **On-chain script size** | Excellent — potentially 5–10× smaller than unrolled approaches if `OP_CAT` enables compact chain composition. Estimated 2–5 KB total for 67-position WOTS at w=16 |
| **On-chain transaction cost** | Lowest among all directions if soft fork activates. Script size reduction directly reduces transaction weight |
| **Signature size** | Same as Direction B (~2,240 bytes at w=16) — the on-chain witness improvement is identical, only the script encoding changes |
| **GC input label compatibility** | Same as Direction B. The `OP_CAT`-based circuit commitment binding is elegant and compact |
| **Cryptographic security** | Full 128-bit security. `OP_CAT` itself does not weaken cryptographic assumptions; it only affects script expressibility |
| **Off-chain computation** | Minimal overhead compared to Lamport. Equivalent to Direction B off-chain |
| **Script expressibility** | Outstanding — with `OP_CAT`, hash chain verification becomes a compact loop-like pattern. This is the natural Bitcoin-native solution if the opcode is available |
| **Soundness under composition** | Strong. `OP_CAT`-based scripts can enforce strict witness structure, potentially enabling tighter binding between signature and garbled circuit evaluation |
| **Parameter flexibility** | Maximum — with `OP_CAT`, adjusting w requires only script template changes, not architectural redesign |
| **Novelty** | Very high. First formal treatment of WOTS in a BitVM context using `OP_CAT` would be a significant contribution to both the BitVM and Script research communities |

**Risks:** The entire direction is contingent on BIP-347 soft fork activation, which is uncertain and outside the researchers' control. Any publication is immediately obsolete if the fork does not activate. The research contribution is conditional on an external political/technical process, making it unsuitable as the primary solution direction for an immediate deployment target.

---

### Direction E: Pre-Computed Witness Table WOTS

| Metric | Assessment |
|---|---|
| **On-chain script size** | Excellent — smallest script of all directions. Each digit position requires only: push `pubkey[i]`, `OP_SHA256` (applied once to the top of the witness-provided chain), `OP_EQUALVERIFY`. Total script ≈ 67 × ~40 bytes = ~2,680 bytes — well within all limits |
| **On-chain transaction cost** | Moderate-to-high witness cost. For each digit, the witness must include the chain suffix from `d_i` to `w-1`, i.e., `(w-1-d_i)` additional hash values. Worst case: `(w-1)` additional values per digit. For w=16, worst-case witness ≈ 67 × 15 × 32 = 32,160 additional bytes — unacceptably large |
| **Signature size** | Variable and potentially large. Best case (all `d_i = w-1`): only 67 × 32 = 2,144 bytes. Worst case: up to 67 × 16 × 32 = 34,304 bytes. Average case for uniform digits: 67 × 8 × 32 ≈ 17,152 bytes — worse than Lamport |
| **GC input label compatibility** | Excellent. The pre-committed input table directly contains all `w` wire labels per position. Evaluation simply looks up the label for the revealed digit. Clean, simple, and secure |
| **Cryptographic security** | Sound for script verification (one SHA256 check is sufficient). However, the prover provides the full chain suffix in the witness, which is public — this is fine since the chain is forward-hash-only, but requires careful analysis that intermediate chain values cannot be exploited |
| **Off-chain computation** | Lowest off-chain overhead. Pre-computing the input table is O(L×w) hashes, and garbled circuit generation is unchanged from standard practice |
| **Script expressibility** | Best of all directions. Completely eliminates data-dependent branching. Each digit's script is identical and requires no `OP_IF` logic whatsoever |
| **Soundness under composition** | Strong. The script is maximally simple, reducing the attack surface. One-time property preserved by connector outputs |
| **Parameter flexibility** | High. Changing w only changes how many chain suffix values appear in the witness, with no script changes required |
| **Novelty** | Moderate. The witness-suffix technique is known in signature literature but its application to BitVM3's garbled circuit binding is a meaningful architectural contribution. The pre-committed input table design is novel in context |

**Risks:** The variable and potentially very large witness size is the critical flaw. The worst-case witness size for w=16 is larger than Lamport, completely defeating the purpose of Winternitz compression. This direction optimises the wrong metric (script size) at the expense of the most important one (on-chain data / fees).

---

## 3. Chosen Direction

**Selected Direction: A + C Combined — Direct WOTS+ Tapscript Verification (w=4) with a Digit-to-Bit Adapter Layer**

The optimal solution combines the script-feasibility of Direction A (w=4, fully unrolled 4-branch Tapscript, no soft fork required) with the clean garbled circuit interface of Direction C's adapter layer. Specifically: Bitcoin-side verification uses WOTS+ at **w=4** (2 bits per digit), keeping per-leaf scripts to ≈80–120 bytes and the total across all ≈136 digit positions within practical Tapscript bounds. The adapter layer converts each 2-bit digit wire label into 2 individual bit-level wire label pairs for the garbled circuit, preserving full compatibility with standard bit-level garbled circuit implementations. This combination is the only direction that simultaneously satisfies all hard constraints — no soft fork dependency, fits within Bitcoin's script limits, achieves a meaningful signature compression (~2× over Lamport at w=4, extendable to w=16 in a future BIP-347-enabled version), and delivers a clean, formally analysable interface between the WOTS chain values and the garbled circuit's input encoding. The two-layer architecture also yields a reusable design pattern: the adapter abstraction decouples signature scheme compression from garbled circuit semantics, enabling future upgrades (e.g., to w=8 or w=16) without modifying the garbled circuit layer.

**Concrete parameter choice:** w=4, 256-bit proof message → L₁ = 128 digit positions + L₂ ≈ 8 checksum positions = **136 total chain positions**, producing a ~4,352-byte on-chain signature (2× Lamport reduction) with 136 Tapscript leaves of ≈100 bytes each (≈13.6 KB total committed script, amortised across the Taproot tree).

---

## 4. Key Questions

1. **What is the exact Tapscript byte budget consumed by a single WOTS+ digit verification leaf at w=4, including all stack operations, public key pushes, and branch logic — and does the aggregate across 136 leaves remain within the Taproot annex and per-script limits when combined with the BitVM3 connector output and challenge-response scripts in the same transaction?**

2. **Can the checksum of WOTS+ at w=4 (with L₁=128 message digits, maximum checksum value = 128×3 = 384, requiring L₂=5 checksum digits at w=4) be verified in Bitcoin Script without introducing additional branching complexity, and specifically: can the script recompute the checksum from witness-revealed digit indices and compare against the revealed checksum chain values within the opcode and stack size constraints?**

3. **Does the digit-to-bit adapter layer — mapping each 2-bit WOTS digit wire label `C_{i,d_i}` to two bit-level garbled circuit wire labels via `BitLabel(i, j, b) = SHA256(C_{i,d_i} || i || j || b)` — preserve the simulation-based security of the garbled circuit, specifically: does an adversary who observes only the correct bit labels learn nothing about the garbled circuit beyond the evaluated output, assuming SHA-256 is a random oracle?**

4. **What is the precise on-chain vByte cost of a full BitVM3 challenge-response protocol round using WOTS+ at w=4, compared to the Lamport baseline — accounting for the signature witness data (4,352 vs. ~8,192 bytes), Tapscript execution costs, and any additional transactions required for checksum verification — and at what Bitcoin fee rate does the WOTS+ redesign produce measurable cost savings?**

5. **Is the one-time signature property of WOTS+ preserved under the BitVM3 bisection protocol, where the prover may be required to sign and reveal multiple related messages across challenge rounds — specifically, can the connector output structure be designed to cryptographically enforce that the same WOTS key pair is never used to sign two distinct messages, even if the prover is incentivised to equivocate?**

6. **For the chosen parameter w=4 with SHA-256, what is the concrete bit-security of WOTS+ against existential forgery under chosen-message attack, and does the security level degrade when the same hash function (SHA-256) is used both for chain hashing and for wire label derivation in the adapter layer — i.e., is domain separation via the `|| i || j || b` suffix sufficient, or is a dedicated PRF (e.g., HMAC-SHA256) required?**

7. **Can the 136 Tapscript leaves (one per digit position) be arranged into a Taproot tree such that the most frequently spent leaves (e.g., checksum positions with predictable digit values) are placed at minimal Merkle depth, and what is the resulting average-case Merkle proof overhead in vBytes compared to a balanced tree arrangement?**

8. **What is the minimum modification required to an existing open-source BitVM implementation (e.g., BitVM2 or BitVM Bridge) to replace the Lamport signature module with the WOTS+ w=4 module plus adapter layer — specifically, which interfaces change (key generation, signing, Bitcoin script generation, wire label binding), which remain identical, and what is the estimated implementation complexity in lines of code?**
