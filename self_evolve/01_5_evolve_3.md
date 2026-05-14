# 01 — Scope & Plan

**Topic:** In BitVM3, garbled circuits are used to do off-chain proof verification based on a signed proof put on the Bitcoin chain. The signed proof is input into the garbled circuit as input labels. In most existing designs, the signature scheme is a Lamport signature, which is verifiable by Bitcoin. Can you provide a re-design using Winternitz signatures instead of Lamport signatures?

**Note:** 

**Model:** `claude-sonnet-4-6`  
**Tokens:** in=3,302 out=5,774  
**Cost:** $0.0965

---

# Winternitz Signatures in BitVM3: Revised Candidate Solutions

---

### 1. Candidate Solutions

---

**Direction A: WOTS+ at w=8 with Balanced Tapscript Leaf Trees, HMAC-PRF Bit-Decomposition Adapter, and GC-Side Checksum Verification**

Deploy WOTS+ (with bitmask XORs) at w=8, producing L₁=86 message digit positions plus L₂=4 checksum digit positions = 90 total chain positions for a 256-bit proof hash. Each of the 90 Tapscript leaves encodes a **depth-3 balanced binary OP_IF tree** that verifies the hash chain for one digit position: the witness provides the chain value `C_{i,d_i} = F_{k_i}^{d_i}(sᵢ)` (using WOTS+ notation where each step XORs a public bitmask before hashing), and the leaf script applies the appropriate number of masked SHA-256 steps to reach the committed public key `pk_i = F_{k_i}^7(sᵢ)`. Crucially, because WOTS+ bitmask XORs are applied at each step using **publicly known bitmasks** committed in the setup transaction, the forward-chain computation problem — where an observer who sees `C_{i,d_i}` can trivially compute `H^{d_i+1}(sᵢ)` in plain WOTS — is closed: without the bitmasks, computing forward chain values produces different outputs than the masked chain, so the adversary cannot derive wrong-digit chain values from the revealed one. A **bit-decomposition adapter layer** operates entirely off-chain: each revealed chain value `C_{i,d_i}` is used as a PRF key to derive 3 bit-level wire label pairs via `BitLabel(i, j, b) = HMAC-SHA256(C_{i,d_i} || bitmask_prefix_i, i || j || b)` for `j ∈ {0,1,2}` and `b ∈ {0,1}`. The evaluator can derive only the labels for `b = bit_j(d_i)` because the adapter's HMAC call uses `C_{i,d_i}` as key material; the wrong-digit labels require computing `C_{i,d_i'}` for `d_i' ≠ d_i`, which is hard by hash chain one-wayness (backward) and WOTS+ bitmask blinding (forward). Checksum verification is delegated entirely to a small GC sub-circuit (~150 gates for a sum-and-compare circuit over 86 three-bit inputs), keeping Bitcoin Script's role strictly limited to chain-depth enforcement. The 90 Tapscript leaves are arranged in a **Huffman-weighted Merkle tree** with leaves ordered by spending frequency across protocol phases. All bitmasks and public keys are committed in the setup transaction's P2TR output.

---

**Direction B: WOTS+ at w=4 with Fully Unrolled Tapscript Leaves and Protocol-Level Checksum Commitment**

Deploy WOTS+ at w=4 (2 bits per digit) producing L₁=128 message digit positions plus L₂=5 checksum positions = 133 total chain positions. Each Tapscript leaf uses a **depth-2 balanced OP_IF tree** (4 branches) that is simple, auditable, and conservatively within all Tapscript byte limits. The key architectural innovation over prior w=4 designs is the **protocol-level checksum commitment**: rather than verifying the checksum in Bitcoin Script (which requires cross-leaf state, impossible under current consensus as shown in the Direction C soundness analysis) or in the GC sub-circuit, the prover commits to all checksum digit chain values `{C_{L₁+j, d_{L₁+j}}}` for `j=1..L₂` as a **hash commitment** in the setup transaction's OP_RETURN output. During the assertion transaction, the unlocking witness for each checksum leaf provides the preimage opening this commitment, allowing a single dedicated **checksum verification leaf** to check both (a) the Merkle opening of the preimage commitment from setup and (b) the sum consistency via a chain of `OP_ADD` operations within a single leaf — avoiding the inter-leaf state-passing problem because the sum is verified against a value committed at setup time, not assembled across leaves. The WOTS+ bitmasks close the forward-chain security gap identically to Direction A. A digit-to-bit adapter identical to Direction A's produces 2 bit-level label pairs per digit. The ~1.9× compression over Lamport is modest but the architecture is maximally conservative and requires no opcode counting uncertainty: w=4 leaves are demonstrably small.

---

**Direction C: WOTS+ at w=16 with Verifier-Controlled Challenge Digits and Suffix-Free Script**

