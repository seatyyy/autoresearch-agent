# Run log — In BitVM3, garbled circuits are used to do off-chain proof verification based on a signed proof put on the Bitcoin chain. The signed proof is input into the garbled circuit as input labels. In most existing designs, the signature scheme is a Lamport signature, which is verifiable by Bitcoin. Can you provide a re-design using Winternitz signatures instead of Lamport signatures?

Started: 2026-05-22T03:38:58

- `03:38:58` project=`redesign-signature-scheme` user=`your_user_name` run_id=`your_user_name_20260522T033858`
- `03:38:58` mode: **base run**
- `03:38:58` pipeline start — model=`claude-sonnet-4-6` run_dir=`/work/research_runs/redesign-signature-scheme/your_user_name_20260522T033858` stop_after=`scope`
- `03:38:58` stage **scope** begin
- `03:38:58` 0 seed paper(s), ~0 prompt tokens
- `03:39:44` wrote `01_1_analysis.md` (7,977 chars)
- `03:39:56` wrote `01_2_eval_design.md` (2,834 chars)
- `03:39:56` calling LLM for scope — topic=`In BitVM3, garbled circuits are used to do off-chain proof verification based on a signed proof put on the Bitcoin chain. The signed proof is input into the garbled circuit as input labels. In most existing designs, the signature scheme is a Lamport signature, which is verifiable by Bitcoin. Can you provide a re-design using Winternitz signatures instead of Lamport signatures?`
- `03:39:56` user message to llm: Produce the scope document for the following research task.

**Research Problem:** In BitVM3, garbled circuits are used to do off-chain proof verification based on a signed proof put on the Bitcoin chain. The signed proof is input into the garbled circuit as input labels. In most existing designs, the signature scheme is a Lamport signature, which is verifiable by Bitcoin. Can you provide a re-design using Winternitz signatures instead of Lamport signatures?

**Understanding the Problem:** 

>>> begin of problem understanding

#### High level understanding

## BitVM3 and Garbled Circuits: Redesign with Winternitz Signatures

### Background Context

**BitVM3** is an evolution of the BitVM paradigm that enables off-chain computation verification on Bitcoin without changing the consensus rules. The core mechanism involves:

1. A **prover** generates a proof off-chain
2. The proof is **signed** and committed on-chain
3. A **garbled circuit** verifies the proof off-chain, using the on-chain signature as input
4. The signature provides the **input wire labels** to the garbled circuit — the key insight being that a valid signature naturally selects the correct label for each input bit (0-label or 1-label), making the circuit evaluation authentically tied to the signed data

---

### Why Lamport Signatures Are Currently Used

Lamport signatures are ideal for this setting because:
- They are **one-time, hash-based** and natively verifiable by Bitcoin Script (using `OP_SHA256`, `OP_EQUALVERIFY`)
- Each bit of the message maps to **exactly one pre-image reveal**: to sign bit `b_i`, the signer reveals `sk_i[b_i]`, where `sk_i[0]` and `sk_i[1]` are the two secret values hashed to produce the public key
- This maps **perfectly** to garbled circuit input label selection: `sk_i[0]` ↔ label for wire `i` being 0, `sk_i[1]` ↔ label for wire `i` being 1
- **Drawback**: Lamport is extremely **verbose** — for an `n`-bit message, it requires `2n` hash values in the public key and `n` reveals, leading to large on-chain footprint

---

### Winternitz Signatures: Core Mechanics

Winternitz One-Time Signature (WOTS) is a compression of Lamport signatures:

- For a security parameter `w` (the Winternitz parameter), each **chunk** of `log₂(w)` bits of the message is signed together using a **hash chain** of length `w`
- To sign a chunk with value `v ∈ [0, w-1]`, the signer reveals `H^v(sk_i)` (apply hash `v` times to the secret key fragment)
- The verifier checks by applying `H^(w-v)` and comparing to the public key element `H^w(sk_i)`
- This reduces key/signature size by a factor of `log₂(w)` compared to Lamport
- **Checksum** values are appended to prevent forgery by substituting smaller chunk values

**Common choices**: `w = 4` (2 bits per chunk), `w = 16` (4 bits per chunk), `w = 256` (8 bits per chunk)

---

### The Redesign Challenge: Mapping WOTS to Garbled Circuit Inputs

The fundamental challenge is that Lamport has a **direct bijection** between signature fragments and wire labels, while Winternitz signs *multi-bit chunks* via hash chains, breaking this direct correspondence.

