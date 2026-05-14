# 01 — Scope & Plan

**Topic:** In BitVM3, garbled circuits are used to do off-chain proof verification based on a signed proof put on the Bitcoin chain. The signed proof is input into the garbled circuit as input labels. In most existing designs, the signature scheme is a Lamport signature, which is verifiable by Bitcoin. Can you provide a re-design using Winternitz signatures instead of Lamport signatures?

**Note:** 

**Model:** `claude-sonnet-4-6`  
**Tokens:** in=3,302 out=5,774  
**Cost:** $0.0965

---

# Winternitz Signatures in BitVM3: Improved Candidate Solutions

---

### 1. Candidate Solutions

---

**Direction A: WOTS+ at w=4 with Per-Digit Tapscript Leaves and GC-Side Checksum Verification**

Deploy WOTS+ with w=4 (2 bits per digit) where each of the L₁=128 message digit positions occupies a dedicated Tapscript leaf encoding a fully unrolled 4-branch `OP_IF/OP_NOTIF` tree. Each leaf both (a) verifies the hash chain depth for the revealed digit `C_{i,d_i}` by applying the appropriate number of SHA-256 operations to reach `H³(sᵢ)`, and (b) pushes the digit value `d_i` as a numeric constant within the taken branch, making `d_i` explicitly available on the stack as a side-effect of the chain verification. The checksum is **not** verified in Bitcoin Script; instead, all `L = L₁ + L₂ = 133` chain values (message + checksum digits) are fed as inputs to the garbled circuit, and a small sub-circuit within the GC recomputes the checksum from the message digit labels and verifies consistency. Bitcoin script enforces only chain-depth correctness; the GC enforces arithmetic consistency of the checksum. Wire labels are bound as `WireLabel(i, d) = HMAC-SHA256(C_{i,d}, context_i)` where `context_i` encodes position and circuit identifier for domain separation. The Taproot tree contains 133 leaves arranged by spending frequency; the prover reveals one leaf per digit position per transaction step.

---

**Direction B: WOTS+ at w=8 with Unrolled Tapscript and Bit-Decomposition Adapter Layer**

Deploy WOTS+ with w=8 (3 bits per digit) to achieve approximately 3× compression over Lamport while keeping per-leaf scripts tractable: each digit position requires an 8-branch `OP_IF` tree, producing leaf scripts of approximately 200–280 bytes. For a 256-bit proof: L₁=86 message digits + L₂=4 checksum digits = 90 total positions. A **digit-to-bit adapter layer** operates entirely off-chain: each revealed chain value `C_{i,d_i}` deterministically generates 3 bit-level wire label pairs via `BitLabel(i, j, b) = HMAC-SHA256(C_{i,d_i}, i || j || b)` for bit position `j ∈ {0,1,2}` and bit value `b ∈ {0,1}`, where only labels with `b = bit_j(d_i)` are derivable by the evaluator. This adapter preserves full compatibility with standard bit-level garbled circuit frameworks (Bellare-Hoang-Rogaway semantics), decoupling the Bitcoin-layer signature compression from the GC layer's bit-granular operation. Checksum verification is handled by the GC sub-circuit as in Direction A. The Taproot tree holds 90 leaves; the key-to-leaf commitment is published in the setup transaction's `OP_RETURN` output.

---

**Direction C: WOTS+ at w=4 with Aggregated Checksum Leaf and Merkle-Depth-Optimised Tree**

Deploy WOTS+ at w=4 where the 128 message digit leaves each verify chain depth via the 4-branch unrolled pattern, and a **single dedicated aggregation leaf** handles the entire checksum: it takes the 5 checksum digit chain values from the witness plus 128 numeric digit-value witnesses (each being the `d_i` constant from the corresponding message leaf, re-provided here as a compact integer), computes their sum using Bitcoin Script's native `OP_ADD` operations (maximum sum = 3×128 = 384 < 2³¹, safely within CScriptNum bounds), and verifies the sum against the 5 revealed checksum chain values by completing their chains to the committed public keys. This consolidates all checksum arithmetic into one leaf rather than distributing it or delegating it to the GC. The Merkle tree is constructed with **Huffman-weighted depth assignment**: checksum digits (always spent together) occupy shallow positions, and message digit leaves are arranged by expected spending frequency based on proof hash statistics. Wire labels use `HMAC-SHA256(C_{i,d_i}, domain_i)` with explicit domain separation. The key question this direction answers concretely is whether inter-leaf checksum accumulation is achievable under current Bitcoin Script constraints without a soft fork.