Redesign the **protocol-level interaction** so that in the challenge-response bisection, it is the **verifier** (not the prover) who selects the challenged proof hash, using a commit-reveal protocol that produces challenge values with all base-16 digit values constrained to `d_i ∈ {8, ..., 15}` (the upper half of the digit range). This eliminates the suffix witness bloat problem that made naive w=16 unattractive in Direction D: because `d_i ≥ w/2 = 8`, each chain verification in Bitcoin Script requires applying at most `w-1-d_i ≤ 7` SHA-256 steps from the revealed `C_{i,d_i}` to the public key `pk_i = H^{15}(sᵢ)`. Critically, the locking script for each digit position is **branch-free**: it applies a **fixed** number of SHA-256 steps (not data-dependent), because `w-1-d_i` is known at the time the challenge is formed and is embedded directly in the leaf script generated for that specific challenge instance. The verifier publishes the challenge as a taproot tree where each of the 67 leaf scripts has the exact number of SHA-256 applications hardcoded for that digit's constrained value. This eliminates the need for OP_IF branching entirely, producing the smallest possible per-leaf scripts (~40–60 bytes each). The constrained digit encoding: re-encode the proof hash in base-16 and XOR with a verifier-provided mask to shift all digits into `[8,15]`; the verifier commits to the mask in the challenge transaction and reveals it for verification. The WOTS+ bitmasks handle security. Wire labels are bound as `WireLabel(i, d) = HMAC-SHA256(C_{i,d}, context_i)` using the pre-committed input table with all 16 labels per position. Checksum verification is handled in the GC sub-circuit. This direction achieves the lowest per-leaf script size and eliminates OP_IF complexity entirely.

---

**Direction D: WOTS+ at w=8 with OP_CAT-Enabled Iterative Chain Verification (BIP-347 Variant)**

Assuming BIP-347 (OP_CAT re-enablement, currently proposed and under active review), design WOTS+ verification that uses **OP_CAT** to iteratively apply SHA-256 chain steps without unrolling all branches explicitly. The leaf script for each digit position uses OP_CAT to concatenate the running chain value with the bitmask for the current step, applies OP_SHA256, and uses OP_SWAP + OP_CAT to assemble a hash chain of variable depth determined by a witness-provided **depth counter**. The locking script verifies the depth counter is consistent with the digit value by checking that the final value equals `pk_i` after exactly `w-1-d_i` steps. This enables compact scripts of ~80–100 bytes per leaf regardless of w, compared to the branching overhead in non-OP_CAT designs. The digit-to-bit adapter and GC-side checksum verification are identical to Direction A. The additional power of OP_CAT enables more efficient encoding of the WOTS+ bitmask XOR steps, since `XOR(value, mask) || context` can be assembled on-stack before hashing. For w=8 and 90 total chain positions, the committed Tapscript tree is ~7.2–9 KB total, and per-transaction witness costs drop by ~15% versus the non-OP_CAT Direction A due to eliminated branching overhead. This direction serves the important purpose of characterising the benefit of BIP-347 in this context and providing a forward-compatible design.

---

### 2. Evaluate Directions

---

#### Direction A: WOTS+ w=8, Bit-Decomposition Adapter, GC-Side Checksum

**On-chain script size (bytes):**
Each of the 90 Tapscript leaves encodes a depth-3 balanced binary OP_IF tree. Under BIP 342 (Tapscript), the 201-opcode limit is removed; the binding constraint is the 10,000-byte per-script limit and the 1,000-element stack limit. For digit value `d_i` in a depth-3 tree: the tree has 3 levels of OP_IF/OP_ELSE/OP_ENDIF (= 9 opcodes for the structure), plus in the taken branch, `w-1-d_i ∈ {0,...,7}` applications of `OP_CAT`-with-bitmask (without OP_CAT, each WOTS+ step is: `<bitmask_j> OP_SWAP OP_XOR OP_SHA256`, requiring OP_XOR which is unavailable — the correct encoding uses the bitmask via a different construction, see below) or equivalently, since OP_XOR is not available in Bitcoin Script, the bitmask can be pre-applied off-chain and the leaf script degenerates to plain SHA-256 chain verification with the WOTS+ property enforced by committing to the correct public key derived from the masked chain. Using this simplification (bitmasks committed in setup, verification is still just SHA-256 chain depth), each taken branch requires at most 7 OP_SHA256 + 1 OP_EQUALVERIFY + 1 pubkey push + 1 digit-value constant push ≈ ~40–50 bytes in the taken branch. Full leaf size including the binary tree structure: approximately **200–280 bytes per leaf**. Total committed script across 90 leaves: **~18–25 KB** in the Merkle tree (not in any single transaction — each spend reveals only one leaf). All leaves are well within the 10,000-byte per-script limit.

**On-chain transaction cost (vBytes / fees):**
The BitVM3 protocol spans multiple transaction phases. Per-phase cost breakdown:

| Phase | Transactions | WOTS+ w=8 witness (bytes) | Lamport witness (bytes) |
|---|---|---|---|
| Setup | 1 | ~300 (pubkey commitment) | ~16,400 (pubkey list) |
| Assertion | 1 | 90 × 32 = 2,880 (chain values) + 90 × 224 (Merkle proofs) = ~22,980 | 256 × 32 = 8,192 + 256 × 256 = ~73,728 |
| Per-challenge digit reveal | 1 per digit | 1 × 32 + 224 + ~50 = ~306 | 1 × 32 + 256 + ~50 = ~338 |
| Full dispute resolution | ~90–256 txns | ~27,540 total chain + proofs = ~6,885 vBytes | ~81,920 total = ~20,480 vBytes |

The ~66% reduction in assertion transaction witness size is the primary on-chain benefit. At current median fee rates (~50 sat/vByte), the assertion transaction alone saves approximately 13,595 vBytes × 50 sat = ~680,000 satoshis (~$400 at $60k BTC) per dispute round.

**Signature size (on-chain witness data):**
Primary chain value reveal: 90 × 32 = **2,880 bytes** versus Lamport's 256 × 32 = 8,192 bytes. This is a **2.84× reduction** in signature data. Including Merkle proof overhead (224 bytes per digit vs. 256 bytes for Lamport's slightly larger tree), the total witness per full assertion is ~25,860 bytes vs. ~81,920 bytes — a **3.17× total witness reduction**. The setup transaction pubkey storage is 90 × 32 = 2,880 bytes vs. 256 × 32 = 8,192 bytes for Lamport public keys, an additional ~5.3 KB saving in the setup transaction.

**Garbled circuit input label compatibility:**
The bit-decomposition adapter produces a clean bit-level interface: each of the 90 chain reveals yields 3 wire label pairs, for 270 total bit-level wire inputs — comparable to Lamport's 256 bit inputs (14 additional bits are checksum-related, handled by the GC sub-circuit). The adapter's security rests on two properties: (1) **backward one-wayness** — computing `C_{i,d_i'}` for `d_i' < d_i` requires inverting SHA-256; (2) **forward bitmask blinding** — computing `C_{i,d_i'}^{WOTS+}` for `d_i' > d_i` requires knowing the intermediate bitmask-XOR values, which are committed in setup but whose interaction with the chain prevents naive forward computation without the masked values. The HMAC-SHA256 label derivation uses `C_{i,d_i}` as the key, so the wrong-bit labels are computationally hidden under PRF security given hash-chain one-wayness. Formal security reduction: a distinguisher on wrong-bit labels implies either a PRF distinguisher for HMAC-SHA256 or a preimage finder for SHA-256 — both assumed hard at 128-bit security.

**Cryptographic security level:**
128-bit security under SHA-256 collision resistance and one-wayness. WOTS+ provides tight security reduction under the multi-function hash family (MF-OW) assumption. The checksum prevents forgery-by-upward-shift (an adversary who lowers some `d_i` values to forge a new valid signature must raise the checksum digits, but increasing checksum digit values requires finding preimages). One-time property enforced by connector outputs destroying the signing UTXO after first use; key reuse requires double-spending a Bitcoin UTXO, which is consensus-rejected.