#### Proposed Redesign Strategy

**Step 1: Decompose the signed proof into w-bit chunks**

Instead of treating the proof as individual bits, partition the `n`-bit proof into `⌈n / log₂(w)⌉` chunks of `log₂(w)` bits each.

**Step 2: Redefine garbled circuit input label encoding**

For each chunk `i` with value `v_i ∈ [0, w-1]`, assign **w possible input labels** `{L_i^0, L_i^1, ..., L_i^(w-1)}` instead of just two. The garbled circuit must now be constructed to accept multi-valued (base-`w`) inputs on those wires.

- This requires extending the garbled circuit model to **multi-valued garbling** or decomposing each chunk back into `log₂(w)` binary wires internally, with the label selection happening at the chunk level

**Step 3: Bind WOTS chain values to garbled labels**

For chunk `i`, the WOTS signing procedure reveals `H^(v_i)(sk_i)`. The key binding mechanism is:

- Set label `L_i^(v_i) = H^(v_i)(sk_i)` (or derive it via a PRF from this value)
- The evaluator, upon receiving `H^(v_i)(sk_i)`, can compute the correct label for the chunk value `v_i`
- The garbled circuit is constructed such that only the correct label `L_i^(v_i)` decrypts the correct garbled gate outputs for the sub-circuit handling chunk `i`

**Step 4: On-chain Bitcoin Script verification of WOTS**

Bitcoin Script must verify the WOTS signature before the labels are considered valid:
- For chunk `i`, given revealed value `r_i = H^(v_i)(sk_i)`, verify `H^(w - v_i)(r_i) == pk_i`
- This requires `OP_SHA256` applied iteratively up to `w` times per chunk
- This is scriptable in Bitcoin but requires **w-deep hash chain unrolling** in Script, which is feasible for small `w` (e.g., `w=4` or `w=16`)
- The checksum chunks must also be verified in Script to prevent substitution attacks

**Step 5: Handle the Checksum**

WOTS requires a checksum over all chunk values to prevent an adversary from replacing a chunk `v_i` with `v_i' < v_i` (which would be easier to forge since fewer hash applications are needed). The checksum `C = Σ(w-1-v_i)` is itself signed as additional chunks. In Bitcoin Script, the checksum verification can be computed and checked as part of the input validation script.

---

### Efficiency Gains

| Property | Lamport | WOTS (w=16) | WOTS (w=256) |
|---|---|---|---|
| Secret key fragments per bit | 2 | 0.25 | 0.125 |
| On-chain signature size (n=256 bits) | 256 hash reveals | 64 + checksum reveals | 32 + checksum reveals |
| Bitcoin Script complexity | Linear in n | ~4× smaller | ~8× smaller |
| Bits per chunk | 1 | 4 | 8 |

For a 256-bit proof hash, WOTS with `w=16` reduces the signature from 256 hash reveals to approximately 64 + ~18 checksum chunks = ~82 reveals — roughly a **3× compression**.

---

### Key Design Considerations and Tradeoffs

1. **Garbled circuit complexity increases slightly**: The circuit must now handle multi-valued inputs or internally decode chunks, but this is a one-time circuit construction cost, not an on-chain cost

2. **Label derivation security**: The binding between WOTS chain values and garbled labels must be done via a PRF/KDF to ensure that knowing `H^(v_i)(sk_i)` doesn't leak labels for other values `v_j ≠ v_i` of the same chunk. Specifically: `L_i^(v_i) = PRF(H^(v_i)(sk_i), "label")` with domain separation

3. **One-time use**: Both Lamport and WOTS are one-time signatures. This property is preserved and is actually **desirable** in BitVM because each proof verification session uses a fresh key commitment

4. **Checksum wires**: The checksum chunks must also be fed into the garbled circuit (or verified externally in Script), adding a small overhead that partially offsets the compression gain

5. **w selection**: `w=16` is likely optimal for Bitcoin Script — it provides good compression while keeping the hash chain depth manageable. `w=256` gives more compression but requires up to 255 sequential hash operations per chunk in Script verification, which may hit Script size/opcode limits

6. **Compatibility with WOTS+**: The WOTS+ variant (which randomizes hash inputs to improve security proofs) can be used with minor modifications — the randomization masks must either be public parameters committed to on-chain, or derived deterministically

---

### Summary of the Redesign