---

**Direction D: WOTS+ at w=16 with Signature-to-Label Binding via Committed Input Table (No Script-Side Chain Unrolling)**

Reframe the verification architecture: rather than encoding w-branch unrolling in Tapscript, restructure the protocol so that the **locking script performs only one SHA-256 and one OP_EQUALVERIFY per digit**, eliminating data-dependent branching entirely from Script. The mechanism: the signer provides, in the unlocking witness for each digit position, not only `C_{i,d_i}` but also the **chain suffix** `(C_{i,d_i+1}, ..., C_{i,w-1})` — the remaining chain values from the revealed point to the public key. The locking script applies a fixed single SHA-256 to the top of the suffix and checks it equals the next value in sequence, ending at `pubkey[i] = H^(w-1)(sᵢ)`. Critically, to prevent the witness bloat that makes naïve Direction E unacceptable, the design constrains `d_i` to the **upper half of the range** by protocol convention: the message is re-encoded so all digit values satisfy `d_i ≥ w/2`, ensuring the suffix length is at most `w/2 - 1 = 7` values per digit. For w=16 and 67 total positions, worst-case suffix witness ≈ 67 × 7 × 32 = 14,976 bytes, and **average-case ≈ 67 × 3.5 × 32 ≈ 7,500 bytes** — competitive with Lamport's ~8,192 bytes while delivering 4× compression on the primary signature reveal (`C_{i,d_i}` alone = 67 × 32 = 2,144 bytes). The wire label binding uses the committed input table: all `w = 16` wire labels per position are pre-committed in the garbled circuit's input encoding, and the on-chain revelation of `C_{i,d_i}` (together with the publicly verified chain suffix) uniquely indexes the correct label.

---

**Direction E: Hybrid Lamport-WOTS Architecture with Selective Compression**

Rather than replacing Lamport entirely, apply WOTS+ compression **selectively** to the high-entropy portion of the proof while retaining Lamport for low-entropy or structurally constrained portions. Concretely: partition the 256-bit proof hash into (a) a 192-bit "bulk" segment encoded under WOTS+ at w=8 (64 digits, ~3× compression), and (b) a 64-bit "tail" segment retained as Lamport (64 bits, 1-to-1). The WOTS+ segment produces 64 + 3 (checksum) = 67 chain positions; the Lamport segment produces 64 bit positions. Bitcoin Script verification uses per-leaf unrolled Tapscript for the WOTS+ digits (8-branch trees, ~200 bytes/leaf) and standard single-hash Lamport leaves for the tail segment. Wire label binding is uniform across both segments: all labels use `HMAC-SHA256(revealed_value, domain)`. The architectural benefit is that the Lamport segment handles bits near the proof hash's checksum interface without introducing WOTS arithmetic complexity, and the system degrades gracefully: if WOTS verification is ever found to have a Bitcoin Script incompatibility, the Lamport fallback maintains protocol liveness. Total on-chain signature witness: ~2,144 (WOTS) + 2,048 (Lamport tail) ≈ 4,192 bytes — roughly 2× improvement over full Lamport.

---

### 2. Evaluate Directions

---

#### Direction A: WOTS+ w=4, GC-Side Checksum

