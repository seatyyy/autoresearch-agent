# 01_1 — Analysis

**Problem:** In BitVM3, garbled circuits are used to do off-chain proof verification based on a signed proof put on the Bitcoin chain. The signed proof is input into the garbled circuit as input labels. In most existing designs, the signature scheme is a Lamport signature, which is verifiable by Bitcoin. Can you provide a re-design using Winternitz signatures instead of Lamport signatures?

**Analysis:** #### High level understanding

## BitVM3 with Winternitz Signatures: A High-Level Analysis

### Background Context

**BitVM3** is an evolution of the BitVM paradigm that enables expressive off-chain computation with on-chain dispute resolution on Bitcoin. The core innovation is using **garbled circuits** for off-chain proof verification, where:

1. A prover commits to a proof on-chain (via Bitcoin transaction)
2. The proof is encoded as **input labels** fed into a garbled circuit
3. The garbled circuit evaluates the proof verification logic off-chain
4. Bitcoin script verifies the signature binding the proof to the input labels

The choice of signature scheme is critical because it must be **natively verifiable in Bitcoin Script** (which has no built-in ECDSA/Schnorr for arbitrary messages — only for transaction signing).

---

### Why Lamport Signatures are Used Today

**Lamport signatures** are the default because:
- They are **hash-based** (Bitcoin Script supports SHA256, RIPEMD160)
- Each bit of the message is signed by revealing one of two pre-images
- Verification in Bitcoin Script is straightforward: `OP_HASH160 OP_EQUALVERIFY`
- However, they are **extremely inefficient**: signing an n-bit message requires **2n secret values** and **2n public key hashes**
- For a 256-bit hash output, you need 512 hash values just for one signature

---

### Winternitz Signatures: The Core Idea

**Winternitz One-Time Signatures (WOTS)** generalize Lamport by signing **w bits at a time** (where w is the Winternitz parameter), using hash chains instead of single hash pre-images:

- Message is divided into blocks of **log₂(w)** bits
- Each block is signed by a hash chain of length up to **w**
- A checksum is appended to prevent forgery
- **Key compression ratio**: ~**log₂(w)× reduction** in signature size vs. Lamport (w=2 reduces to Lamport)
- For w=16: signs 4 bits per chain element → ~4× fewer elements than Lamport

**Formal structure:**
- Private key: random values `x_i`
- Public key: `pk_i = H^w(x_i)` (w-fold hash)
- Signature on message block `m_i ∈ [0, w-1]`: `σ_i = H^(m_i)(x_i)`
- Verification: `H^(w - m_i)(σ_i) == pk_i`

---

### Redesign: BitVM3 with Winternitz Signatures

#### 1. Encoding the Proof as Winternitz Input Labels

In the Lamport-based design, each **bit** of the signed proof maps to one input label (either the 0-label or 1-label of the garbled circuit). With Winternitz:

- Group the proof bits into **w-bit blocks** (e.g., w=16 → 4-bit blocks)
- Each block value `m_i` selects the corresponding position in a hash chain as the garbled circuit **input label**
- The input label for block i at value m_i is: `L_i = H^(m_i)(x_i)`
- The garbled circuit evaluator receives `L_i` and can verify it against `pk_i` by checking `H^(w - m_i)(L_i) == pk_i`

This means the **number of garbled circuit input wires** is reduced by a factor of **log₂(w)** compared to Lamport.

#### 2. Bitcoin Script Verification

Bitcoin Script must verify the Winternitz signature on-chain (in the dispute/challenge path):

```
For each block i:
  Stack: [σ_i, m_i, pk_i]
  Apply H^(w - m_i)(σ_i) using a loop-unrolled hash chain
  Check equality with pk_i
  Verify checksum blocks
```

**Key challenge**: Bitcoin Script has no loops, so the hash chain must be **unrolled**. For w=16, worst case 15 hash operations per element — this is manageable. Scripts using `OP_SHA256` repeated up to w-1 times per block are feasible within Bitcoin Script's constraints.

The checksum mechanism (sum of `w - m_i` values) must also be Script-verified to prevent the adversary from manipulating message blocks downward.

#### 3. Connecting to Garbled Circuit Input Labels

The critical binding is:

> **The Winternitz signature revelation IS the garbled circuit input label delivery.**

