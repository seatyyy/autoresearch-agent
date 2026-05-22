# 01_4 — Critic

**Problem:** In BitVM3, garbled circuits are used to do off-chain proof verification based on a signed proof put on the Bitcoin chain. The signed proof is input into the garbled circuit as input labels. In most existing designs, the signature scheme is a Lamport signature, which is verifiable by Bitcoin. Can you provide a re-design using Winternitz signatures instead of Lamport signatures?

### Score: 7 / 10

### Justifications:

The problem understanding and candidate solutions demonstrate a solid grasp of the cryptographic primitives involved — WOTS mechanics, garbled circuit input label binding, and Bitcoin Script constraints. The evaluation matrix is thoughtful and the chosen direction (A) is reasonable. However, several gaps prevent a higher score:

1. **The most critical security issue is identified but not resolved**: The hash chain ordering problem — that revealing `H^v(sk_i)` leaks `H^j(sk_i)` for all `j < v` — is flagged but the proposed PRF mitigation is hand-wavy. This is not just a proof obligation; it is a **fundamental structural incompatibility** between WOTS and garbled circuit label security that requires a concrete construction, not a reference to domain separation.

2. **The label binding mechanism conflates two distinct security requirements**: In Lamport, the signer reveals *one* of two secrets, and the *other* remains hidden — this is what provides input privacy/label hiding for the unchosen wire. In WOTS, the hash chain structure means the unchosen values (those *above* `v_i` in the chain) are not revealed, but those *below* `v_i` are computable by anyone. This asymmetry is glossed over.

3. **The garbled circuit evaluation model is underspecified**: The document does not address how the evaluator knows *which* chunk value was signed without learning anything extra. In Lamport, this is trivial — one pre-image is revealed, the other is not. In WOTS, the evaluator receives `H^v(sk_i)` but the circuit must be constructed knowing that `v` is the correct index. The PRF derivation `L_i^{v_i} = PRF(H^{v_i}(sk_i), ...)` works, but the evaluator still needs to identify which gate row to decrypt without knowing `v_i` in advance.

4. **Bitcoin Script feasibility is asserted without verification**: The claim that iterative `OP_SHA256` for `w=16` fits within script limits is plausible but unverified. Bitcoin scripts have a 10,000-byte limit and a 201 non-push opcode limit (pre-Tapscript), and Tapscript removes the 201 limit but retains stack limits. Actual opcode counts per chunk are never computed.

5. **The checksum treatment is superficial**: The WOTS checksum is security-critical and its integration into the garbled circuit input layer is non-trivial — the checksum chunks must be bound to input labels just like message chunks, but their values are *derived* from the message chunks rather than being independent inputs. This creates a dependency that could be exploited.

---

### Feedbacks to the Solutions:

**On Direction A (Chosen Direction):**

The core issue that needs resolution is the **asymmetric leakage in hash chains**. Concretely:

- If the signer reveals `r_i = H^v(sk_i)` for chunk value `v`, any observer can compute `H^1(r_i), H^2(r_i), ..., H^{w-1-v}(r_i)` — these are the chain values for *higher* chunk values. The values for *lower* chunk values (`H^j(sk_i)` for `j < v`) are *not* computable from `r_i` alone.
- This means: an adversary who sees `r_i` can derive the PRF seeds for labels corresponding to chunk values `v+1, v+2, ..., w-1`, but **not** for values `0, 1, ..., v-1`.
- Therefore, PRF domain separation does **not** prevent leakage of higher-value labels. The evaluator (or any observer) can compute labels for all larger chunk values from the revealed chain position.

**Suggested fix**: Reverse the hash chain direction for label derivation, or use a separate committed randomness for label generation that is not derivable from the chain. Concretely: derive labels as `L_i^j = PRF(K_i, j)` where `K_i` is a secret key committed to (but not revealed) on-chain via its hash, and the WOTS reveal is used only to *authenticate* the chunk value, not to *seed* the label. This decouples label security from chain structure but requires an additional commitment. Alternatively, use the *bottom* of the chain (i.e., `sk_i` itself, or a value near it) as the PRF seed, so that revealing `H^v(sk_i)` does not help an adversary compute the seed — this works because hash functions are one-way.

**Revised construction**: Set `L_i^j = PRF(sk_i, j || i)` for all `j`. The evaluator, upon receiving `H^v(sk_i)` from the WOTS signature, **cannot** compute `sk_i` (one-wayness of hash), and thus cannot compute labels for values `j ≠ v`. But this means the evaluator also cannot compute `L_i^v` without knowing `sk_i`. **Resolution**: The garbler precomputes all labels `{L_i^j}` from `sk_i` before the protocol begins and embeds them in the garbled circuit. The evaluator receives `L_i^v` directly as part of the WOTS reveal protocol — i.e., the label itself is transmitted off-chain, authenticated by the on-chain WOTS verification. This is actually the standard garbled circuit OT paradigm, applied here with WOTS as the chooser mechanism.

**On Direction B:**

Multi-valued garbling is more principled but the off-chain overhead for `w=16` at the input boundary is manageable (input layer is typically small compared to the full circuit). A key improvement: use **projective garbling** schemes (e.g., the Free-XOR-compatible scheme from Bellare-Hoang-Rogaway) extended to handle `w`-ary inputs natively. This would make Direction B more competitive and theoretically cleaner.

**On Direction C:**

The XOR problem with Bitcoin Script is real and largely fatal for near-term deployment. However, there is a workaround: use a **lookup-table-based XOR** implemented via Bitcoin Script arithmetic (since Bitcoin Script supports byte-level operations via `OP_SPLIT` and `OP_CAT` in some variants). More practically, if BIP-347 (`OP_CAT`) activates, Direction C becomes immediately feasible and should be the target design. The document should explicitly scope Direction C as a **post-OP_CAT** design and present it as the recommended long-term direction.