| Metric | Assessment |
|---|---|
| **On-chain script size** | Each of 133 leaves: ~80–120 bytes (4-branch tree + pubkey push + chain verification). Total committed script: ~10.6–16 KB across the Taproot tree. Per-transaction Merkle proof overhead: 8 levels × 32 bytes = 256 bytes per digit spent. Well within per-leaf Tapscript limits (~10 KB per leaf). |
| **On-chain transaction cost** | Witness per digit reveal: 1 × 32 bytes (chain value) + 256 bytes (Merkle proof) + ~50 bytes (script execution metadata) ≈ 338 bytes/digit. For a full 133-position reveal: ~44,954 bytes witness total. At witness discount (×0.25 weight), this is ~11,239 vBytes. Compare Lamport: 256 × (32 + 256 + 50) ≈ 73,728 bytes witness → ~18,432 vBytes. Approximate 40% fee reduction. |
| **Signature size** | 133 × 32 = 4,256 bytes of chain values on-chain. Approximately 1.9× reduction over Lamport (~8,192 bytes). Modest but meaningful; the compression ratio is honest at w=4 after accounting for L₂=5 checksum digits. |
| **GC input label compatibility** | Clean. Each of 133 `C_{i,d_i}` values directly derives one wire label group via HMAC-SHA256 with domain separation. The GC sub-circuit for checksum verification adds ~40 AND/XOR gates — negligible overhead. No digit-to-bit adapter required if the GC is designed with 2-bit input groups (natural for WOTS at w=4). |
| **Cryptographic security** | 128-bit security under SHA-256 one-wayness. WOTS+ bitmask XORs provide tight reduction from the multi-function hash family assumption. Domain separation via HMAC prevents length-extension and cross-context collisions between chain hashing and label derivation. |
| **Off-chain computation** | Garbling 133 2-bit groups vs. 256 1-bit groups: comparable GC size (133 2-bit gates ≈ 266 1-bit equivalent wires). Chain generation: 133 × 3 = 399 SHA-256 calls at keygen. Signing: at most 133 SHA-256 calls. Minimal overhead vs. Lamport. |
| **Bitcoin script expressibility** | Excellent at w=4. Each 4-branch tree requires 3 `OP_IF/OP_NOTIF` opcodes plus hash operations. The digit-value constant is pushed within each branch, enabling downstream use. No soft fork required. Standard Tapscript v1. |
| **Soundness under protocol composition** | Sound. The setup transaction commits to `Hash(WOTS_pubkey_set)` in a `P2TR` output; the response transaction's Tapscript leaf verifies the public key against this commitment before executing chain verification. One-time use enforced by connector outputs: the UTXO spending the WOTS-committed output is destroyed after first reveal, preventing re-signing. GC-side checksum verification means a manipulated checksum produces incorrect GC output, caught by the verifier. |
| **Parameter flexibility** | Limited. w=4 is the conservative choice. Upgrading to w=8 requires redesigning all leaf scripts. However, the GC-side checksum design and HMAC label binding are parameter-agnostic and port cleanly to higher w. |
| **Novelty** | Moderate. The key novel contribution is delegating checksum verification to the garbled circuit, cleanly separating Bitcoin's role (chain-depth enforcement) from the GC's role (arithmetic consistency). This separation principle generalises to other WOTS variants and is a reusable architectural insight. |

**Risks:** The 1.9× compression over Lamport is weak justification for the added complexity. The GC checksum sub-circuit introduces a new correctness requirement: if the sub-circuit has a bug, a malicious prover can pass an invalid checksum. Requires formal circuit verification of the checksum component. The per-round witness size (~44 KB) may still be prohibitive at high fee rates.

---

#### Direction B: WOTS+ w=8, Bit-Decomposition Adapter Layer