Specifically:
- During garbled circuit construction, the **input label for wire i at value v** is defined as `H^v(x_i)`
- The Winternitz signature on proof block i with value `m_i` naturally reveals `H^(m_i)(x_i)` — exactly the correct input label
- The evaluator uses this label directly to evaluate the garbled circuit
- No separate label-to-signature binding is needed — the signature **is** the label

This is an elegant unification: **signing the proof and delivering garbled circuit input labels are the same operation**.

#### 4. Security Considerations

| Property | Lamport | Winternitz (w=16) |
|---|---|---|
| Signature size (256-bit msg) | 512 hashes | ~72 hashes (64 msg + 8 checksum) |
| Bitcoin Script size | Large | ~4× smaller |
| Security assumption | Hash preimage | Hash chain one-wayness |
| Forgery resistance | Perfect per bit | Requires checksum integrity |
| One-time property | Yes | Yes |

**Critical security note**: Winternitz requires careful checksum handling. If an adversary can choose `m_i` after seeing partial signatures, they can forge by extending hash chains downward. The checksum blocks prevent this — they must also be Script-verified.

#### 5. Parameter Selection Tradeoffs

- **w=2**: Equivalent to Lamport — baseline
- **w=16**: Good balance — 4× compression, manageable Script unrolling (15 ops/element)
- **w=256**: Maximum compression but 255 hash ops per element in Script — likely hits Script size limits
- **Recommended**: **w=16 or w=32** for practical BitVM3 deployment

#### 6. Impact on BitVM3 Protocol

- **Reduced on-chain footprint**: Fewer public key hashes committed on-chain (in the setup transaction)
- **Smaller challenge transactions**: The dispute script that verifies the signature is shorter
- **Faster off-chain evaluation**: Fewer input labels means smaller garbled circuits
- **Compatible with existing Bitcoin opcodes**: No consensus changes required — pure `OP_SHA256`/`OP_HASH160` based

---

### Summary

Replacing Lamport with Winternitz in BitVM3 is both **feasible and advantageous**. The key insight is that Winternitz hash chains naturally serve as garbled circuit input label selectors, unifying signature verification and label delivery. The compression factor of log₂(w) directly reduces on-chain data, Bitcoin Script size, and garbled circuit complexity. The main engineering challenge is careful Bitcoin Script construction for unrolled hash chain verification with correct checksum handling, but this is entirely achievable within Bitcoin's existing opcode set.

#### High level understanding

## BitVM3 with Winternitz Signatures: A High-Level Analysis

### Background Context

**BitVM3** is an evolution of the BitVM paradigm that enables expressive off-chain computation with on-chain dispute resolution on Bitcoin. The core innovation is using **garbled circuits** for off-chain proof verification, where:

1. A prover commits to a proof on-chain (via Bitcoin transaction)
2. The proof is encoded as **input labels** fed into a garbled circuit
3. The garbled circuit evaluates the proof verification logic off-chain
4. Bitcoin script verifies the signature binding the proof to the input labels

The choice of signature scheme is critical because it must be **natively verifiable in Bitcoin Script** (which has no built-in ECDSA/Schnorr for arbitrary messages — only for transaction signing).

---

### Why Lamport Signatures are Used Today

**Lamport signatures** are the default because:
- They are **hash-based** (Bitcoin Script supports SHA256, RIPEMD160)
- Each bit of the message is signed by revealing one of two pre-images
- Verification in Bitcoin Script is straightforward: `OP_HASH160 OP_EQUALVERIFY`
- However, they are **extremely inefficient**: signing an n-bit message requires **2n secret values** and **2n public key hashes**
- For a 256-bit hash output, you need 512 hash values just for one signature

---

### Winternitz Signatures: The Core Idea

**Winternitz One-Time Signatures (WOTS)** generalize Lamport by signing **w bits at a time** (where w is the Winternitz parameter), using hash chains instead of single hash pre-images:

- Message is divided into blocks of **log₂(w)** bits
- Each block is signed by a hash chain of length up to **w**
- A checksum is appended to prevent forgery
- **Key compression ratio**: ~**log₂(w)× reduction** in signature size vs. Lamport (w=2 reduces to Lamport)
- For w=16: signs 4 bits per chain element → ~4× fewer elements than Lamport

