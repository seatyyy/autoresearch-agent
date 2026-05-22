# 01_2 — Eval Design

**Problem:** In BitVM3, garbled circuits are used to do off-chain proof verification based on a signed proof put on the Bitcoin chain. The signed proof is input into the garbled circuit as input labels. In most existing designs, the signature scheme is a Lamport signature, which is verifiable by Bitcoin. Can you provide a re-design using Winternitz signatures instead of Lamport signatures?

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