| Metric | Assessment |
|---|---|
| **On-chain script size** | Each of 90 leaves: ~200–280 bytes (8-branch tree). Total committed script: ~18–25 KB. Merkle proof overhead: ⌈log₂(90)⌉ = 7 levels × 32 bytes = 224 bytes per digit. Per-leaf size remains within Tapscript's ~10 KB limit, but the 8-branch unrolling requires careful opcode counting: 7 nested `OP_IF` opcodes + 4 SHA-256 calls per branch (average) + pubkey push ≈ 85 opcodes per leaf. Within the 201-opcode per-script limit only if structured carefully. |
| **On-chain transaction cost** | Witness per digit: 32 (chain value) + 224 (Merkle proof) + ~50 (metadata) ≈ 306 bytes. For 90 positions: ~27,540 bytes → ~6,885 vBytes after witness discount. Approximately 63% reduction over Lamport baseline (~18,432 vBytes). Strong practical improvement. |
| **Signature size** | 90 × 32 = 2,880 bytes of chain values. ~2.8× reduction over Lamport. After checksum (4 positions): 90 × 32 = 2,880 bytes total — comfortably the best in the no-soft-fork space. |
| **GC input label compatibility** | Excellent via the adapter layer. Each `C_{i,d_i}` produces 3 bit-level label pairs `{BitLabel(i,j,0), BitLabel(i,j,1)}` for j∈{0,1,2}; only one label per bit is derivable from the revealed chain value. The garbled circuit receives a standard bit-level interface identical to the Lamport case. The adapter is purely off-chain with no on-chain footprint. Security follows from HMAC-SHA256 PRF security: given `C_{i,d_i}`, `BitLabel(i,j, b≠bit_j(d_i))` is computationally indistinguishable from random under the PRF assumption. |
| **Cryptographic security** | 128-bit security under SHA-256. WOTS+ bitmask XORs provide tight security reduction. The adapter's HMAC derivation is secure provided `C_{i,d_i}` is computationally unpredictable to an adversary who only knows the public key — which holds by the one-wayness of the hash chain for the correct digit value. The wrong-digit labels are computationally hidden even given all public keys. |
| **Off-chain computation** | Garbling with adapter: 90 positions × 3 bits = 270 bit-level wire pairs, comparable to Lamport's 256. Additional PRF calls for adapter: 90 × 3 × 2 = 540 HMAC-SHA256 calls — negligible. Chain generation: 90 × 7 = 630 SHA-256 calls at keygen. Signing: at most 90 SHA-256 calls. |
| **Bitcoin script expressibility** | Feasible but requires careful engineering. 8-branch `OP_IF` trees with depth 3 (since 2³=8) can be structured as balanced binary trees: each internal node is one `OP_IF/OP_ELSE`, consuming 3 `OP_IF` opcodes and up to 4 SHA-256 calls per leaf. Script size per leaf: 200–280 bytes, safely under the 10 KB limit. Opcode count per leaf: ~60–90, within the 201-opcode limit. Requires systematic script generation (no hand-coding); a script template engine is essential. |
| **Soundness under protocol composition** | Strong. The two-layer architecture provides clear separation: Bitcoin enforces WOTS chain validity; the adapter enforces bit-label uniqueness; the GC enforces computation correctness. One-time use enforced identically to Direction A via connector outputs. The adapter's wrong-label indistinguishability ensures an adversary cannot extract the other-bit label even after observing the on-chain `C_{i,d_i}`. |
| **Parameter flexibility** | High within the w=8 choice. The adapter layer is fully parameterisable over w; changing to w=4 or w=16 requires only regenerating the script templates and adjusting the adapter's bit-decomposition width. |
| **Novelty** | High. The adapter abstraction as a formally analysable cryptographic component — not just an engineering shim — is a genuine contribution. The formal claim that "HMAC-PRF-based bit-decomposition preserves GC simulation security" is a provable statement with a clear proof sketch, making this a publishable cryptographic contribution. |

**Risks:** The 8-branch leaf scripts push against practical opcode limits. A script generation bug producing an incorrect branch structure could allow a malicious prover to pass invalid signatures undetected — requires formal verification of the generated scripts or a mechanically checked script template. The adapter's security proof requires `C_{i,d_i}` to be a pseudorandom PRF key from the adversary's perspective, which holds under hash chain one-wayness but requires careful statement (the adversary knows all public keys, which are `H^7(sᵢ)` values, and can partially constrain `C_{i,d_i}` values for wrong digits).

---

#### Direction C: WOTS+ w=4, Aggregated Checksum Leaf