**On Direction E:**

The characterization of Direction E as incompatible with BitVM3's non-interactive model is largely correct, but there is a nuance: the OT step can be made **non-interactive** if the prover pre-commits to both labels for each wire and uses a 1-of-2 commitment scheme on-chain (essentially re-inventing Lamport from a different angle). The key insight of Direction E — decoupling the on-chain commitment from the off-chain label distribution — is actually useful in multi-prover settings. This deserves a brief acknowledgment rather than dismissal.

---

**Suggested Lightweight Experimentations:**

**Experiment 1: Bitcoin Script opcode budget analysis for WOTS verification**

Write a concrete Bitcoin Script (or use a script assembler like `btcdeb` or `miniscript`) implementing WOTS chunk verification for `w ∈ {4, 16}`. Measure:
- Exact opcode count per chunk (for the hash chain unrolling)
- Total script size for a 256-bit message with checksum
- Stack depth at peak execution

This is a 1–2 day effort and directly answers Key Question 8. It will either confirm feasibility or reveal the need for Tapscript leaf splitting (which is an important architectural decision).

**Experiment 2: Hash chain label leakage simulation**

Write a small Python script that simulates the WOTS chain for `w=16` and demonstrates explicitly which labels are computable by an evaluator who receives `H^v(sk_i)` for various values of `v`. Specifically:
- For each `v ∈ {0, ..., 15}`, compute all derivable chain values and show which PRF-derived labels become computable
- Plot the leakage pattern as a matrix

This experiment directly validates or refutes the PRF domain separation claim and takes ~2 hours to implement. It will make the security argument concrete and may reveal that the leakage is systematic (all higher-value labels leak), confirming the need for the revised construction suggested above.

**Experiment 3: WOTS checksum overhead calculator**

Implement a parameter sweep (in Python or a spreadsheet) over:
- Message length `n ∈ {128, 256, 512}` bits
- Winternitz parameter `w ∈ {4, 16, 256}`

Computing: number of message chunks, checksum value range, checksum chunk count, total signature length, total public key length, net compression ratio vs. Lamport. This answers Key Question 6 concretely and takes ~1 hour.

**Experiment 4: Garbled circuit input layer size comparison**

Using a standard garbled circuit library (e.g., JustGarble, EMP-toolkit, or a Python prototype), measure the size of the input layer garbled tables for:
- Standard binary Lamport-derived labels (2 rows per wire)
- Direction A: PRF-derived binary labels (same structure, 2 rows per wire)
- Direction B: Native `w`-ary input labels (w rows per wire, for `w ∈ {4, 16}`)

For a representative circuit input size (e.g., 256 input wires), measure total input-layer table size in bytes. This directly quantifies the off-chain overhead difference between Directions A and B.

---

### Feedbacks to the Research Problem:

**1. The problem statement should specify the threat model more precisely.** BitVM3 involves a prover and a verifier (or challenger). The current framing says the signed proof is "input into the garbled circuit as input labels" — but *who evaluates* the garbled circuit, and what does the evaluator learn? In standard BitVM, the verifier evaluates the garbled circuit to check the proof. The security question is: can a malicious prover produce a garbled circuit that *appears* to verify an invalid proof? This threat model should be stated explicitly before discussing signature schemes, because the choice between WOTS and Lamport has different implications depending on whether the adversary is the prover, the verifier, or an external observer.

**2. The problem conflates two distinct functions of the signature**: (a) authenticating the proof value on-chain (so Bitcoin Script can verify it), and (b) providing garbled circuit input labels (so the evaluator can evaluate the circuit). These two functions have *different* security requirements and it is worth separating them. The signature's role in (a) requires unforgeability; its role in (b) requires that the revealed value uniquely and unpredictably selects the correct label. The problem statement should separate these requirements to allow solutions that might use *different* primitives for each.

**3. The problem should specify the proof system being used.** "Signed proof" is ambiguous — is this a STARK proof hash, a Groth16 proof, a Bulletproofs transcript? The size of the signed message determines the magnitude of the efficiency gain from WOTS vs. Lamport, and the structure of the proof may suggest natural chunk boundaries (e.g., field elements) that align well with WOTS parameters. A concrete instantiation (e.g., "a 256-bit Fiat-Shamir challenge hash from a FRI-based STARK") would make the problem sharper.

**4. The problem should address the one-time key management challenge at the protocol level.** Both WOTS and Lamport are one-time signatures. The problem statement mentions this but treats it as a property rather than a challenge. In practice, ensuring one-time use in a Bitcoin protocol requires an on-chain enforcement mechanism (e.g., the public key is a Taproot output that can only be spent once, or is committed in a time-locked contract). This protocol-level concern should be part of the problem definition, not just an afterthought.

**5. Consider refining the problem to also include WOTS+ and XMSS variants as explicit options.** The current framing treats WOTS as monolithic, but WOTS+, XMSS (which chains WOTS+ instances for multi-time use), and SPHINCS+ (stateless) have meaningfully different properties. If the goal is to build a *production-ready* BitVM3 system, SPHINCS+ signatures (which are stateless and avoid the one-time key problem) might be worth considering, even at the cost of larger signatures. Framing the problem as "replace Lamport with a more efficient hash-based signature scheme" (rather than specifically WOTS) would open this design space.

**6. The research problem would benefit from a formal security definition.** What does it mean for the redesigned system to be "secure"? A natural definition would be: *no PPT adversary can cause the garbled circuit to accept an invalid proof with non-negligible probability, given only the public on-chain data and the output of the garbled circuit evaluation.* Formalizing this as a game-based or UC-based definition would make the problem more rigorous and would clarify what the proof obligations are for any candidate solution.