The redesign replaces the **1-bit-per-reveal** Lamport structure with a **log₂(w)-bits-per-reveal** Winternitz structure. The garbled circuit input wire labels are derived from WOTS hash chain values at specific depths, creating a cryptographically binding mapping between the on-chain WOTS signature and the off-chain garbled circuit evaluation. Bitcoin Script verifies the WOTS signature by checking hash chain completions, while the garbled circuit evaluator uses the revealed chain values to select correct input labels. This achieves the same security guarantees as the Lamport-based design with significantly reduced on-chain data footprint, making it more practical for Bitcoin's constrained scripting environment.

>>> end of problem understanding 

Output a single markdown document with exactly the following sections, in this order:

### 1. Candidate Solutions

3–5 candidate directions that can **SOLVE** the specific research problem. 

++NOTE++: for all the directions you choose, you MUST make sure it's to the point and targets to solving the exact problem. It should NOT be solving adjacent problems. It should NOT be simply explorations of the research problem. Focus on **SOLVING** the problem. 

### 2. Evaluate Directions 

For each direction, evaluate it based on following evaluation metrics:

#### Eval metrics

1. **On-chain script size (bytes)**: The total size of Bitcoin scripts required to verify the Winternitz signature on-chain, directly impacting transaction fees and feasibility within Bitcoin's script limits.

2. **On-chain transaction cost (vbytes / fees)**: The overall cost of committing and challenging transactions on the Bitcoin blockchain, including witness data and script execution overhead.

3. **Signature size (on-chain payload)**: The number of bytes that must be pushed on-chain as the signed proof (Winternitz signature output), since this directly determines the input label commitment size and data footprint on Bitcoin.

4. **Garbled circuit input label encoding efficiency**: How compactly and cleanly the Winternitz signature verification output maps to garbled circuit input labels off-chain, including the number of labels required and the overhead introduced relative to Lamport.

5. **Off-chain computation and communication overhead**: The computational cost and bandwidth required for the prover and verifier to generate, transmit, and evaluate the garbled circuit with Winternitz-derived labels, including circuit size changes.

6. **Security level and cryptographic soundness**: Whether the redesign maintains or improves the target security parameter (e.g., 128-bit security), and whether the Winternitz one-time signature security assumptions are sound under the Bitcoin threat model.

7. **Script opcode compatibility and Bitcoin consensus constraints**: Whether the Winternitz verification logic can be implemented purely within Bitcoin's constrained scripting language (e.g., no `OP_CAT` assumptions, or explicitly scoped to specific soft forks).

8. **Reduction in number of on-chain keys/commitments**: The degree to which Winternitz's hash chaining reduces the number of individual key commitments compared to Lamport (a core efficiency motivation), measured as a compression ratio.

9. **Round complexity and protocol interaction**: The number of on-chain and off-chain rounds required between the prover and verifier/challenger, and whether Winternitz introduces additional interaction compared to the Lamport baseline.

10. **Novelty and technical contribution**: The degree to which the redesign introduces non-trivial innovations in adapting Winternitz OTS to the BitVM garbled-circuit context, beyond a straightforward substitution of the signature scheme.

as well as **Risks:** the main thing that could make this direction fail

### 3. Chosen Direction

Pick ONE direction and justify the choice in 3–5 sentences. If the best approach is to combine different directions to a single approach. Do it and give the combined output. 

### 4. Key Questions

A numbered list of 4–8 specific, answerable questions that can be answered by experimentation stage.
- `03:41:41` LLM ok — tokens in=3,038 out=5,054 cost=$0.0849 model=`claude-sonnet-4-6`
- `03:41:41` wrote `01_3_scope.md` (20,737 chars)
- `03:42:51` wrote `01_4_critic_0.md` (12,880 chars)
- `03:42:51` Critic score (Initial): 7.0/10
- `03:45:17` LLM ok — tokens in=11,329 out=7,270 cost=$0.1430 model=`claude-sonnet-4-6`
- `03:45:17` wrote `01_5_evolve_1.md` (27,477 chars)
- `03:46:33` wrote `01_4_critic_1.md` (14,123 chars)
- `03:46:33` Critic score (Initial): 7.0/10
- `03:49:56` LLM ok — tokens in=13,717 out=9,865 cost=$0.1891 model=`claude-sonnet-4-6`
- `03:49:56` wrote `01_5_evolve_2.md` (35,443 chars)