| Metric | Assessment |
|---|---|
| **On-chain script size** | 128 message digit leaves at ~100 bytes each = ~12.8 KB. One aggregation leaf encoding 128 `OP_ADD` operations + 5 chain verifications ≈ 128 × 4 (push+add) + 5 × 40 (chain checks) ≈ 712 bytes. Merkle tree: 129 leaves, depth ⌈log₂(129)⌉ = 8, proof = 256 bytes. All within Tapscript limits. |
| **On-chain transaction cost** | Same signature witness as Direction A (~4,256 bytes of chain values). The aggregation leaf spend requires providing 128 digit-value witnesses (128 × 1 byte = 128 bytes) plus 5 checksum chain values (160 bytes) plus Merkle proof (256 bytes) ≈ 544 bytes extra for the checksum transaction step. Total across full protocol: comparable to Direction A, ~10,800–11,500 vBytes. |
| **Signature size** | Identical to Direction A: 133 × 32 = 4,256 bytes. 1.9× reduction over Lamport. |
| **GC input label compatibility** | Same as Direction A for message digits. Checksum digit labels are also fed to the GC, but the GC sub-circuit is eliminated — Bitcoin Script handles checksum arithmetic. Slightly cleaner GC (no arithmetic gates needed), at the cost of the aggregation leaf's Script complexity. |
| **Cryptographic security** | 128-bit security. The aggregation leaf's critical security property: it must be infeasible for a prover to provide digit-value witnesses that sum to the correct checksum without the actual `d_i` values. This holds provided the 128 digit-value witnesses are **bound to** the chain values proved in the message digit leaves. The critical open problem: Tapscript does not natively pass state between leaves. The digit-value witnesses provided to the aggregation leaf are independent of those verified in message digit leaves — a prover could provide correct chain values in message leaves but incorrect digit values to the aggregation leaf. **This is a fundamental soundness flaw** unless a cross-leaf binding mechanism is introduced (e.g., all digit values are hash-committed in the setup transaction). |
| **Off-chain computation** | Identical to Direction A. |
| **Bitcoin script expressibility** | Good for message digit leaves. The aggregation leaf's `OP_ADD` chain for 128 values is scriptable: push 128 witness integers, apply 127 `OP_ADD` operations, compare to expected checksum value (encoded as script constant), then verify 5 checksum chain values. Total opcodes ≈ 127 + 5×5 + overhead ≈ 175 opcodes, within the 201 limit. However, the cross-leaf binding problem noted above undermines this approach in its naive form. |
| **Soundness under protocol composition** | **Weak** due to the cross-leaf binding gap. Without a mechanism binding the digit-value witnesses in the aggregation leaf to the chain values verified in the message digit leaves, this direction has a soundness flaw. Patching this requires either (a) OP_CTV/covenant-based cross-leaf commitments (soft fork dependent), or (b) moving checksum verification back into each message digit leaf (which bloats individual leaves), or (c) moving to GC-side verification as in Direction A. |
| **Parameter flexibility** | Limited at w=4. The aggregation leaf design is sensitive to L₁ (the `OP_ADD` chain must be exactly right). |
| **Novelty** | Moderate. The aggregation leaf concept is novel in the BitVM context but has the identified soundness gap that must be resolved before it becomes a genuine contribution. |

**Risks:** The cross-leaf state-passing problem is potentially fatal under current Bitcoin Script constraints. The soundness flaw — a prover can provide consistent message digit chain values but inconsistent digit-value witnesses to the aggregation leaf — means this direction requires either a soft fork or a redesign that collapses into Direction A. This is the key result that Direction C concretely answers: **GC-side checksum verification is necessary under current Bitcoin consensus rules**, which is itself a valuable finding.

---

#### Direction D: WOTS+ w=16, Constrained-Digit Chain Suffix Witness

