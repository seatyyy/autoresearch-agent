# 01_2 — Eval Design

**Problem:** In BitVM3, garbled circuits are used to do off-chain proof verification based on a signed proof put on the Bitcoin chain. The signed proof is input into the garbled circuit as input labels. In most existing designs, the signature scheme is a Lamport signature, which is verifiable by Bitcoin. Can you provide a re-design using Winternitz signatures instead of Lamport signatures?

**Eval Design:** #### Eval metrics

1. **On-chain script size (bytes)**: The size of the Bitcoin locking/unlocking scripts required to verify the Winternitz signature on-chain, directly impacting transaction fees and feasibility within Bitcoin's script constraints.

2. **On-chain transaction cost (vbytes / fees)**: The total on-chain footprint across all transactions in the protocol (commitment, challenge, response), measured in virtual bytes and fee expenditure, compared against the Lamport baseline.

3. **Signature/witness data size (on-chain)**: The size of the Winternitz signature itself when posted on-chain as a witness, since Winternitz produces shorter signatures than Lamport at the cost of more computation — quantifying this compression ratio is critical.

4. **Garbled circuit input label encoding overhead (off-chain)**: How the switch from Lamport to Winternitz affects the mapping between signature outputs and garbled circuit input wire labels, including any additional encoding or hashing steps required off-chain.

5. **Computational overhead (prover and verifier)**: The number of hash evaluations required by both the prover (signing) and the Bitcoin script verifier (on-chain verification), given that Winternitz involves chained hashing of depth *w*, affecting latency and resource usage.

6. **Security level and parameter soundness**: Whether the chosen Winternitz parameter *w* and hash function achieve the target security level (e.g., 128-bit), including resistance to one-time signature forgery and checksum manipulation attacks.

7. **Bitcoin script compatibility and feasibility**: Whether the Winternitz verification logic (hash chains, checksum computation) can be faithfully implemented within Bitcoin's constrained Script opcodes (no loops, limited stack), and whether any workarounds fragment correctness guarantees.

8. **Reduction in public key / commitment size**: Winternitz public keys are smaller than Lamport's; this metric measures the reduction in the number of on-chain committed values and its downstream effect on UTXO/output size.

9. **Protocol security under composition**: Whether replacing Lamport with Winternitz preserves the overall BitVM3 security properties — in particular, soundness of the bisection/challenge-response game and binding of the signed proof to the garbled circuit input labels.

10. **Novelty and design elegance**: The degree to which the redesign introduces non-trivial insights (e.g., novel checksum handling in Script, new label-binding techniques), beyond a straightforward substitution, assessed relative to existing BitVM and one-time signature literature.

#### Eval metrics

1. **On-chain script size (bytes)**: The size of the Bitcoin locking/unlocking scripts required to verify the Winternitz signature on-chain, directly impacting transaction fees and feasibility within Bitcoin's script constraints.

2. **On-chain transaction cost (vbytes / fees)**: The total on-chain footprint across all transactions in the protocol (commitment, challenge, response), measured in virtual bytes and fee expenditure, compared against the Lamport baseline.

3. **Signature/witness data size (on-chain)**: The size of the Winternitz signature itself when posted on-chain as a witness, since Winternitz produces shorter signatures than Lamport at the cost of more computation — quantifying this compression ratio is critical.

4. **Garbled circuit input label encoding overhead (off-chain)**: How the switch from Lamport to Winternitz affects the mapping between signature outputs and garbled circuit input wire labels, including any additional encoding or hashing steps required off-chain.

5. **Computational overhead (prover and verifier)**: The number of hash evaluations required by both the prover (signing) and the Bitcoin script verifier (on-chain verification), given that Winternitz involves chained hashing of depth *w*, affecting latency and resource usage.

6. **Security level and parameter soundness**: Whether the chosen Winternitz parameter *w* and hash function achieve the target security level (e.g., 128-bit), including resistance to one-time signature forgery and checksum manipulation attacks.

7. **Bitcoin script compatibility and feasibility**: Whether the Winternitz verification logic (hash chains, checksum computation) can be faithfully implemented within Bitcoin's constrained Script opcodes (no loops, limited stack), and whether any workarounds fragment correctness guarantees.

8. **Reduction in public key / commitment size**: Winternitz public keys are smaller than Lamport's; this metric measures the reduction in the number of on-chain committed values and its downstream effect on UTXO/output size.

9. **Protocol security under composition**: Whether replacing Lamport with Winternitz preserves the overall BitVM3 security properties — in particular, soundness of the bisection/challenge-response game and binding of the signed proof to the garbled circuit input labels.

10. **Novelty and design elegance**: The degree to which the redesign introduces non-trivial insights (e.g., novel checksum handling in Script, new label-binding techniques), beyond a straightforward substitution, assessed relative to existing BitVM and one-time signature literature.
