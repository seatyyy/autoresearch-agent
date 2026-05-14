# 01 — Scope & Plan

**Topic:** In BitVM3, garbled circuits are used to do off-chain proof verification based on a signed proof put on the Bitcoin chain. The signed proof is input into the garbled circuit as input labels. In most existing designs, the signature scheme is a Lamport signature, which is verifiable by Bitcoin. Can you provide a re-design using Winternitz signatures instead of Lamport signatures?

**Model:** `claude-sonnet-4-6`  
**Tokens:** in=2,718 out=9,302  
**Cost:** $0.1477

---

# Scope Document: BitVM3 Redesign with Winternitz Signatures

---

## 1. Candidate Solutions

### Direction A: Direct WOTS Substitution with Script-Unrolled Hash Chains (w=16)

Replace each Lamport bit-signing element with a Winternitz one-time signature component using parameter w=16 (4-bit blocks). The Bitcoin Script verifier unrolls the hash chain inline — for each message block, it applies `OP_SHA256` up to 15 times depending on the revealed block value, then checks against the committed public key hash. The prover reveals `σ_i = H^{m_i}(x_i)` for each 4-bit block of the proof hash, and a checksum chain prevents downward forgery. Garbled circuit input labels are defined directly as the Winternitz chain values `H^v(x_i)`, so signature revelation and label delivery are unified into a single operation. The entire verification is implemented in Bitcoin Script using only `OP_SHA256`, `OP_DUP`, `OP_EQUALVERIFY`, and numeric opcodes, requiring no consensus changes.

### Direction B: WOTS+ with Randomised Hash Chains for Tighter Security Proof

Adopt WOTS+ (the variant used in XMSS/SPHINCS+), which applies a bitmask XOR at each hash step: `H(r_i ⊕ val)` where `r_i` are public randomisation values committed at setup. This provides a tighter security reduction to second-preimage resistance rather than the weaker pseudorandom function assumption required by basic WOTS. The randomisation values `r_i` are committed on-chain in the setup transaction and included in the Script as constants. Bitcoin Script implements the chain as: push bitmask constant, `OP_XOR`, `OP_SHA256`, repeated w-1 times per block. Label binding is modified so the garbled circuit input label for wire i at value v is `WOTS+_chain_v(x_i)`, preserving the unification of signing and label delivery while upgrading the security proof.

### Direction C: WOTS with Compact Script via Tapscript Leaf Decomposition

Rather than placing the full unrolled Winternitz verification in a single Script, decompose the verification across multiple Tapscript leaves — one leaf per Winternitz block or small group of blocks. Each leaf handles one block's hash chain unrolling and checksum partial sum update, with the partial state threaded through the witness stack or committed via intermediate hashes in a Merkle tree. This approach keeps each individual script leaf within practical size limits and exploits Taproot's leaf versioning to allow future upgrades. The garbled circuit input labels are derived identically to Direction A (chain values serve as labels), but the on-chain binding uses a Tapscript tree whose leaf structure mirrors the block decomposition of the proof hash.

### Direction D: Winternitz Signatures with Off-Chain Verification and On-Chain Hash Commitment (Optimistic Path)