| Metric | Assessment |
|---|---|
| **On-chain script size** | Smallest of all directions. Each of 67 digit leaves requires only: `OP_SHA256 OP_EQUALVERIFY` (applied once to the top of the witness-provided suffix). Per-leaf script ≈ 35–45 bytes including pubkey push. Total: 67 × 40 = ~2,680 bytes committed script. Merkle proof: ⌈log₂(67)⌉ = 7 levels × 32 = 224 bytes. Dramatically within all Bitcoin Script limits. |
| **On-chain transaction cost** | Witness per digit: 32 (primary chain value) + up to 7 × 32 (suffix, if `d_i = w/2`) + 224 (Merkle proof) + metadata ≈ 32 + 224 + 224 + 50 = 530 bytes per digit (worst case). For 67 positions: ~35,510 bytes → ~8,878 vBytes after witness discount. Average case (uniform `d_i ∈ [8,15]`): ~3.5 suffix values → 67 × (32 + 112 + 224 + 50) = ~28,406 bytes → ~7,102 vBytes. Competitive with Direction B. |
| **Signature size** | Primary reveal: 67 × 32 = 2,144 bytes. Plus suffix: worst case 67 × 7 × 32 = 14,976 bytes (unacceptable without digit constraint). **With the `d_i ≥ 8` encoding constraint**: average suffix = 67 × 3.5 × 32 ≈ 7,504 bytes additional. Total average: ~9,648 bytes — worse than Lamport in raw bytes, though the re-encoding required to enforce `d_i ≥ 8` is not costless and introduces message-dependent variability. **This is the critical weakness**: the average-case improvement is marginal and the maximum-case is worse than Lamport. |
| **GC input label compatibility** | Good. The pre-committed input table contains all 16 wire labels per position; the revealed `C_{i,d_i}` (verified by the chain suffix) indexes the correct label directly. No adapter required. However, the digit-constraint re-encoding (`d_i ≥ 8`) means the effective message space is halved, requiring a longer base-16 encoding — increasing L₁ from 64 to ~68 digits. |
| **Cryptographic security** | The digit constraint `d_i ≥ 8` introduces a subtle security consideration: the constrained message encoding may have non-uniform digit distribution, potentially weakening the WOTS checksum's forgery resistance. Requires formal analysis of WOTS+ security under constrained digit alphabets. At w=16 with the upper-half constraint, the effective checksum range is smaller, reducing the checksum's protective margin. |
| **Off-chain computation** | Lowest off-chain overhead. Pre-computing the full chain for 67 positions: 67 × 15 = 1,005 SHA-256 calls. Signing requires at most 67 hash calls. No adapter. |
| **Bitcoin script expressibility** | Excellent — the best of all directions for script simplicity. No branching required. Each leaf is a single-path script executable by any Bitcoin script interpreter without `OP_IF`. This is the unique advantage of Direction D. |
| **Soundness under protocol composition** | The chain suffix in the witness is publicly visible, revealing `C_{i,d_i+1}, ..., C_{i,w-1}`. This reveals which hash chain intermediates were *not* used for signing, which is public information in WOTS. One-time use enforced by connector outputs. The digit constraint does not weaken one-time soundness provided the protocol ensures `d_i ≥ 8` for all digits in the signed message. |
| **Parameter flexibility** | The digit constraint is tightly coupled to w=16 (splitting at w/2=8). Changing w requires redesigning the constraint and the re-encoding scheme. Inflexible. |
| **Novelty** | Moderate. The constrained-digit encoding trick is a novel workaround for the variable-witness-bloat problem. The key insight — that you can trade message-space efficiency for bounded witness size by restricting the digit alphabet — is useful but limits generality. |

**Risks:** The average-case witness size remains ~9.6 KB total (primary + suffix), worse than Lamport's ~8.2 KB in raw bytes. The compression benefit materialises only in the primary `C_{i,d_i}` values (2,144 bytes vs. 8,192 bytes for Lamport) but is erased by the suffix overhead. The digit constraint complicates the security proof and halves the effective encoding alphabet. This direction optimises script simplicity at the cost of defeating the primary goal: reducing on-chain data.

---

#### Direction E: Hybrid Lamport-WOTS with Selective Compression

