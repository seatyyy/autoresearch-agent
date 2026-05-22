# 01_1 — Analysis

**Problem:** In BitVM3, garbled circuits are used to do off-chain proof verification based on a signed proof put on the Bitcoin chain. The signed proof is input into the garbled circuit as input labels. In most existing designs, the signature scheme is a Lamport signature, which is verifiable by Bitcoin. Can you provide a re-design using Winternitz signatures instead of Lamport signatures?

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