Optimise for the common (honest) case by keeping Winternitz verification entirely off-chain, posting only a hash commitment of the full signature and the corresponding garbled circuit evaluation transcript on-chain. The on-chain commitment is a single 32-byte hash: `C = H(σ_1 || σ_2 || ... || σ_n || GC_output)`. The Bitcoin Script in the challenge path verifies this commitment by requiring the challenger to reveal the full preimage, then applies a compact on-chain check of only the violated Winternitz block (single-block dispute rather than full-signature verification). This drastically reduces the on-chain footprint for the honest path to near-zero overhead, with the full Winternitz chain verification only triggered on a per-block basis during disputes, making the worst-case Script small (one block's unrolled chain, not all blocks).

### Direction E: Winternitz over BLAKE3/SHA256 with Precomputed Chain Shortcuts Stored in Tapleaves

Use a tree of precomputed intermediate chain values stored as Tapscript leaves to avoid full unrolling in a single Script execution. Specifically, for a chain of depth w=256 (maximum compression), precompute and commit to intermediate values at depths `{1, 2, 4, 8, ..., w/2}` in a binary Merkle tree of Tapleaves. During verification, the Script only needs to hash from the nearest committed intermediate to the target, bounding the per-execution hash count to O(log w) rather than O(w). This enables using large w (high compression, fewer garbled circuit input wires) without hitting per-script opcode or size limits. Labels are again unified with chain values, but the label delivery also includes a Merkle proof to the relevant intermediate commitment.

---

## 2. Evaluate Directions

### Direction A: Direct WOTS Substitution (w=16)

**1. On-chain script size (bytes)**
For a 256-bit proof hash: 64 message blocks (4 bits each) + 8 checksum blocks = 72 chain elements. Each element requires up to 15 `OP_SHA256` operations plus stack management — roughly 20–40 bytes of script per element. Total script size: approximately 72 × 35 ≈ **2,520 bytes**, compared to the Lamport baseline of 512 × ~10 ≈ 5,120 bytes. A ~2× script size reduction. This is within Bitcoin's 10,000-byte standard script limit under Tapscript, but tight.

**2. On-chain transaction cost (vbytes / fees)**
The challenge transaction witness contains the Winternitz signature (72 revealed chain values × 32 bytes = 2,304 bytes) plus the script. Total witness data ≈ 2,304 + 2,520 ≈ 4,824 bytes witness weight (discounted), or roughly **1,206 vbytes** for the witness component alone. Compared to Lamport (512 × 32 bytes signature = 16,384 bytes witness ≈ 4,096 vbytes), this is approximately a **3.4× improvement** in witness vbytes. Transaction fees scale proportionally.

**3. Signature/witness data size (on-chain)**
Lamport signature for 256-bit message: 256 revealed pre-images × 32 bytes = **8,192 bytes**. WOTS (w=16): 72 chain values × 32 bytes = **2,304 bytes**. Compression ratio: **3.6×**. The public key commitment (posted at setup) shrinks from 512 × 32 bytes = 16,384 bytes to 72 × 32 bytes = **2,304 bytes** (3.6× reduction in committed public key hashes).

**4. Garbled circuit input label encoding overhead (off-chain)**
With Lamport, each bit of the proof maps to one of two 32-byte labels — direct 1:1 mapping, 256 labels total. With WOTS (w=16), each 4-bit block maps to one of 16 chain values, 64 blocks total. The garbled circuit therefore has 64 input wires (each carrying 16 possible label values) rather than 256 binary wires. The circuit topology must change: the garbled circuit must handle multi-valued (16-ary) input wires or encode them as 4 binary wires per block — the latter is natural and yields exactly 256 binary garbled wires, but each set of 4 is constrained to correspond to a single Winternitz chain. The off-chain label delivery mechanism is slightly more complex (the evaluator must identify which of 16 chain positions was revealed), but no additional hashing beyond the chain itself is needed. **Overhead is minimal** — the circuit input count is unchanged (256 wires), but the label binding structure is richer.

**5. Computational overhead (prover and verifier)**
Prover (signing): For each of 72 elements, compute the chain `H^{m_i}(x_i)` — average chain length ≈ 7.5 for uniform distribution over w=16. Total: 72 × 7.5 ≈ **540 hash operations** to produce the signature (plus 72 × 15 = 1,080 ops to precompute public keys at setup). Lamport prover cost: 256 hash operations for signing (trivial), 512 for key generation. So WOTS signing is **slightly more expensive** but key generation is cheaper. On-chain Script verifier: for each element, applies H^{w - m_i} times, average 7.5 ops × 72 elements ≈ **540 hash ops** total in Script. Comparable to Lamport's 256 hash checks, but each WOTS hash check involves fewer Script bytes due to the 4× block compression.

**6. Security level and parameter soundness**
WOTS with w=16 and SHA256 achieves 128-bit security against existential forgery under the pseudorandom function assumption on the hash, assuming one-time key use. The checksum mechanism (sum of `w - m_i` = constant) ensures an adversary cannot forge by decreasing block values without increasing checksum blocks, which requires finding hash chain preimages. With SHA256, the security is standard and well-analysed. The 8-checksum-block overhead is correct for w=16 (checksum range is 0 to 64×15=960, requiring ⌈log₁₆(960)⌉ = 3 blocks, or more conservatively with padding, typically 3–4 blocks for w=16 over 64 message blocks). **Security level: adequate at 128 bits.**

**7. Bitcoin script compatibility and feasibility**
All required operations (`OP_SHA256`, `OP_DUP`, `OP_SWAP`, `OP_EQUALVERIFY`, `OP_ADD`, `OP_NUMEQUAL`) are available in Bitcoin Script. The unrolling is mechanical — for an element at position i with known chain depth needed, the Script branches or uses a fixed worst-case chain. The critical challenge is that the block value `m_i` is revealed in the witness, and Script must apply exactly `w - m_i` hashes. Without loops, this requires **conditional Script blocks** or an unrolled chain that always applies w-1 hashes with intermediate results discarded based on the block value — achievable but verbose. Under Tapscript (BIP 342), the 10,000-byte script limit and 201-opcode limit may be strained for a monolithic script; Tapscript removes the opcode limit, so the main constraint is the 10,000-byte limit. **Feasibility: achievable but requires careful script engineering.**

**8. Reduction in public key / commitment size**
Public keys: Lamport commits 512 hash values (256 pairs) = 512 × 20 bytes (with OP_HASH160) = **10,240 bytes** or 512 × 32 bytes with SHA256 = **16,384 bytes**. WOTS commits 72 chain-end values = 72 × 32 bytes = **2,304 bytes**. Reduction: **7.1× smaller public key commitment** for SHA256. This directly reduces the size of the setup/funding transaction output script or Tapscript commitment, lowering setup costs.

**9. Protocol security under composition**
The WOTS one-time signature property is preserved: the private key is used exactly once per garbled circuit instance, matching BitVM3's one-time-use structure per round. The binding between the signed proof and garbled circuit input labels remains tight — the revealed chain value is simultaneously the signature and the label, so no additional binding argument is needed beyond what Lamport provides. The bisection/challenge-response game's soundness is unaffected since it relies on Bitcoin Script's ability to verify the signature, not on the specific scheme. **No degradation in compositional security**, provided one-time key discipline is maintained.

**10. Novelty and design elegance**
This is the most direct approach and represents a clean, well-motivated engineering improvement. The identification that Winternitz chain values naturally serve as garbled circuit labels is non-trivial and elegant. However, the Script unrolling technique is known in the BitVM/one-time-signature-on-Bitcoin literature. **Moderate novelty** — a solid, publishable engineering contribution with clear metrics, but not a conceptually novel breakthrough.

**Risks:** The primary risk is that the unrolled Bitcoin Script for 72 chain elements with variable hash depth exceeds practical Script size limits or becomes too complex to audit and implement correctly. A secondary risk is that block-value-dependent Script branching introduces subtle correctness bugs if not all branch paths are tested.

---

### Direction B: WOTS+ with Randomised Hash Chains

**1. On-chain script size (bytes)**
Each WOTS+ step requires an XOR with a bitmask before hashing: `OP_XOR OP_SHA256`. The bitmask must be pushed as a constant (32 bytes) per step. For 72 elements × up to 15 steps × (32-byte push + OP_XOR + OP_SHA256 + stack ops) ≈ 72 × 15 × 38 ≈ **41,040 bytes** for the worst-case full chain. This **far exceeds** Bitcoin's 10,000-byte script limit even under Tapscript. Significant fragmentation across Tapleaves would be required.

**2. On-chain transaction cost (vbytes / fees)**
If decomposed into Tapleaves (one per element or per step), the Tapscript tree overhead adds Merkle proof bytes per leaf reveal. Rough estimate: 72 Tapleaf reveals × (script bytes + Merkle path) → transaction cost increases substantially. **Likely 2–4× worse than Direction A** in terms of total on-chain bytes, despite the same signature size.

**3. Signature/witness data size (on-chain)**
Identical to Direction A (72 × 32 bytes = 2,304 bytes) for the signature values. Additional witness data includes the bitmask values `r_i` if not hardcoded in Script, adding up to 72 × 15 × 32 bytes = **34,560 bytes** — catastrophic if included in witness. If pre-committed at setup as Script constants, the witness size stays at 2,304 bytes but the setup transaction balloons. **Net signature size unchanged; overall protocol on-chain data increases.**

**4. Garbled circuit input label encoding overhead (off-chain)**
WOTS+ chain values are `H(r ⊕ val)` at each step, so the labels are defined differently from plain hash chains. The garbled circuit evaluator must know the bitmasks `r_i` to verify label correctness (`H^{w-m_i}` in WOTS+ sense). These bitmasks must be distributed to the evaluator at setup, adding **O(w × n)** bytes of auxiliary data per garbled circuit instantiation. This overhead is non-trivial for large w.

**5. Computational overhead (prover and verifier)**
WOTS+ signing: same chain structure, but each step is `H(r_i ⊕ val)` instead of `H(val)`. Prover cost is essentially doubled in constant factor (one XOR + one hash vs. one hash per step). On-chain Script verifier: same doubling of operations per step. The net computation is **~2× that of Direction A**.

**6. Security level and parameter soundness**
WOTS+ has a tighter security reduction to the underlying hash function's second-preimage resistance, rather than requiring pseudorandomness. This is a genuine security improvement — relevant if the hash function is used in a setting where pseudorandomness is hard to argue. For Bitcoin's SHA256, the PRF assumption is standard and uncontroversial, so the security improvement of WOTS+ is **theoretically meaningful but practically marginal** for this application.

**7. Bitcoin script compatibility and feasibility**
The `OP_XOR` opcode is **not available in standard Bitcoin Script** (it was disabled). While it exists conceptually in some extended script proposals, it is not in the current mainnet opcode set. This is a critical compatibility failure. Workarounds using arithmetic operations to simulate XOR are expensive and complex (requiring bit decomposition). **Major feasibility concern — likely requires a different bitmask application method or falls back to scalar addition mod 2^256, which is not native either.**

**8. Reduction in public key / commitment size**
Same as Direction A for the chain-end values (72 × 32 bytes). However, the bitmasks `r_i` must also be committed, adding 72 × 15 × 32 bytes = 34,560 bytes of committed randomisation values. **Net public key/commitment data is much larger than Direction A, negating the WOTS+ security benefit.**

**9. Protocol security under composition**
The tighter security proof of WOTS+ strengthens the overall protocol, but the practical gains are negligible for SHA256. The protocol composition is otherwise identical to Direction A. **Marginally better in theory, not meaningfully better in practice.**

**10. Novelty and design elegance**
Applying WOTS+ to Bitcoin Script is novel but the `OP_XOR` unavailability makes it inelegant — a theoretically motivated approach that runs into a concrete practical barrier. **Low elegance due to the XOR problem; moderate novelty.**

**Risks:** The fatal risk is `OP_XOR` unavailability in Bitcoin Script. Without XOR, the WOTS+ construction either cannot be implemented or requires a prohibitively complex workaround. This direction is likely infeasible without a soft fork enabling XOR, making it unsuitable for a near-term BitVM3 deployment.

---

### Direction C: WOTS with Compact Script via Tapscript Leaf Decomposition

**1. On-chain script size (bytes)**
Each Tapleaf handles one Winternitz block (one chain element). Per-leaf Script: unroll up to 15 `OP_SHA256` operations + checksum partial update + equality check ≈ 150–200 bytes per leaf. 72 leaves × 180 bytes ≈ **12,960 bytes total** across all leaves, but each individual leaf is well within the 10,000-byte per-leaf limit. The Tapscript tree adds a Merkle tree of depth log₂(72) ≈ 7, so each leaf reveal requires a **7-element Merkle proof (224 bytes)**.

**2. On-chain transaction cost (vbytes / fees)**
In the honest case, no leaves are revealed — only the key path is used, costing **0 extra vbytes**. In the dispute case, the challenger reveals one or more leaves; each leaf reveal costs ≈ 200 bytes (script) + 224 bytes (Merkle proof) + 32 bytes (signature value) + witness overhead ≈ **500 bytes per disputed block**. If the entire signature must be verified in the dispute case, 72 leaf reveals × 500 bytes ≈ **36,000 witness bytes**, which is large but could be spread across multiple transactions in a bisection protocol. **Better than monolithic approach for partial disputes; worse for full-verification disputes.**

**3. Signature/witness data size (on-chain)**
If only the disputed elements need to be revealed (as in a bisection game), the on-chain signature data is proportional to the number of disputed blocks. In the worst case (full verification), it matches Direction A. **In the average/optimistic case, significantly less on-chain data is needed.**

**4. Garbled circuit input label encoding overhead (off-chain)**
Identical to Direction A — the chain values serve as labels. The Tapscript decomposition is a verification-side optimisation and does not affect label encoding or garbled circuit structure. **No additional overhead.**

**5. Computational overhead (prover and verifier)**
Prover: same as Direction A plus the one-time cost of building the Tapscript Merkle tree (72 SHA256 operations for leaf hashing + ~140 hashes for the tree). **Negligible overhead.** On-chain verifier: same per-leaf hash chain computation, but only for disputed leaves. For the honest case, **no hash computation needed on-chain**.

**6. Security level and parameter soundness**
Identical to Direction A — the Winternitz construction and parameters are the same. The Tapscript decomposition is a structural optimisation, not a change to the cryptographic primitive. **Security level unchanged at 128 bits.**

**7. Bitcoin script compatibility and feasibility**
Each individual Tapleaf script is small and uses only standard opcodes. The Tapscript tree structure is well-supported in current Bitcoin (post-Taproot activation, BIP 341/342). The challenge is correctly threading the checksum partial sums across leaves — this may require either accepting a per-leaf checksum approach (less efficient but self-contained) or a multi-leaf transaction structure where checksum verification is a separate leaf. **Good feasibility with careful engineering of checksum threading.**

**8. Reduction in public key / commitment size**
The Tapscript tree root is a single 32-byte value — the public key commitment is just the Taproot internal key + Merkle root, effectively **32 bytes regardless of w or n**. The actual public key hashes are embedded in the leaves and not posted on-chain until a dispute. This is a **massive reduction in on-chain commitment size** at setup: from 72 × 32 = 2,304 bytes (Direction A) to effectively **32 bytes** for the Taproot commitment.

**9. Protocol security under composition**
The Tapscript leaf binding is secured by the Taproot commitment scheme (SHA256-based Merkle tree), which is standard and well-audited. The one-time signature property and label binding are preserved. The dispute game must be redesigned to accommodate the leaf-by-leaf revelation pattern, but this aligns naturally with BitVM3's bisection protocol. **No degradation in security; improved efficiency in the honest case.**

**10. Novelty and design elegance**
Using Tapscript leaf decomposition to decompose Winternitz verification is a meaningful structural insight — it exploits Taproot's design in a non-obvious way (treating each signature block as a separately-spendable leaf). The integration of Winternitz block-by-block verification with the bisection challenge game is novel and elegant. **High novelty and elegance.**

**Risks:** The main risk is complexity in the checksum handling across multiple Tapleaves — ensuring that partial checksum sums from different leaves are correctly aggregated and verified without allowing adversarial manipulation is a subtle engineering challenge. A secondary risk is that the bisection protocol must be redesigned to work with leaf-by-leaf revelation, potentially increasing the number of rounds in the challenge game.

---

### Direction D: Winternitz with Optimistic Off-Chain Verification and Per-Block On-Chain Dispute

**1. On-chain script size (bytes)**
The commitment transaction contains only a 32-byte hash `C = H(σ_1 || ... || σ_n || GC_output)` — **32 bytes** on-chain at commitment time. The dispute script for a single challenged block is: unroll one Winternitz chain (up to 15 `OP_SHA256` ops) + hash preimage verification + checksum check ≈ **300–400 bytes per disputed block**. This is the smallest per-script footprint of all directions.

**2. On-chain transaction cost (vbytes / fees)**
Commitment transaction: near-baseline cost (32-byte hash addition to existing output). Dispute transaction for one block: ≈ 400 bytes script + 32 bytes σ_i + 32 bytes Merkle proof ≈ **500 vbytes per dispute**. Full dispute across all blocks (worst case) requires sequential challenge transactions, each small. **Optimal for the honest case (nearly free); competitive for the dispute case.**

**3. Signature/witness data size (on-chain)**
In the honest (optimistic) case: **32 bytes** (just the hash commitment). In the dispute case: **32 bytes per disputed block** (the revealed chain value) plus the preimage of the commitment hash (full signature = 2,304 bytes) is revealed once to enable block-level checking. **Overall reduction in witness data in the common case is ~99.9% versus Lamport.**

**4. Garbled circuit input label encoding overhead (off-chain)**
Off-chain, the full Winternitz signature is computed and used to derive garbled circuit input labels, identical to Direction A. The labels themselves are the chain values. The evaluator works entirely off-chain with the full signature. **No additional off-chain overhead beyond Direction A.**

**5. Computational overhead (prover and verifier)**
Prover: identical to Direction A (72 chain computations) plus one SHA256 to compute the commitment hash — **negligible overhead**. On-chain verifier: in the dispute case, verifies one block's chain (up to 15 SHA256 ops) plus checks the commitment preimage (one SHA256 on 2,304 bytes). **Dramatically less on-chain computation than any other direction.**

**6. Security level and parameter soundness**
Security depends on two layers: (1) the SHA256 collision resistance of the commitment hash (128-bit), and (2) the WOTS one-time signature security (128-bit with w=16). Both assumptions are standard. A subtlety: the commitment hash binds the entire signature and GC output, so the prover cannot selectively reveal only valid blocks without revealing invalid ones. **Security level equivalent to Direction A; the optimistic layer does not weaken it.**

**7. Bitcoin script compatibility and feasibility**
The commitment script is trivial (OP_SHA256 + OP_EQUALVERIFY). The dispute script for one block is small and uses only standard opcodes. **Easiest of all directions to implement in Bitcoin Script.** The main protocol engineering challenge is defining the dispute game correctly so that a single bad block is sufficient to invalidate the whole proof — this requires the dispute protocol to correctly identify and challenge individual blocks, which aligns with existing BitVM bisection designs.

**8. Reduction in public key / commitment size**
Setup transaction commits only to a Taproot key (32 bytes) encoding the dispute script tree. Individual public key hashes for Winternitz blocks are embedded in the dispute leaves and revealed on demand. **On-chain setup commitment is essentially constant-size** regardless of signature scheme parameters, which is the best possible outcome.

**9. Protocol security under composition**
The optimistic path relies on the prover behaving correctly and the garbled circuit evaluation being verifiable off-chain. If the prover posts an incorrect commitment, the challenger can initiate a block-level dispute. The bisection game must correctly decompose to individual Winternitz blocks. This is a redesign of the challenge protocol, not just a signature substitution — it requires careful security proof that the per-block dispute is sufficient for full soundness. **Potential soundness gap if the dispute protocol is not designed carefully; this is the main compositional risk.**

**10. Novelty and design elegance**
The separation of optimistic commitment from per-block dispute, combined with Winternitz label delivery, is genuinely novel in the BitVM context. It reframes the on-chain verification problem as a succinctness problem where only the disputed part needs to be verified. **High novelty; potentially the most impactful design of the five directions.**

**Risks:** The critical risk is the protocol redesign required for the challenge game. The existing BitVM3 bisection protocol assumes full signature verification in the dispute path; per-block dispute requires a new soundness argument. If a prover can post a commitment that is consistent on all individually verifiable blocks but inconsistent when combined, soundness breaks. The commitment hash `C` must be designed to prevent this — which requires careful cryptographic argument.

---

### Direction E: Winternitz with Precomputed Chain Shortcuts in Tapleaves (w=256)

**1. On-chain script size (bytes)**
Each intermediate chain value at depth 2^k is stored as a Tapscript leaf. For w=256 and binary shortcuts, there are log₂(256) = 8 intermediate levels per element. For n=32 elements (at w=256, fewer elements needed), total leaves: 32 × 8 = 256 leaves. Each leaf script: 2–3 hash operations + equality check ≈ 60 bytes. Total leaf script data: 256 × 60 ≈ **15,360 bytes across the tree**, but each leaf is tiny. The Tapscript tree depth for 256 leaves is 8, adding 256 bytes per Merkle proof. **Individual script sizes are small; tree overhead is moderate.**

**2. On-chain transaction cost (vbytes / fees)**
Using w=256 reduces message blocks to 32 (for 256-bit proof hash, 8 bits per block). On-chain signature is 32 × 32 bytes = **1,024 bytes** — the most compact of all directions. The shortcut Merkle proof per dispute adds ≈ 8 × 32 = 256 bytes. **Lowest signature witness size; moderate dispute overhead.**

**3. Signature/witness data size (on-chain)**
Lamport: 8,192 bytes. Direction A (w=16): 2,304 bytes. Direction E (w=256): 32 × 32 = **1,024 bytes** for the signature proper. The Merkle proof for shortcuts adds ~256 bytes per disputed element, but this is only in the dispute path. **Best-in-class signature compression: 8× smaller than Lamport.**

**4. Garbled circuit input label encoding overhead (off-chain)**
With w=256 and 32 elements, the garbled circuit has 32 input wires each with 256 possible label values (8 bits per wire). Encoding 256-ary values as binary garbled wires requires 8 binary wires per block = 256 binary wires total, same count as Lamport and Direction A. The shortcut intermediates must be communicated to the evaluator to enable label verification, adding O(n × log w) = 32 × 8 = 256 intermediate hash values as auxiliary data. **Off-chain overhead is moderate and manageable.**

**5. Computational overhead (prover and verifier)**
Prover: must precompute the full chain (255 hashes per element × 32 elements = **7,680 hash operations** for key generation) plus store 8 × 32 = 256 intermediate values. This is **14× more computation than Direction A** for key generation, though signing itself is at most 255 × 32 = 7,680 ops. On-chain verifier (per disputed element): at most 8 hash operations using the shortcut (log₂(255) ≈ 8 steps from the nearest intermediate). **Verification is efficient; key generation is expensive.**

**6. Security level and parameter soundness**
WOTS with w=256 has a larger checksum overhead (⌈log₂₅₆(32 × 255)⌉ = ⌈log₂₅₆(8160)⌉ ≈ 2 extra blocks) and maintains 128-bit security with SHA256. The shortcut intermediates are public committed values — revealing them does not weaken security since they lie above the signing point on the chain. **Security level maintained; parameter analysis for w=256 checksum is more complex and must be verified carefully.**

**7. Bitcoin script compatibility and feasibility**
Each Tapleaf script is extremely simple — 2–3 hash operations maximum. No issues with opcode limits or script size. The complexity is in correctly building and navigating the shortcut Merkle tree, and in correctly threading the partial chain evaluation across the lookup structure. The dispute protocol must specify which shortcut leaf to use based on the revealed message block value. **Individually feasible scripts; complex overall protocol coordination.**

**8. Reduction in public key / commitment size**
Public key at chain ends: 32 × 32 bytes = 1,024 bytes. Shortcut intermediates: 256 × 32 = 8,192 bytes. Total committed data: **9,216 bytes** — actually more than Direction A (2,304 bytes) because of the shortcut tree. The Taproot commitment collapses this to 32 bytes on-chain, so from the chain's perspective it is constant-size, but the off-chain storage requirement is higher. **On-chain commitment is constant (Taproot root); off-chain data is heavier.**

**9. Protocol security under composition**
The shortcut intermediates introduce additional trust assumptions: they must be committed at setup and correctly match the chain. If the prover incorrectly commits shortcuts, the verifier may accept an invalid chain. The dispute protocol must include verification of the shortcut consistency (that intermediate hashes correctly chain between levels). This adds a new layer of protocol complexity. **Compositional security requires additional argument for shortcut consistency; non-trivial.**

**10. Novelty and design elegance**
The shortcut Merkle tree idea is novel in the Bitcoin/BitVM context and is an interesting connection to hash-based authenticated data structures. However, the increased complexity (off-chain storage, shortcut consistency protocol) partially undermines the elegance. **Moderate-to-high novelty; elegance is compromised by complexity.**

**Risks:** The main risk is the substantial increase in prover computation (thousands of hash evaluations for key generation with w=256) and the complex shortcut consistency verification in the dispute protocol. Additionally, the advantage of w=256 (smaller signature) may be offset by the larger committed intermediate data required for efficient Script verification, yielding no net improvement over w=16 in practice.

---

## 3. Chosen Direction

**Chosen Direction: A combined approach of Direction A and Direction C**, specifically: **WOTS (w=16) with per-block Tapscript leaf decomposition for verification, unified label delivery, and a full checksum verification leaf.**

**Justification:**

Direction A provides the cleanest cryptographic construction — the Winternitz chain values directly serve as garbled circuit input labels, unifying signing and label delivery with no additional overhead, and w=16 achieves a well-understood 3.6× signature compression with 128-bit security under standard assumptions. However, a monolithic verification Script for 72 chain elements strains Bitcoin's script size limits and produces a brittle, hard-to-audit Script. Direction C addresses this by decomposing verification into per-block Tapleaves, each containing a small, independently-auditable unrolled chain Script, while the Taproot commitment reduces the on-chain setup footprint to 32 bytes. The combination gives the best of both worlds: the cryptographic elegance and label-binding property of Direction A, with the practical Script feasibility, dispute-game alignment, and setup efficiency of Direction C. The checksum verification is handled by a dedicated Tapleaf that aggregates partial sums from the revealed blocks, which is a concrete engineering contribution. This combined design is implementable on current Bitcoin (post-Taproot), requires no consensus changes, and produces a measurably better protocol than the Lamport baseline on every key metric (script size, witness data, setup commitment, garbled circuit complexity).

---

## 4. Key Questions

1. **What is the exact Bitcoin Script encoding for a single WOTS block verification leaf (w=16), and does it fit within the Tapscript per-leaf size and opcode constraints?** Specifically: can the unrolled chain (up to 15 `OP_SHA256` operations with the correct block value applied conditionally from the witness) be implemented correctly in ≤200 bytes of Script without `OP_LOOP`, and does the resulting Script correctly reject all invalid chain values?

2. **How should the Winternitz checksum be verified across the Tapscript leaf structure?** In particular: can a single checksum verification leaf receive the committed block values (or their complements) and verify the total checksum constraint without requiring all 72 message leaves to be revealed in the same transaction, and if not, what multi-transaction protocol correctly enforces checksum integrity while remaining compatible with the bisection challenge game?

3. **What is the precise garbled circuit input wire encoding when w=16 blocks are used, and is the evaluator's label verification overhead acceptable?** Specifically: if each Winternitz block of 4 bits maps to a group of 4 binary garbled circuit input wires with correlated labels (all four labels `L_{i,0}, L_{i,1}, L_{i,2}, L_{i,3}` derived from a single chain value via `H^{m_i}(x_i)` and its bit decomposition), does this correlation introduce any attack surface against the garbled circuit's privacy or soundness under the standard half-gates or free-XOR construction?

4. **What is the end-to-end on-chain byte count for the combined Direction A+C design (setup transaction Taproot output, commitment transaction, challenge transaction, response transaction) compared to the Lamport baseline, including all witness data and Merkle proof overhead?** Produce a concrete numerical comparison at the level of individual transaction fields (version, inputs, outputs, witnesses) to validate the claimed 3–4× improvement.

5. **Can the per-block Tapscript leaf dispute protocol be proven sound under the standard BitVM3 security model?** Specifically: is there a formal reduction showing that if an adversary can win the bisection challenge game (i.e., Bitcoin Script accepts an invalid Winternitz block), then the adversary can invert SHA256, and does this reduction extend to cover the checksum leaf and the commitment binding between blocks?

6. **What is the optimal Winternitz parameter w given the joint constraints of Bitcoin Script size limits, transaction fee costs, and garbled circuit complexity?** Concretely: compute the total weighted cost function `α × Script_bytes + β × witness_bytes + γ × GC_wires` for w ∈ {4, 8, 16, 32, 64} and identify whether w=16 is indeed the Pareto-optimal choice or whether w=8 or w=32 dominates in realistic fee environments.

7. **How does the Winternitz key generation and signing protocol interact with the BitVM3 setup phase, and what trust assumptions are required?** In particular: in a two-party (prover/verifier) BitVM3 setup, who generates the Winternitz private keys, how are the public key hashes committed on-chain (in the Tapscript tree leaves), and is it possible for either party to cheat during setup in a way that allows them to produce a valid-looking invalid signature later — and if so, how does the setup protocol prevent this?

8. **What is the concrete implementation complexity of the combined Direction A+C design, and are there off-the-shelf Bitcoin Script libraries or existing BitVM implementations that can be extended?** Specifically: does the existing BitVM2/BitVM3 reference implementation (e.g., the `BitVM` GitHub repository) provide reusable Script gadgets for SHA256 chains that can be repurposed for Winternitz leaf scripts, and what is the estimated implementation effort in person-weeks for a complete prototype including test vectors for the challenge-response game?