**Off-chain computation overhead:**
Key generation: 90 × 7 = 630 SHA-256 calls plus HMAC label derivations (90 × 3 × 2 = 540 calls). Garbling: 270-wire GC input encoding (comparable to Lamport's 256-wire), plus ~150-gate checksum sub-circuit overhead (negligible: 150 gates ≈ <0.1% of a 1M-gate circuit). Signing: at most 90 SHA-256 calls. Compared to Lamport: key generation 256 × 2 = 512 hashes, signing 256 hashes. WOTS+ overhead is modest; the reduction in *number of wire labels* (270 vs. 512 label pairs) actually *reduces* garbled circuit input encoding size by ~47%.

**Bitcoin script expressibility / opcode compatibility:**
Under BIP 342 Tapscript (no 201-opcode limit), the depth-3 OP_IF tree is fully expressible. Each leaf uses standard opcodes: OP_IF, OP_ELSE, OP_ENDIF, OP_SHA256, OP_EQUALVERIFY, OP_DROP — all available in Tapscript. The bitmask XOR step is handled by pre-computing the masked values off-chain (since OP_XOR is unavailable), with the locking script performing plain SHA-256 chain completion against the WOTS+-derived public key. A script template engine generates all 90 leaves deterministically from the WOTS+ parameters. No soft fork required.

**Soundness / unforgeability under protocol composition:**
The one-time property composes correctly with BitVM3's challenge-response protocol because: (a) the setup transaction's P2TR output commits to `Hash(all_90_pubkeys || all_bitmasks)`, binding the WOTS+ key set to a specific dispute instance; (b) the assertion transaction spends this UTXO (destroying it), so any attempt to re-sign under the same keys requires double-spending — rejected by consensus; (c) the GC checksum sub-circuit ensures a manipulated checksum (forged chain values for checksum digits) produces incorrect GC output, caught by the verifier's evaluation; (d) the bit-decomposition adapter's wrong-label hiding ensures the evaluator cannot complete any gate other than the one indexed by the true signed digit.

**Parameter flexibility:**
The w=8 choice is fixed for this direction but the architecture is fully parameterisable. The Tapscript template engine, bit-decomposition adapter, and GC checksum sub-circuit all generalise to arbitrary w by changing the tree depth (⌈log₂(w)⌉), the adapter's bit-width (⌊log₂(w)⌋), and the checksum circuit's input width. A production system can select w based on Bitcoin fee conditions: at high fees, increase w to reduce on-chain data; at low fees, decrease w to simplify scripts.

**Novelty and conceptual contribution:**
High. Three novel contributions: (1) the formally-grounded bit-decomposition adapter with an explicit two-step security reduction (hash chain one-wayness + PRF security) closing the forward-chain vulnerability via WOTS+ bitmasks; (2) the separation of concerns principle (Bitcoin enforces chain depth, adapter enforces label uniqueness, GC enforces computation correctness) as an architectural pattern generalisable to other commitment-based protocols; (3) the concrete quantification of the compression benefit across the full BitVM3 transaction graph — the first precise comparison across all protocol phases.

**Risks:**
- The WOTS+ bitmask XOR cannot be directly computed in Bitcoin Script (OP_XOR unavailable), so the bitmask integration degrades to a pre-commitment approach where the masked public keys are committed at setup. A subtle attack: if the prover can manipulate the bitmask commitment in setup, they can influence which labels are revealed. Mitigation: the bitmask is derived deterministically from the prover–verifier joint randomness (e.g., hash of both parties' setup contributions), bound to the P2TR commitment.
- The ~150-gate checksum sub-circuit adds verifiable correctness requirements on the garbled circuit; a bug in the sub-circuit could allow checksum bypass. Requires mechanised circuit verification.
- If BIP-347 is activated before deployment, Direction D supersedes this direction with smaller scripts; the architecture should be designed to be OP_CAT-upgradeable.

---

#### Direction B: WOTS+ w=4, Protocol-Level Checksum Commitment

**On-chain script size (bytes):**
Each of the 133 Tapscript leaves uses a depth-2 OP_IF tree (4 branches, 2 levels). Per-leaf structure: 2 levels × 3 opcodes (OP_IF/OP_ELSE/OP_ENDIF) = 6 structural opcodes; taken branch: at most 3 OP_SHA256 + 1 OP_EQUALVERIFY + pubkey push + digit constant push ≈ ~70–100 bytes per leaf. Total committed script: **~9.3–13.3 KB** across 133 leaves — smaller aggregate than Direction A. Merkle tree depth: ⌈log₂(133)⌉ = 8 levels, proof = 256 bytes per digit reveal. The dedicated checksum verification leaf adds ~400 bytes (5 chain verifications + sum check against the setup commitment). All leaves comfortably within Tapscript limits.

**On-chain transaction cost (vBytes / fees):**

| Phase | WOTS+ w=4 witness | Lamport witness |
|---|---|---|
| Setup | ~300 + 32 (checksum hash commitment) | ~16,400 |
| Assertion | 133 × 32 + 133 × 256 = ~37,924 bytes → ~9,481 vBytes | 256 × 32 + 256 × 256 = ~73,728 → ~18,432 vBytes |
| Checksum leaf spend | ~680 bytes | N/A |
| Full dispute | ~45,000 bytes total → ~11,250 vBytes | ~81,920 → ~20,480 vBytes |

Approximately **45% reduction** over Lamport. Less impressive than Direction A's 66% but architecturally simpler.

**Signature size (on-chain witness data):**
133 × 32 = **4,256 bytes**, a **1.93× reduction** over Lamport's 8,192 bytes. The protocol-level checksum commitment adds 32 bytes at setup (the commitment hash) and ~160 bytes (5 preimages) at the checksum leaf spend. Net compression is modest but genuine.

**Garbled circuit input label compatibility:**
Clean 2-bit-per-digit adapter (depth-2 bit decomposition). Each of 128 message chain reveals yields 2 bit-level wire label pairs for 256 total bit inputs — identical count to Lamport, making this a drop-in replacement for the GC input encoding with no sub-circuit overhead (checksum is enforced by Bitcoin Script, not the GC). This is the strongest GC compatibility among all directions.

**Cryptographic security level:**
128-bit security under SHA-256 one-wayness. WOTS+ at w=4 has a smaller per-chain hash depth (3 steps vs. 7 for w=8), reducing the multi-chain forgery probability by a factor proportional to chain length — still negligible at 2^{-256} per chain. The protocol-level checksum commitment binds the checksum values to the setup transaction via SHA-256, making checksum manipulation require preimage inversion.

**Off-chain computation overhead:**
Key generation: 133 × 3 = 399 SHA-256 calls. Garbling: 256 bit-level wire pairs — identical to Lamport. No GC sub-circuit overhead for checksum. Lowest off-chain overhead of any WOTS+ direction. This is architecturally the least disruptive change from Lamport.

**Bitcoin script expressibility / opcode compatibility:**
Excellent and auditable. The depth-2 tree is the simplest possible multi-branch structure in Bitcoin Script. Each leaf is directly hand-verifiable. The checksum leaf's `OP_ADD` chain for 5 values against a committed sum is straightforward: `<commitment> OP_EQUALVERIFY` after computing the chain sum, all within ~30 opcodes. No soft fork required.

**Soundness / unforgeability under protocol composition:**
Strong, with one important clarification: the protocol-level checksum commitment solves the inter-leaf state-passing problem by binding the checksum digit values to the setup transaction at signing time rather than assembly time. An adversary cannot provide inconsistent digit-value witnesses to the checksum leaf because the leaf verifies the chain values against the setup commitment hash, not against independently provided witnesses. One-time use enforced identically to Direction A.

**Parameter flexibility:**
Limited to w=4. Upgrading to w=8 requires redesigning all 133 leaf scripts and the checksum commitment scheme. The architecture does not naturally extend to higher w, making it a conservative but inflexible choice.

**Novelty and conceptual contribution:**
Moderate. The protocol-level checksum commitment as a solution to the inter-leaf state-passing problem is a clean and novel architectural insight — it proves that Bitcoin-Script-side checksum verification is achievable without soft forks by moving the binding to the setup transaction. This is a publishable finding that cleanly resolves the soundness flaw identified in the prior Direction C analysis.

**Risks:**
- The ~1.93× compression over Lamport may not justify the added complexity compared to simply using Lamport. The main value proposition is in the architectural clarity of the checksum commitment solution, not the compression.
- The checksum leaf's sum computation assumes the 5 checksum digit values were committed correctly at setup. If the prover incorrectly constructs the commitment (e.g., using wrong digit sum), the protocol stalls. Requires rigorous commitment construction verification at the prover side.

---

#### Direction C: WOTS+ w=16, Verifier-Controlled Challenge Digits, Branch-Free Tapscript

**On-chain script size (bytes):**
Because the verifier constructs challenge values with `d_i ∈ {8,...,15}` and embeds the exact number of SHA-256 steps as a constant in each leaf, **each leaf is branch-free**: it applies a fixed `w-1-d_i ∈ {0,...,7}` SHA-256 operations and checks the result against `pk_i`. Per-leaf structure: at most 7 OP_SHA256 + 1 OP_EQUALVERIFY + 1 pubkey push ≈ **35–75 bytes per leaf** (varying by digit value; averaged ~55 bytes). For 67 total positions: total committed script ≈ **~3.7 KB** — the smallest of all directions by a factor of 5–7×. Merkle tree depth: ⌈log₂(67)⌉ = 7 levels, proof = 224 bytes per digit reveal.

**On-chain transaction cost (vBytes / fees):**

| Phase | WOTS+ w=16 (verifier challenge) witness | Lamport witness |
|---|---|---|
| Setup | ~300 + verifier mask commit (32 bytes) | ~16,400 |
| Challenge issuance | ~67 bytes (verifier mask reveal) | N/A |
| Assertion | 67 × 32 + 67 × 224 = ~17,200 bytes → ~4,300 vBytes | ~73,728 → ~18,432 vBytes |
| Full dispute | ~20,500 bytes → ~5,125 vBytes | ~81,920 → ~20,480 vBytes |

Approximately **75% reduction** over Lamport — the best of all directions.

**Signature size (on-chain witness data):**
67 × 32 = **2,144 bytes** — a **3.82× reduction** over Lamport's 8,192 bytes. No suffix needed (branch-free design eliminates suffix witnesses entirely). This is the best signature compression achievable without a soft fork at 256-bit security.

**Garbled circuit input label compatibility:**
The pre-committed input table contains all 16 wire labels per position (committed at setup). The revealed `C_{i,d_i}` — verified by the branch-free Tapscript leaf as a chain value at depth `d_i` from the public key — directly indexes the correct wire label via `WireLabel(i, d_i) = HMAC-SHA256(C_{i,d_i}, context_i)`. A 4-bit-per-digit adapter layer decomposes each digit into 4 bit-level wire label pairs for compatibility with standard bit-level GC frameworks. The forward-chain security gap is closed by WOTS+ bitmasks (committed in setup and embedded in the challenge-specific leaf scripts). Checksum handled by GC sub-circuit.

**Cryptographic security level:**
128-bit security under SHA-256. The constrained digit range `d_i ∈ {8,...,15}` reduces the checksum range (minimum digit sum = 8 × 67 = 536, maximum = 15 × 67 = 1005; checksum range = 469 vs. full range 1005), but the **relative** checksum protection is unchanged: an adversary who lowers some `d_i'` below 8 (to forge a valid signature) necessarily violates the verifier-enforced digit constraint, which is checked by the verifier's mask commitment before the assertion transaction is accepted. The digit constraint is enforced at the protocol level, not the cryptographic level: the verifier publishes the mask such that `d_i = (proof_digit_i XOR mask_i) + 8`, and any assertion with a different mask is rejected. The WOTS+ forgery bound remains `L × w × 2^{-256}` = negligible.

**Off-chain computation overhead:**
Key generation: 67 × 15 = 1,005 SHA-256 calls. Verifier mask generation: 67 single-byte operations. Garbling: 67 × 4 = 268 bit-level wire pairs (comparable to Lamport's 256). GC checksum sub-circuit: ~200 gates for a sum-and-compare circuit over 67 four-bit inputs (max sum = 1005, requiring 10 bits). Leaf script generation: the verifier generates 67 branch-free leaf scripts at challenge time, each tailored to the specific constrained digit value — this is a verifier-side computation of ~1 second, negligible in practice.

**Bitcoin script expressibility / opcode compatibility:**
The best of all directions. Branch-free scripts using only OP_SHA256 and OP_EQUALVERIFY are the simplest possible Tapscript leaves, fully auditable and mechanically verifiable. No OP_IF required. Every leaf is essentially a simple hash chain suffix check. No soft fork required.

**Soundness / unforgeability under protocol composition:**
The verifier-controlled digit constraint introduces a new composability property: the verifier is the entity who generates the constrained challenge, so the challenge is implicitly bound to the verifier's commitment from the start of the round. In the BitVM3 challenge-response bisection protocol, the verifier issues challenges at each round; requiring the verifier to provide a mask that constrains digits to `[8,15]` is a natural extension of the verifier's existing role. One-time use enforced by connector outputs. A potential concern: if the verifier can choose the mask adversarially (to force specific digit values that reveal unfavorable wire labels), this is mitigated by deriving the mask from the hash of both parties' pre-committed randomness (a standard coin-toss protocol), preventing either party from biasing the digit distribution.

**Parameter flexibility:**
Fixed at w=16 by design. The constrained-digit approach is specifically optimised for w=16 (splitting at w/2=8). Other values of w would require redesigning the constraint scheme. However, within w=16, the design is highly optimised.

**Novelty and conceptual contribution:**
High. The key novel contribution is the **protocol-level digit constraint** that converts a data-dependent branching problem (variable hash chain depth) into a branch-free script design by leveraging the verifier's natural role in challenge-response protocols. This insight — that the verifier's challenge-selection power can be used to eliminate script complexity — is a genuine contribution to the BitVM/Bitcoin Script literature, applicable beyond WOTS+ to any signature scheme with variable-depth verification.

**Risks:**
- The verifier-controlled digit constraint requires the verifier to participate actively in leaf script generation per challenge round. If the verifier is unavailable or produces an incorrect mask, the protocol stalls. This adds a liveness dependency on the verifier for leaf generation.
- The digit-constraint mask derivation protocol (joint randomness) must be formally specified and analysed for bias resistance. A verifier who can bias even 1 bit of the mask could potentially influence which specific wire labels are revealed, potentially weakening GC input confidentiality in a multi-round setting.
- The GC sub-circuit for a 4-bit-per-digit checksum is slightly more complex than the w=8 case (~200 gates vs. ~150 gates) due to the wider digit representation. Requires concrete synthesis to confirm gate count.

---

#### Direction D: WOTS+ w=8 with OP_CAT-Enabled Iterative Chain Verification (BIP-347)

**On-chain script size (bytes):**
With OP_CAT available, each Tapscript leaf replaces the depth-3 OP_IF tree with an **iterative loop-like structure**: push the chain value, push the digit-value witness as a loop counter, and apply OP_SHA256 iteratively using OP_CAT + OP_SHA256 in a partially unrolled loop (OP_CAT itself enables loop simulation via recursive script patterns). However, Bitcoin Script still lacks explicit loop opcodes, so "iterative" here means a fixed-depth unrolled structure that uses OP_CAT to manage the bitmask XOR inline. Concretely: each WOTS+ step without OP_XOR was previously handled by committing masked public keys; with OP_CAT, the bitmask can be cat'd onto the chain value before hashing — `<mask> OP_SWAP OP_CAT OP_SHA256` — which is the correct WOTS+ step without requiring OP_XOR. Per-leaf script with OP_CAT for 8-branch WOTS+: the OP_IF tree is still needed to select the correct number of steps, but each step is simpler (~4 opcodes vs. ~3 without OP_CAT), and the bitmask XOR is exact (not approximated). Per-leaf size: **~150–200 bytes** (vs. 200–280 without OP_CAT), approximately 25% smaller. Total committed script: ~13.5–18 KB across 90 leaves.

**On-chain transaction cost (vBytes / fees):**
Leaf script reduction (~25%) produces modest per-transaction savings. Assertion transaction witness: approximately 90 × 32 + 90 × 224 = 22,980 bytes → ~5,745 vBytes. Compared to Direction A's ~6,885 vBytes: **~17% additional savings** over Direction A. Compared to Lamport: ~72% reduction.

**Signature size (on-chain witness data):**
Identical to Direction A: 90 × 32 = **2,880 bytes**. The OP_CAT optimisation affects script size, not witness size; the revealed chain values are the same.

**Garbled circuit input label compatibility:**
Identical to Direction A. The OP_CAT optimisation is entirely on-chain; the bit-decomposition adapter, label derivation, and GC sub-circuit are unchanged.

**Cryptographic security level:**
Identical to Direction A, but the WOTS+ bitmask XOR is now **exact** (using OP_CAT + OP_SHA256) rather than approximated via pre-committed masked public keys. This provides a cleaner implementation of the WOTS+ security proof, which explicitly requires the bitmask XOR to be performed at each chain step. The OP_CAT variant is therefore **cryptographically preferable** to the non-OP_CAT variant: it directly implements the WOTS+ specification without the intermediate public-key pre-computation approximation.

**Off-chain computation overhead:**
Slightly reduced compared to Direction A: the prover need not pre-compute all 90 × 8 = 720 masked-chain intermediate values for public key commitment; instead, only the final public keys `pk_i = F^7(sᵢ)` are committed (the bitmasks are embedded in the leaf scripts). Key generation: 90 × 7 = 630 SHA-256 calls + bitmask generation (90 × 7 = 630 32-byte random values). Slight increase in setup computation but simplification of the public-key commitment structure.

**Bitcoin script expressibility / opcode compatibility:**
Requires BIP-347 (OP_CAT). Currently proposed and under active review; not yet deployed. The direction is forward-compatible: the same architecture without OP_CAT falls back to Direction A with pre-committed masked public keys. Designing Direction A with OP_CAT compatibility as an upgrade path is straightforward.

**Soundness / unforgeability under protocol composition:**
Identical to Direction A. OP_CAT does not affect the one-time use or chain-binding properties; it only affects script compactness.

**Parameter flexibility:**
High. OP_CAT enables parameter changes without redesigning the script architecture: adjusting w only changes the unrolling depth in the script template, which is trivially regenerated. This is more flexible than Direction A's fixed template structure.

**Novelty and conceptual contribution:**
Moderate. The application of OP_CAT to WOTS+ bitmask handling is novel in the Bitcoin Script context and provides a concrete example of BIP-347's practical utility for one-time signature verification. The result (exact WOTS+ implementation vs. approximation) is a technically meaningful improvement, but the overall architecture follows Direction A's pattern closely.

**Risks:**
- BIP-347 is not yet activated. Any research or implementation depending on OP_CAT is contingent on a soft fork. Designing a production system around this assumption is premature.
- OP_CAT re-enablement is controversial; some developers oppose it on grounds of enabling certain covenant patterns. The risk of the soft fork being rejected or significantly modified is non-trivial.
- The direction adds no new cryptographic insight beyond Direction A — its value is purely in script efficiency improvement, which is contingent on the soft fork.

---

### 3. Chosen Direction

**Selected Direction: Combination of Direction A and Direction C, with Direction D as an explicit upgrade path.**

The combined approach uses **Direction C's protocol-level digit constraint as the primary design** for the common case (where the verifier can enforce constrained challenges), with **Direction A's bit-decomposition adapter and WOTS+ bitmask handling as the general-case fallback** when digit constraints cannot be enforced (e.g., in prover-initiated assertions rather than verifier challenges). The combination achieves Direction C's 75% on-chain cost reduction and branch-free script simplicity for the dominant challenge-response case, while preserving Direction A's correctness and security guarantees for the full protocol. Specifically: verifier-issued challenge transactions use Direction C's branch-free w=16 Tapscript leaves; prover-initiated assertion transactions (where digit values are not verifier-controlled) use Direction A's depth-3 w=8 OP_IF trees. The GC-side checksum sub-circuit, bit-decomposition adapter, and WOTS+ bitmask commitment are shared across both modes, ensuring a uniform garbled circuit interface. Direction D (OP_CAT) is designated as the explicit upgrade path: once BIP-347 activates, the Direction A fallback scripts are replaced by OP_CAT variants with exact bitmask XOR, reducing their size by ~25% and unifying both modes under a single script template.

**Justification:** No single direction achieves optimality across all protocol phases in BitVM3. Direction C's branch-free design is optimal only when the verifier controls digit values, which is precisely the challenge phase — the most frequent and fee-sensitive phase of the dispute protocol. Direction A's depth-3 OP_IF design handles the assertion phase where the prover, not the verifier, commits to proof hash digits. The combination exploits the natural role separation in BitVM3's challenge-response bisection protocol, where verifier and prover play structurally distinct roles in different transactions. The shared GC interface eliminates the complexity of maintaining two separate garbled circuit encodings, and the OP_CAT upgrade path ensures the design remains competitive as Bitcoin's scripting capabilities evolve.

---

### 4. Key Questions

1. **What are the exact byte sizes and opcode counts of (a) a Direction A depth-3 OP_IF leaf at w=8 for each digit value `d_i ∈ {0,...,7}`, and (b) a Direction C branch-free leaf at w=16 for each constrained digit value `d_i ∈ {8,...,15}`, generated by a script template engine and measured against a Bitcoin Script interpreter (e.g., `btcdeb` or `rust-bitcoin`), confirming both fit within Tapscript's 10,000-byte per-script limit?**
   *Experimentally answerable in 1–2 days by implementing a Tapscript leaf generator and testing against a Bitcoin Script interpreter.*

2. **Does the WOTS+ bitmask commitment correctly close the forward-chain security gap in the non-OP_CAT setting? Specifically: given the committed masked public keys `pk_i = F_{k_i}^7(sᵢ)` and a revealed chain value `C_{i,d_i}^{WOTS+}` (where each step XORs the bitmask before hashing), can an adversary compute `C_{i,d_i+1}^{WOTS+}` without knowing `k_{i,d_i}` (the bitmask for step `d_i`)?**
   *Answerable in 2–3 hours by implementing the WOTS+ chain computation in Python with and without bitmask knowledge, and verifying that forward computation without the bitmask produces values that fail the public key check.*

3. **What is the concrete gate count, garbling time, and evaluation time of the GC checksum sub-circuit for (a) Direction A/B: w=8, 86 message digits, 10-bit sum output, 4 checksum digits, and (b) the combined Direction C: w=16, 67 message digits, 10-bit sum output, 3 checksum digits — implemented in a standard GC library (EMP-toolkit or JustGarble) and profiled against a 1M-gate baseline circuit?**
   *Answerable in 1–2 days by implementing and benchmarking the arithmetic circuits in EMP-toolkit.*

4. **What is the total on-chain vByte cost of one complete BitVM3 dispute-resolution round under the combined Direction A/C design, broken down by transaction phase (setup, assertion, challenge, response, resolution), compared against the Lamport baseline — measured by constructing the full transaction graph using `rust-bitcoin` with correct witness data at current Bitcoin fee rates (~50 sat/vByte)?**
   *Answerable in 2–3 days by implementing a transaction size simulator that constructs the full BitVM3 transaction graph with WOTS+ and Lamport witnesses and computes vByte costs per phase.*

5. **Can the verifier's digit-constraint mask derivation (Direction C) be made bias-resistant against a malicious verifier using a standard two-party coin-toss protocol (hash-then-reveal), and does any residual bias in the resulting digit distribution affect the simulation security of the garbled circuit — specifically, does a non-uniform digit distribution over `{8,...,15}` leak information about the GC's input labels?**
   *Answerable by a formal analysis of the coin-toss protocol's bias bound and a reduction argument from GC simulation security: the question reduces to whether non-uniform distribution of `C_{i,d_i}` over a constrained set affects the PRF-based label derivation, which it does not given HMAC-SHA256's input-independence.*

6. **For the combined protocol, what is the minimum number of Tapscript leaves that must be spent across all phases of a complete BitVM3 dispute round, and what is the optimal Huffman tree depth assignment for the combined 90-leaf (Direction A assertion) and 67-leaf (Direction C challenge) Merkle trees that minimises expected Merkle proof overhead given the probability distribution of leaf spends across protocol phases?**
   *Answerable by modelling the BitVM3 protocol's state machine, computing expected leaf-spend frequencies per phase, and running a Huffman tree optimisation — implementable as a ~1 day programming exercise.*

7. **Does composing the Direction A depth-3 OP_IF leaf design with the OP_CAT upgrade path (Direction D) require any change to the garbled circuit input encoding or the bit-decomposition adapter, or is the adapter entirely agnostic to whether bitmask XOR is performed on-chain (OP_CAT) or approximated via pre-committed public keys (non-OP_CAT)?**
   *Answerable by a formal interface analysis: the adapter takes `C_{i,d_i}^{WOTS+}` as input in both cases and the HMAC label derivation is identical — the question reduces to whether the two methods produce identical `C_{i,d_i}^{WOTS+}` values, which they do if the bitmasks are the same, confirming adapter agnosticism.*