**Formal structure:**
- Private key: random values `x_i`
- Public key: `pk_i = H^w(x_i)` (w-fold hash)
- Signature on message block `m_i ∈ [0, w-1]`: `σ_i = H^(m_i)(x_i)`
- Verification: `H^(w - m_i)(σ_i) == pk_i`

---

### Redesign: BitVM3 with Winternitz Signatures

#### 1. Encoding the Proof as Winternitz Input Labels

In the Lamport-based design, each **bit** of the signed proof maps to one input label (either the 0-label or 1-label of the garbled circuit). With Winternitz:

- Group the proof bits into **w-bit blocks** (e.g., w=16 → 4-bit blocks)
- Each block value `m_i` selects the corresponding position in a hash chain as the garbled circuit **input label**
- The input label for block i at value m_i is: `L_i = H^(m_i)(x_i)`
- The garbled circuit evaluator receives `L_i` and can verify it against `pk_i` by checking `H^(w - m_i)(L_i) == pk_i`

This means the **number of garbled circuit input wires** is reduced by a factor of **log₂(w)** compared to Lamport.

#### 2. Bitcoin Script Verification

Bitcoin Script must verify the Winternitz signature on-chain (in the dispute/challenge path):

```
For each block i:
  Stack: [σ_i, m_i, pk_i]
  Apply H^(w - m_i)(σ_i) using a loop-unrolled hash chain
  Check equality with pk_i
  Verify checksum blocks
```

**Key challenge**: Bitcoin Script has no loops, so the hash chain must be **unrolled**. For w=16, worst case 15 hash operations per element — this is manageable. Scripts using `OP_SHA256` repeated up to w-1 times per block are feasible within Bitcoin Script's constraints.

The checksum mechanism (sum of `w - m_i` values) must also be Script-verified to prevent the adversary from manipulating message blocks downward.

#### 3. Connecting to Garbled Circuit Input Labels

The critical binding is:

> **The Winternitz signature revelation IS the garbled circuit input label delivery.**

Specifically:
- During garbled circuit construction, the **input label for wire i at value v** is defined as `H^v(x_i)`
- The Winternitz signature on proof block i with value `m_i` naturally reveals `H^(m_i)(x_i)` — exactly the correct input label
- The evaluator uses this label directly to evaluate the garbled circuit
- No separate label-to-signature binding is needed — the signature **is** the label

This is an elegant unification: **signing the proof and delivering garbled circuit input labels are the same operation**.

#### 4. Security Considerations

| Property | Lamport | Winternitz (w=16) |
|---|---|---|
| Signature size (256-bit msg) | 512 hashes | ~72 hashes (64 msg + 8 checksum) |
| Bitcoin Script size | Large | ~4× smaller |
| Security assumption | Hash preimage | Hash chain one-wayness |
| Forgery resistance | Perfect per bit | Requires checksum integrity |
| One-time property | Yes | Yes |

**Critical security note**: Winternitz requires careful checksum handling. If an adversary can choose `m_i` after seeing partial signatures, they can forge by extending hash chains downward. The checksum blocks prevent this — they must also be Script-verified.

#### 5. Parameter Selection Tradeoffs

- **w=2**: Equivalent to Lamport — baseline
- **w=16**: Good balance — 4× compression, manageable Script unrolling (15 ops/element)
- **w=256**: Maximum compression but 255 hash ops per element in Script — likely hits Script size limits
- **Recommended**: **w=16 or w=32** for practical BitVM3 deployment

#### 6. Impact on BitVM3 Protocol

- **Reduced on-chain footprint**: Fewer public key hashes committed on-chain (in the setup transaction)
- **Smaller challenge transactions**: The dispute script that verifies the signature is shorter
- **Faster off-chain evaluation**: Fewer input labels means smaller garbled circuits
- **Compatible with existing Bitcoin opcodes**: No consensus changes required — pure `OP_SHA256`/`OP_HASH160` based

---

### Summary

Replacing Lamport with Winternitz in BitVM3 is both **feasible and advantageous**. The key insight is that Winternitz hash chains naturally serve as garbled circuit input label selectors, unifying signature verification and label delivery. The compression factor of log₂(w) directly reduces on-chain data, Bitcoin Script size, and garbled circuit complexity. The main engineering challenge is careful Bitcoin Script construction for unrolled hash chain verification with correct checksum handling, but this is entirely achievable within Bitcoin's existing opcode set.