| Metric | Assessment |
|---|---|
| **On-chain script size** | WOTS+ portion (w=8, 67+4=71 positions): ~71 × 240 bytes = ~17 KB. Lamport portion (64 positions): ~64 × 60 bytes = ~3.8 KB. Total: ~20.8 KB committed script. Merkle tree for 135 leaves, depth 8, proof = 256 bytes. Larger aggregate script than either pure design. |
| **On-chain transaction cost** | WOTS+ witness: 71 × 32 = 2,272 bytes. Lamport witness: 64 × 32 = 2,048 bytes. Combined primary reveal: 4,320 bytes + Merkle proofs for each leaf (256 bytes × 135 leaves amortised = ~34,560 bytes total Merkle overhead for full reveal). Approximately 60% of Lamport total cost — improvement, but the hybrid's two-component architecture increases engineering complexity without proportional benefit over a pure w=8 design. |
| **Signature size** | ~4,320 bytes combined, ~1.9× reduction over Lamport. No better than Direction A at w=4, while carrying w=8 complexity for the WOTS portion. The hybrid does not offer a compression advantage over a clean single-scheme design; the Lamport tail wastes the benefit of WOTS compression on 25% of the message bits. |
| **GC input label compatibility** | Complex. Two different label derivation schemes must coexist: WOTS-derived labels for the first 192 bits and Lamport-derived labels for the final 64 bits. The GC must handle two input encoding formats, increasing design complexity and the risk of encoding mismatches at the 192-bit boundary. |
| **Cryptographic security** | 128-bit security in both components. No weakening from the hybrid structure, but the security proof must address both components and their interaction at the partition boundary. More proof surface area than a single scheme. |
| **Off-chain computation** | Sum of individual components. No savings vs. a pure WOTS+ design; in fact marginally higher due to maintaining two key structures. |
| **Bitcoin script expressibility** | Manageable: the WOTS+ portion at w=8 is feasible (as per Direction B analysis), and the Lamport portion is already proven. However, the hybrid script generator must handle two code paths, doubling implementation complexity and audit surface. |
| **Soundness under protocol composition** | Sound, with the caveat that the partition boundary must be consistently defined in the setup commitment. A prover who can influence where the partition falls could potentially manipulate which bits are covered by the stronger Lamport vs. the weaker (in terms of forgery surface) WOTS scheme — mitigated by fixing the partition at protocol design time. |
| **Parameter flexibility** | Low. The partition point (192/64 split) is hardcoded. Any change to proof size or security requirements requires redesigning both components. |
| **Novelty** | Low. This direction is a superposition of existing techniques with no new cryptographic or architectural insight. The claimed advantage (graceful degradation if WOTS has issues) is not a research contribution; it is an engineering hedge that reduces research focus. |

**Risks:** This direction solves no problem that a pure WOTS+ design does not solve better. The hybrid architecture adds complexity, reduces compression efficiency, complicates the GC interface, and produces no novel insight. It exists primarily as a risk-hedging mechanism, which is appropriate for a production deployment but not for a research contribution. It should not be the primary direction.

---

### 3. Chosen Direction

**Selected Direction: B — WOTS+ at w=8 with Unrolled Tapscript Verification and Bit-Decomposition Adapter Layer**

Direction B is the uniquely correct choice because it is the only direction that simultaneously achieves all three hard constraints with genuine compression: a ~63% reduction in on-chain transaction cost over Lamport, full compatibility with current Bitcoin consensus (no soft fork), and a formally analysable interface between the on-chain signature and the off-chain garbled circuit. The bit-decomposition adapter layer is the core architectural innovation — it resolves the digit/bit granularity mismatch identified in the problem statement as a key research challenge, and does so through a provably secure HMAC-PRF construction whose simulation-security preservation is a concrete, publishable cryptographic result. Direction A's 1.9× compression at w=4 is too modest to justify WOTS+'s added complexity; Direction C has a fatal soundness flaw in checksum cross-leaf binding; Direction D defeats its own compression goal through suffix bloat; and Direction E offers no novel contribution. Direction B's w=8 achieves the practical sweet spot — 8-branch Tapscript trees remain within the 201-opcode limit, the ~2.8× signature compression is a substantial and measurable improvement, and the clean separation of concerns (Bitcoin enforces chain validity, the adapter enforces bit-label uniqueness, the GC enforces computation correctness) provides a modular architecture that is both formally analysable and extensible. Checksum verification is delegated to the GC sub-circuit (the key insight from the Direction A/C comparison), eliminating the inter-leaf state-passing problem entirely.

**Concrete parameters:** WOTS+ with w=8, SHA-256 as the hash function, HMAC-SHA256 for label derivation, L₁=86 message digit positions + L₂=4 checksum positions = **90 total chain positions**, 90 Tapscript leaves in a Huffman-weighted Merkle tree, bit-decomposition adapter producing 3 bit-level label pairs per digit, GC sub-circuit for checksum verification of ≈40 gates, one-time use enforced via connector outputs with pubkey commitment in the setup transaction.

---

### 4. Key Questions

1. **What is the exact opcode count and byte size of a single WOTS+ digit verification Tapscript leaf at w=8, using a balanced binary `OP_IF` tree structure (depth 3), including the SHA-256 chain completion operations for each of the 8 branches, the public key push, and the digit-value constant push — and does this fit within Bitcoin's 201-opcode and ~10 KB per-script limits for all 8 digit values `d_i ∈ {0,...,7}`?**

   *This is experimentally answerable in 1–2 days by implementing a Tapscript leaf generator and measuring exact byte/opcode counts across all branches.*

2. **Does the bit-decomposition adapter preserve the simulation-based security of the garbled circuit? Specifically: given that an adversary knows all WOTS+ public keys `{H^7(sᵢ)}` and observes the on-chain `C_{i,d_i}` values, can they compute any wrong-bit label `BitLabel(i, j, b)` for `b ≠ bit_j(d_i)` with non-negligible probability — and does the formal proof hold under the standard PRF security of HMAC-SHA256 without requiring the random oracle model?**

   *Answerable by a formal reduction proof: PRF security of HMAC-SHA256 directly implies wrong-label indistinguishability; the proof sketch is constructible in ~1 week of formal analysis.*

3. **What is the minimum GC sub-circuit size (in gates) required to verify the WOTS+ checksum for w=8 and L₁=86 message digits, where the sub-circuit receives the 86 digit values as 3-bit wire groups and must compute their sum, compare against the 4 checksum digit values (also provided as GC inputs from the on-chain signature), and output accept/reject — and what is the resulting increase in garbled circuit size and evaluation time relative to the Lamport baseline?**

   *Answerable by implementing the checksum circuit in a standard GC library (e.g., JustGarble or EMP-toolkit) and profiling gate count and garbling time.*

4. **What is the concrete total on-chain vByte cost of one complete BitVM3 dispute-resolution round using WOTS+ at w=8, measured across all transactions in the challenge-response protocol, including setup transaction (pubkey commitment), assertion transaction (WOTS signature reveal across 90 leaves), and any challenge transactions — compared against the Lamport baseline under the same protocol, at current (2024) median Bitcoin fee rates?**

   *Answerable by implementing a transaction size simulator using rust-bitcoin or python-bitcoinlib that constructs the full transaction graph with correct witness data and measures vByte costs.*

5. **How should the 90 Tapscript leaves be arranged in the Taproot Merkle tree to minimise the expected Merkle proof overhead, given that different digit positions are revealed in different protocol phases (some in the assertion transaction, others in challenge transactions) — and what is the vByte savings of a Huffman-optimal tree arrangement versus a balanced tree for a typical BitVM3 dispute scenario?**

   *Answerable by modelling the probability distribution of leaf spends across protocol phases and computing optimal Huffman tree depth assignments; implementable as a ~1 day optimisation exercise.*

6. **Can the one-time use of the WOTS+ key pair be cryptographically enforced by the BitVM3 connector output structure under current Bitcoin consensus — specifically, is there a transaction graph design where the WOTS public key commitment is embedded in the setup transaction's `P2TR` output such that any attempt to reuse the same key pair for a second assertion transaction is detectable and rejectable by any Bitcoin full node, without relying on observer vigilance?**

   *Answerable by designing the specific transaction graph (setup → assert → challenge) with explicit UTXO lineage and verifying that key-reuse would require double-spending a destroyed UTXO, which Bitcoin consensus already prevents.*

7. **For the WOTS+ checksum at w=8 with L₁=86 message digits and maximum checksum value C_max = 7 × 86 = 602, requiring L₂=4 checksum digits at w=8 (since 8³ = 512 < 602 ≤ 8⁴ = 4096), does the four-digit checksum provide sufficient forgery resistance — i.e., what is the probability that an adversary can forge a valid WOTS+ signature by finding message digits `{d_i'}` with the same checksum as the original `{d_i}` but different values, and does this probability remain negligible at 128-bit security?**

   *Answerable by formal analysis: the forgery probability under WOTS+ is bounded by the probability of finding a preimage in the hash chain, which is `L × w × 2^{-λ}` = `90 × 8 × 2^{-256}` — negligibly small; the exact bound is a straightforward calculation.*
