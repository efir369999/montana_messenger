# The Fabric of Time

## A local, private, signed measure of regular human exchange, and what it bounds against Sybil identities

**Montana Council whitepaper.** Audience: cryptographers and reviewers of the Metzdowd list. Language of the formulas: unsigned integers only, as the protocol's determinism invariant requires; every number in this paper is computed, and the computations stand in Appendix B.

**Provenance.** This paper describes the mechanism as the Montana set holds it, and nothing the set does not hold. The normative text is the protocol specification on the branch `spec/fabric-v2-88` of the Montana-Protocol repository at commit `7194655` (documents `docs/Montana App.md`, `docs/Montana Canon.md`, `docs/Montana Identity.md`), with its reference derivations in `Montana-Core/crates/mt-derive/src/levels.rs`; the earlier form stands at commit `fcd2f57` (`spec/fabric-of-time-87`). The client text is the iOS messenger at commit `93fd8386` of the branch `rollback-898` (`Code/Montana/MTWalletCore.swift`, `MTCallRecording.swift`, `MontanaCall.swift`, `MontanaE2E.swift`, `MontanaSettings.swift`). Citations below name file and line of those revisions. Where the specification, the client and the council's records disagree, Section 11 says so and decides nothing. A second reading of the same sources by the council's researcher (dossier of 22.10.2026, `~/.montana/council/fabric/research.md`) was compared with this text before it was closed and agreed with it on every citation.

---

## Abstract

A Montana person carries a **level**, an unsigned integer, defined as the minimum of three terms: the level of the chain of the person (whole doublings of the seconds the seed was present on the network), the level of the wallet (how many decimal prefixes of π the balance reaches, at most nineteen) and the level of the **fabric of time**. The fabric is an H-index over the people the person exchanges with regularly: a correspondent is *regular* when the person holds a testimony signed by that correspondent for a two-way exchange in each of the two seven-day halves of the last τ₂ = 20 160 windows, and the correspondent's *value* is the lowest ceiling (minimum of their own person level and wallet level) the correspondent stated in those testimonies. The level of the fabric is the greatest g such that at least g regular correspondents have value at least g.

We give the fabric a formal model and prove what it bounds. (i) **Ceiling bound.** No seed stands above min(bitlen(age in seconds) − 1, wallet level); hence an adversary who controls any number of seeds born after time T₀ with total balance B holds no seed at level ≥ k before 2^k seconds have elapsed, and at most ⌊B / π_k⌋ of them afterwards, where π_k is the k-digit prefix of π. (ii) **Locality and monotonicity.** The fabric of a person is a function of the testimonies that person holds; a third party who gave no testimony changes nothing, and a Sybil population cannot lower an honest person at all. (iii) **Descent.** Starting from any upper bound u and descending, the first g with at least g values ≥ g is min(u, H); the author's rule "count from the ceiling down" and the one-pass H of the specification coincide, and the count is order-independent and terminates in at most u + 1 steps. (iv) **Attack edges.** An honest person's fabric exceeds their honest circle by at most the number of Sybil keys that person answered in both halves, each such edge costing the honest side two live acts per τ₂ (or, when the act is a call, 60 seconds of received voice in each half, measured by the honest device). (v) **Splitting.** Dividing one balance across several seeds raises no part above the ceiling of the undivided seed, and, while the parts do not testify to one another, above its level either; parts that testify to one another are the self-certifying cluster of (iv) and pay its price in coins held at once. The count of parts at level ≥ k obeys the ceiling bound.

We state plainly what the mechanism does not close: a cluster of adversarial seeds certifies its own fabric at the price of its ceilings alone, since the stated ceiling inside a testimony is verifiable by nobody by design; the protocol consumes the level in no plane; today's client consumers of another person's level read a self-statement; and the proof of the fabric by opening, and its zero-knowledge successor, are a next stage. The fabric is a one-hop, privacy-preserving degree-with-threshold measure, and we compare it as such with the random-walk Sybil defences, with k-core decomposition and with proof-of-personhood schemes.

---

## 1. Scope and claims

This paper answers two questions and refrains from a third.

1. *What does the fabric of time measure, exactly?* Section 3 defines every object in the integers the protocol uses, with the frozen vectors the specification and the client share.
2. *What does the level, with the fabric as its third term, bound against an adversary who manufactures identities?* Sections 4 and 5 give the threat model and the theorems.
3. *What should the mechanism be?* Not here. Section 11 lists the points at which the council's records, the specification and the client disagree, and the one design question the council left open, as questions for the author.

Two invariants of the role frame the exposition. The level is read in integers and never in floating point (the bit-exact determinism invariant of the specification, [I-9]); and every claim about the set is made from the set, with the file and the line it stands on. Claims about external schemes are made from their publications (Section 10, bibliography in Section 12).

---

## 2. The objects of the set

### 2.1 Windows and the period of adaptation

The network's time is counted in **windows**. The constants the fabric uses are those of the Genesis Decree (`docs/Montana Canon.md:4637-4645` at `7194655`):

```
τ₂               = 20 160 windows        the period of adaptation
τ₂ / 2           = 10 080 windows        the half of the fabric
segment_windows  = τ₂ / 14 = 1 440       one segment
```

The specification derives the pace of a window from the geography of the living machines and measures nothing (`Canon.md:4775-4778`); the client, which holds no window of the core, reads the nodes' seconds and divides by sixty (`MTWalletCore.swift:2228-2231`, marked there as a deviation). Under that reading one window is 60 s, τ₂ is 1 209 600 s = 14 days, a half is 7 days and a segment is 1 day. Every duration in this paper is stated in windows first and in days under the client's reading second.

### 2.2 The three chains and the level of a person

The specification states three chains of time a client shows (`docs/Montana App.md:101-138`):

- **The chain of the person** counts the seconds in which the seed was present on the network, a second counting once however many devices held the seed, and only when a machine of the network answered an exchange within it (`App.md:108-113`). Its level is the number of whole doublings of the count (`Canon.md:2721-2730`):

  ```
  level(s) = bit_length(s) − 1        s ≥ 1; a chain with no link enters as zero
  ```

- **The chain of the wallet** has as level the count of prefixes of π the balance reaches (`Canon.md:2732-2742`):

  ```
  wallet_level(b) = count of k in 1 ..= 19 with pi_prefix(k) ≤ b
  pi_prefix(k)    = the integer the first k decimal digits of π write: 3, 31, 314, …, 3141592653589793238
  ```

  Nineteen digits are the most an unsigned 64-bit integer holds, so the level runs from 0 to 19.

- **The fabric of time**, defined in Section 3.

**The level of a person** is the minimum of the three (`Canon.md:2786-2796`):

```
level_of_person(p, w, f) = min(p, w, f)
```

"The level is the person's own reading" (`App.md:140-145`): a client computes and shows it on the person's devices and publishes none of the three; "No plane of the protocol consumes the level and it confers no right in any of them".

### 2.3 The testimony of an exchange

An exchange enters the fabric through one object, the **testimony of an exchange** (`Canon.md:5225-5256`), which the correspondent's device signs and gives to the person:

```
serialize(exchange_testimony)
  suite_id        2 B   u16   the row of the suite the signer's key stands under (row 1: ML-DSA-65)
  addressee      32 B         the hash the fingerprint of the addressee's key is read from
  window          8 B   u64   the window the signer's device received the addressee's live act in
  ceiling         1 B   u8    the signer's ceiling at that window
  signature    3309 B         over everything above

testimony_len = 3 352 B
testimony_id  = SHA-256("mt-exchange-testimony" ‖ 0x00 ‖ signed_scope)
```

The suite table names row 1 as ML-DSA-65 with a 3 309-byte signature (`Canon.md:157`), used in its deterministic variant (`Canon.md:146`). The invariants of a testimony (`Canon.md:5248-5256`) fix what a holder refuses: a testimony naming anyone but the holder's own fingerprint hash; a window more than one window past the holder's own reading; a ceiling above nineteen; a second testimony from one key in one segment, of which the holder keeps the one stating the lower ceiling. The identifier is taken over the signed scope, so re-signing moves nothing.

### 2.4 When a testimony is given, and what a live act is

A **live act** is "anything one person sends another that stands in their conversation: words, voice and video messages, photographs, files and media, stickers and animations, transfers of coins, the moves of a game, and a call that wove"; receipts, typing signs, presence signs and the fabric's own words are not live acts (`App.md:156-160`). A call weaves when each side received the other's voice for at least `call_seconds` = 60 (`Canon.md:2755-2760`), each side counting what its own device received, "so neither side's minute can be lent by the other" (`Canon.md:2766`).

A device gives a testimony "when it receives a live act from a correspondent while it has itself sent that correspondent a live act within the last half of τ₂, so that the exchange runs both ways, and it gives at most one to each correspondent in a segment" (`App.md:162-165`). "A person who only writes and is never answered is given none."

### 2.5 What reaches the network

Once in every half of τ₂ a client witnesses, in one action of the identity plane, the testimonies it received since the last witnessing; each enters the person's fabric "as a blinded leaf over the testimony's identifier and its window" under a single root inside the record's successor commitment (`App.md:195-202`; `docs/Montana Identity.md:185-213`; leaf and node domains `Canon.md:510-518`). "The level of the fabric is proven by opening: a person shows the testimonies of a window to whom they choose, and the root admits no testimony that was not held when it was witnessed" (`App.md:200-202`). No testimony, count or correspondent is published (`App.md:242-245`).

---

## 3. Formal definition

Let ℕ denote the unsigned integers. All quantities below are elements of ℕ or finite sets; no formula divides except by integer division, written `div`, and no subtraction goes below zero (`sat_sub(a, b) = a − b` if `b ≤ a`, else 0).

**Seeds and keys.** A seed is a 24-word identity. For a correspondence between seeds r and s the client derives a signing key from the seed and the correspondence's own hash (`MTWalletCore.swift:2410-2427`); the specification binds the testimony to "the key the two of them compare out of band" (`Canon.md:5228`). Throughout, K(s → r) denotes the key under which r verifies testimonies from s, and "distinct correspondents" means distinct such keys ("Correspondents are told apart by the keys their testimonies verify under, and by nothing they state about themselves", `App.md:170-171`).

**Definition 3.1 (presence, balance, ceiling).** For a seed s at window w let P(s, w) ∈ ℕ be the seconds counted by its chain of the person and B(s, w) ∈ ℕ its balance in coins. Define

```
p(s, w) = bit_length(P(s, w)) − 1     if P(s, w) ≥ 1, else 0
ω(s, w) = count of k in 1 ..= 19 with π_k ≤ B(s, w)
c(s, w) = min(p(s, w), ω(s, w))                          the ceiling
```

Since π_1 < π_2 < … < π_19, ω(s, w) = max{k : π_k ≤ B} (0 when B < 3). The ceiling is "the lower of the levels of their chain of the person and of their wallet" (`App.md:173-174`) and is bounded by 19.

**Definition 3.2 (half and segment).** For the window now w and the window t of a testimony,

```
half(w, t)    = sat_sub(w, t) div 10 080
segment(t)    = t div 1 440
```

(`Canon.md:2776`; `levels.rs`, `half`; `MTWalletCore.swift:2215-2216`). A testimony with half 0 stands in the newer seven days, with half 1 in the older seven days, and with half ≥ 2 has left the window.

**Definition 3.3 (held testimonies).** T_r(w) is the set of testimonies r holds at w: those that passed the refusals of `Canon.md:5250-5256` and have half(w, t) ≤ 1, with at most one per (signer key, segment), the lower ceiling kept. Each T ∈ T_r(w) has a signer key K(T), a window t(T) and a stated ceiling γ(T) ≤ 19.

**Definition 3.4 (regular correspondents and values).** 

```
Reg_r(w) = { K : ∃ T, T' ∈ T_r(w), K(T) = K(T') = K, half(w, t(T)) = 0, half(w, t(T')) = 1 }
v_r(K, w) = min { γ(T) : T ∈ T_r(w), K(T) = K }
```

(`App.md:167-175`). The value is the lowest ceiling the correspondent stated within the last τ₂, so "a carousel of coins" — borrowing a balance for the moment of one statement — raises nothing for fourteen days.

**Definition 3.5 (the function H).** For a finite multiset V of unsigned integers,

```
H(V) = max { g ∈ ℕ : count of v in V with g ≤ v  is ≥ g }        H(∅) = 0
```

(`Canon.md:2746-2753`). Frozen vectors: H() = 0, H(5) = 1, H(3, 3, 3) = 3, H(9, 1, 7, 2, 6) = 3, H(2, 2, 2, 2, 2, 2) = 2 (`Canon.md:3438-3449`), each named by the wrong reading it refuses. The reference computation sorts descending and counts while the i-th value exceeds i − 1 (`levels.rs`, `fabric_level`; `MTWalletCore.swift:2205-2212`).

**Definition 3.6 (the level of the fabric and the level of a person).** Let o(r) be the window the fabric of r opened in. Then

```
f(r, w) = c(r, w)                                    if w < o(r) + τ₂
        = H( { v_r(K, w) : K ∈ Reg_r(w) } )          otherwise
L(r, w) = min( p(r, w), ω(r, w), f(r, w) )
```

(`App.md:177-181`; `Canon.md:2789`; `MTWalletCore.swift:2440-2443`, `1980-1982`). Through the first τ₂ the fabric "lowers a person from where their own time places them, and it starts there".

**Remark 3.7 (what is verifiable by whom).** Of the terms of L(r, w): the balance is public in the financial layer (invariant [I-2]); the seconds of presence are counted on the person's devices from the network's answers and, as *lived time*, proven inside the identity plane's commitments without being published (`App.md:143-145`, `Identity.md:215-225`); the testimonies are verifiable by their holder (signature, addressee, window) and, after witnessing, provable by opening against the root. The ceiling *stated* inside a testimony is verifiable by nobody: the signing key of a correspondence names no account and no balance, by the privacy invariant the client records as [I-17] (`MTWalletCore.swift:2349-2354`). Theorems below say for each bound which of these it rests on.

---

## 4. Threat model

**Adversary.** An adversary 𝒜 controls a set S of seeds, |S| = N, each a complete identity with its own devices, keys, presence and balance. 𝒜 may run a modified client on every seed it controls: it may sign any testimony it likes, state any ceiling up to nineteen, skip the two-way condition, and report any level to itself. 𝒜 may buy or receive coins; coins held by one seed are not held by another at the same time ("one balance is not held by two seeds at once", `App.md:216-217`). 𝒜 cannot forge ML-DSA-65 signatures under keys it does not hold, cannot find SHA-256 collisions, and cannot make the network answer a seed in a second in which no device of that seed exchanged with a machine of the network (`App.md:108-113`).

**Resources.** Three quantities bound 𝒜:

- **Time.** T, the seconds elapsed since the youngest seed 𝒜 needs was born. Seeds age in parallel, but none ages faster than wall-clock.
- **Balance.** B_𝒜, the total coins 𝒜 holds at the window under consideration.
- **Attack edges.** A, the set of pairs (h, s) with h an honest seed and s ∈ S such that h gave s a testimony in each half of the last τ₂ — equivalently, h answered a live act of s with a live act of its own, twice, seven days apart or more. Each such pair is an *attack edge*, in the sense of the social-network Sybil defences [YKGF06, YGKX08]: a relationship the adversary obtained from a real person.

**Honest persons.** An honest seed runs the specification's client: it gives a testimony only on a live act received after one it sent within the last half of τ₂, states its true ceiling, keeps and refuses testimonies as the invariants require, and never shares its seed. Honest persons may be careless: they may answer a stranger. The model charges that as an attack edge and nothing else.

**Goals of 𝒜.** (G1) To hold many seeds whose *verified* level is at least k, for a target k. (G2) To raise or lower the level of an honest person. (G3) To learn with whom an honest person exchanges. (G4) To obtain the standing of one real person several times by splitting.

**What "verified level" means.** L*(s, w) is L(s, w) computed by a verifier from evidence the verifier can check: the public balance of s, the lived time the identity plane proves for s, and the testimonies s holds, each with its signature, addressee and window checked, counted by distinct signer keys, with stated ceilings taken as stated. L* is what Section 5 bounds. The level a modified client shows to its own owner, or says in a presence word, is a self-statement and is bounded by nothing (Section 9).

---

## 5. Theorems

Throughout, w is fixed and omitted when no confusion arises.

### Theorem 1 (ceiling bound; Sybils at level k through time and balance)

*(a) For every seed s, L*(s) ≤ c(s) = min(bit_length(P(s)) − 1, ω(s)).*

*(b) L*(s) ≥ k implies P(s) ≥ 2^k and B(s) ≥ π_k.*

*(c) Let S be the adversary's seeds, all born at or after time T₀, with total balance B_𝒜 at window w. Then*

```
|{ s ∈ S : L*(s) ≥ k }| = 0                      while  now − T₀ < 2^k seconds
|{ s ∈ S : L*(s) ≥ k }| ≤ min( N, B_𝒜 div π_k )  always
```

**Proof.** (a) L* is a minimum of three terms two of which are p(s) and ω(s). (b) p(s) ≥ k means bit_length(P) ≥ k + 1, so P ≥ 2^k; ω(s) ≥ k means at least k prefixes are ≤ B, and since the prefixes increase, π_k ≤ B. (c) The chain of the person counts seconds of presence and a seed present in a second is a seed that exists in it, so P(s) ≤ now − T₀ < 2^k, and by (b) no seed reaches k. For the second line, let S_k be the seeds with L* ≥ k. By (b) each holds at least π_k coins; balances are disjoint, so |S_k| · π_k ≤ Σ_{s ∈ S_k} B(s) ≤ B_𝒜, and |S_k| ≤ B_𝒜 div π_k. |S_k| ≤ N is immediate. ∎

**What it rests on.** The public balance ([I-2]) and the proven lived time of the identity plane; nothing stated by anyone. It holds whatever 𝒜 does with testimonies.

**Corollary 1.1 (the time wall and the coin wall, computed).** Level k is unreachable before 2^k seconds of age and below π_k coins:

```
k    2^k seconds        as time            π_k coins
 7          128         2 min 8 s          3 141 592
 8          256         4 min 16 s         31 415 926
10        1 024         17 min 4 s         3 141 592 653
13        8 192         2 h 16 min 32 s    3 141 592 653 589
19      524 288         6 d 1 h 38 min     3 141 592 653 589 793 238
20    1 048 576         12 d 3 h 16 min    none (the wallet stops at 19)
```

At the two levels the client opens functions at (7 and 8, Section 7) the time wall is minutes and the coin wall is the binding term. The Constitution of the chain fixes one coin per second (article 11, `constitution.py log`, record 12), and the client names the book as the one owner of that price (`MTWalletCore.swift:343-346`); under that rule, and only if a seed's coins come from its own presence, π_7 coins are 36 d 8 h 39 min 52 s of presence and π_8 coins are 363 d 14 h 38 min 46 s. Coins are also transferable, so the coin wall is a wall of money and not of the seed's own time; the ceiling bound in (c) is stated in coins for that reason.

**Corollary 1.2 (a cluster).** A self-sufficient cluster of adversarial seeds that certifies level k for each of its members (Theorem 4(c)) needs at least k + 1 seeds, each with ceiling ≥ k, hence at least (k + 1) · π_k coins at once: 25 132 736 coins for k = 7, 282 743 334 for k = 8, 3 141 592 650 for k = 9, 34 557 519 183 for k = 10. With a budget of 10⁹ coins (one Montana), at most 318 seeds stand at level ≥ 7, at most 31 at level ≥ 8, at most 3 at level ≥ 9, and none at level ≥ 10, whatever the fabric says.

### Theorem 2 (locality and monotonicity)

*(a) H is monotone: if V ⊆ V' as multisets, or V' is obtained from V by raising values, then H(V) ≤ H(V'); and H(V) ≤ |V|.*

*(b) f(r, w) is a function of T_r(w), c(r, w) and o(r) alone. A seed that gave r no testimony with half ≤ 1 at w has no influence on f(r, w).*

*(c) L*(r) falls from one window to the next only through one of: the balance of r falling; a regular correspondent of r leaving Reg_r (no testimony of theirs in one of the halves); a correspondent of r stating a lower ceiling than before. The chain of the person never falls (`App.md:120-121`).*

*(d) No action of a seed s ∉ Reg_r(w) ∪ {r} changes L*(r, w). In particular an adversary who holds no attack edge to r cannot lower r, and an adversary who holds attack edges to r cannot lower r below the level r's honest regulars alone give: adding or raising values never lowers H, and withdrawing the adversary's own values returns H to the honest value and no lower.*

**Proof.** (a) Let n_g(V) be the count of v ∈ V with g ≤ v. Adding values or raising values does not decrease n_g for any g, so every g feasible for V is feasible for V', and the maximum can only grow. For g = |V| + 1, n_g(V) ≤ |V| < g, so H(V) ≤ |V|. (b) is Definition 3.6 read literally; the specification states it as the purpose of weighing by ceilings: "the level of the fabric is a function of the testimonies the person holds and of nothing a third person does" (`App.md:189-191`). (c) By (a), f falls only when the multiset of values shrinks or a value falls; the multiset is indexed by Reg_r and the value of K is the minimum of stated ceilings from K; the three listed events are the only ones that shrink the set or lower a value. The term p(r) is monotone in P(r), which counts and never uncounts. (d) Such a seed holds no key in Reg_r, so by (b) it changes nothing; the second clause follows from (a) applied to the honest values as V and the honest values with the adversary's as V'. ∎

**What it rests on.** The definitions alone. It is the formal content of the sentence "the fabric only ever lowers a person below their ceiling" (`App.md:204-206`): the mechanism cannot be used to attack an honest person's standing, only — with that person's own participation, Theorem 4 — to inflate it.

### Theorem 3 (descent from the ceiling converges to min(u, H); order-independence)

Define the descent from an upper bound u ∈ ℕ:

```
D(u, V) = the first g in the sequence u, u − 1, …, 0 for which n_g(V) ≥ g
```

*(a) The predicate φ(g) ≡ n_g(V) ≥ g is downward closed: φ(g) and g' ≤ g imply φ(g'). Hence {g : φ(g)} = {0, 1, …, H(V)}.*

*(b) D(u, V) = min(u, H(V)), and the descent takes at most u − min(u, H(V)) + 1 evaluations of φ.*

*(c) The author's rule — start at min(p, ω) and descend — yields exactly L*: D(c(r), V) = min(c(r), H(V)) = L*(r) when the fabric is past its first τ₂.*

*(d) The sorted-descending loop of the reference (`levels.rs`, `fabric_level`; `MTWalletCore.swift:2205-2212`) computes H(V); its result does not depend on the order the values arrive in, and it runs in O(n log n) for n = |V|.*

**Proof.** (a) If g' ≤ g then {v : g ≤ v} ⊆ {v : g' ≤ v}, so n_{g'} ≥ n_g ≥ g ≥ g'. Since φ(0) holds (n_0 = |V| ≥ 0) and φ(g) fails whenever |V| < g, the feasible set is an initial segment {0, …, H}. (b) The descent examines u, u − 1, … and stops at the first feasible g; by (a) that is u itself if u ≤ H, and H otherwise. (c) Substitute u = c(r); min(c(r), H) = min(p, ω, H) = L*(r). (d) Let v₍₁₎ ≥ v₍₂₎ ≥ … ≥ v₍ₙ₎ be V sorted. The loop increments `level` from 0 while the next value exceeds the current `level`, i.e. while v₍ᵢ₎ ≥ i; it stops at the largest i with v₍ᵢ₎ ≥ i, and n_i ≥ i exactly when v₍ᵢ₎ ≥ i, so the stopping value is H(V). Sorting makes the result a function of the multiset; the frozen vector H(9, 1, 7, 2, 6) = 3 is given out of order for this reason (`Canon.md:3447-3448`). ∎

**Why this matters.** The council's first definition (17.10.2026) computed the level "from above" to avoid "a deadlock at zero or oscillation" (`project-fabric-of-time-level.md`; council journal line 3220). Theorem 3 shows that, once the values are ceilings rather than levels, the descent and the one-pass H are the same function; the descent is needed only in the recursive variant of Section 11, where the all-zero assignment is a fixed point and the descent from ceilings reaches the greatest one.

### Theorem 4 (what regularity costs; attack edges)

*(a) For every seed s past its first τ₂, f(s) ≤ |Reg_s|. A key K enters Reg_s only if, in each half of the last τ₂, (i) s sent K a live act, (ii) K's device then received a live act from s after having sent one to s within the last half of τ₂, and (iii) K signed a testimony naming s's fingerprint hash. Per key and per τ₂ this is at least two live acts in each direction and two ML-DSA-65 signatures by K.*

*(b) When the live acts are calls, each half costs K at least 60 seconds of received voice, measured on K's own device: at least 120 seconds per key per τ₂ that K's device must have heard from s.*

*(c) (Sybil target.) For s ∈ S, write Reg_s = A_s ⊎ Σ_s, honest keys and adversarial keys. Then f(s) ≤ |A_s| + |Σ_s|, and if 𝒜 holds no attack edges to s then f(s) ≤ |Σ_s| ≤ N − 1. A cluster of n adversarial seeds all stating ceiling ≥ n − 1 certifies f = n − 1 for each member with 2 · n · (n − 1) directed live acts per τ₂ (a complete graph, both directions, both halves): 112 acts for n = 8, 144 for n = 9. The fabric adds no barrier beyond Theorem 1 against such a cluster.*

*(d) (Honest target.) For an honest seed h with honest regular keys H_h and adversarial regular keys A_h,*

```
f(h) ≤ H( {v_h(K) : K ∈ H_h} ∪ {19}^{|A_h|} ) ≤ H({v_h(K) : K ∈ H_h}) + |A_h|
```

*so 𝒜 raises the fabric of h by at most the number of attack edges to h — each one an adversarial key that h answered in both halves — and, by Theorem 2(d), lowers it by nothing. Across all honest seeds, the total inflation 𝒜 can cause is at most |A|, the number of attack edges.*

*(e) (Sybils certified by honest people only.) If 𝒜 forgoes self-edges, then* |{ s ∈ S : f(s) ≥ k }| ≤ |A| div k.

**Proof.** (a) is Theorem 2(a) applied to V = values of Reg_s, with the membership condition of Definition 3.4 and the giving rule of `App.md:162-165`. (b) is the definition of a call that weaves, `Canon.md:2755-2766`. (c) The multiset of values has |A_s| + |Σ_s| elements; H is at most the count. In a cluster of n with all ceilings stated at ≥ n − 1 and every pair regular, each member has n − 1 values ≥ n − 1, so H = n − 1; the count of directed acts is n(n − 1) per half. (d) Adding |A_h| values can raise H by at most |A_h|, since n_g grows by at most |A_h| for every g; the bound 19 is the most a stated ceiling can be (`Canon.md:5253`). Summing over honest seeds counts each attack edge once. (e) Each such s needs k distinct honest keys regular with it, i.e. k attack edges, and an attack edge belongs to one s. ∎

**What it rests on.** (a), (b) and (d) rest on signatures and on the two-way giving rule, both verifiable by the holder; (c) rests on the stated ceiling being unverifiable (Remark 3.7) and states a limit of the mechanism, not a property.

### Theorem 5 (no gain from splitting)

*Let a person hold seeds s₁, …, s_m with a common birth no earlier than that of a single seed s₀ they could have held instead, with B(s₀) = Σ B(sᵢ), and let the person's honest regular keys be shared among the parts arbitrarily. Then*

*(a) max_i c(sᵢ) ≤ c(s₀), hence max_i L*(sᵢ) ≤ c(s₀): no part stands above the undivided ceiling. If the parts give one another no testimonies and together hold no more honest regulars than s₀ would, then max_i L*(sᵢ) ≤ L*(s₀).*

*(b) The count of parts at level ≥ k obeys Theorem 1(c) with B_𝒜 = B(s₀): at most B(s₀) div π_k parts.*

*(c) Parts that testify to one another raise each part's fabric to at most m − 1 + |honest regulars of the part| (Theorem 4(c)), and never above the part's own ceiling. A splitter with m ≥ k + 1 parts, each holding π_k coins and aged 2^k seconds, therefore reaches L* = k on every part with no honest regular at all, even when L*(s₀) < k: splitting converts a fabric-bound level into a ceiling-bound one. This is the cluster of Theorem 4(c), and its price is that of Corollary 1.2 — (k + 1) · π_k coins held at once — which the undivided seed at level k did not pay.*

**Proof.** (a) Each part is no older than s₀, so p(sᵢ) ≤ p(s₀); each part holds at most the whole balance, so ω(sᵢ) ≤ ω(s₀) by monotonicity of ω; hence c(sᵢ) ≤ c(s₀), and L*(sᵢ) ≤ c(sᵢ) by Theorem 1(a). Without self-testimonies the fabric of each part is H over a subset of the honest values, which is at most H over the whole set (Theorem 2(a)) and so at most f(s₀); with c(sᵢ) ≤ c(s₀) the minimum follows. (b) is Theorem 1(c). (c) is Theorem 4(c) with N = m: each part has m − 1 adversarial regulars stating ceilings ≥ k, so H ≥ k when m − 1 ≥ k, and L* = min(c(sᵢ), H) = k when c(sᵢ) = k. ∎

**What it does not say.** The specification is explicit that the fabric "counts keys, and nothing beyond them. A person who holds several seeds and writes from each is several correspondents; what bounds that is the ceiling each seed must reach by itself" (`App.md:212-217`). Theorem 5 bounds the *height* a splitter reaches by the undivided ceiling and the *number* of parts at a height by the coins; it does not and cannot bound the number of parts at level 0, and it does not stop a splitter from buying, with coins held at once, the fabric their honest circle withheld (part (c)).

### Theorem 6 (two devices of one signer weigh as one; a testimony cannot be re-homed)

*(a) If two devices of one seed both answer the same live act of r, r keeps one testimony from that key in the segment, so the correspondent contributes one value, as if one device had answered.*

*(b) A testimony given to r cannot be presented by a third seed q as evidence for q's fabric.*

**Proof.** (a) `Canon.md:5254`: "A signer gives one addressee at most one testimony in a segment of `segment_windows`, and a holder keeps at most one from one key in a segment … so two devices of one signer answering one act weigh as one"; `MTWalletCore.swift:2589-2594` implements the replacement by the lower ceiling. (b) The `addressee` field is the hash the holder's own fingerprint is read from, after `fingerprint_iterations` = 5 200 iterations of SHA-256 under the domain `mt-safety` over the addressee's key (`Canon.md:4592-4613`, `5244-5246`); a holder refuses a testimony naming anyone else (`Canon.md:5251`, `MTWalletCore.swift:2581`). For q to present it, q would need a key whose fingerprint hash equals r's, which is a second preimage of SHA-256 iterated 5 200 times, or r's key. ∎

---

## 6. The cost of a level, assembled

For a verifier, a seed at verified level L* = k has shown, at window w:

```
                        evidence                                  who can check it
time      P ≥ 2^k       seconds of answered presence              the identity plane proves lived time;
                                                                  the person's devices count it
money     B ≥ π_k       coins held now                            everyone ([I-2])
fabric    H(values) ≥ k at least k distinct keys, each with a     the holder (signatures, addressee,
                        signed testimony in each 7-day half,      window); after witnessing, anyone the
                        each stating a ceiling ≥ k                holder opens the root to
```

The fabric term is a *degree with a threshold on self-stated heights*. Its verifiable part is the degree — distinct keys with two-way exchange in both halves; its threshold part is stated. Against an adversary who answers himself, only the degree's cost in Theorem 4(c) and the ceilings of Theorem 1 remain. Against an adversary who needs real people, every unit of fabric costs a real person two answers a fortnight (Theorem 4(a)), and a real person's answers are not for sale in bulk without that person's time.

Timing of the fabric term. The earliest a key becomes regular is 10 080 windows (7 days) after its first testimony, since a testimony must stand in half 1. Through the first τ₂ of a seed's fabric the term equals the ceiling (`App.md:179-181`), so for fourteen days after a seed opens its fabric the fabric imposes nothing beyond Theorem 1; from the fifteenth day it demands k keys that were already regular, i.e. exchanges begun at least seven days before. A level k through the fabric is therefore never faster than the ceiling allows and never earlier than fourteen days after the fabric opened.

---

## 7. What the level does in the network

Everything in this section is taken from the set; the fabric changes the level and nothing else, so what the level does is what the fabric does.

**In the protocol: nothing.** "No plane of the protocol consumes the level and it confers no right in any of them: the standing the protocol consumes remains the lived time Identity defines, segments marked by the record's own actions, and none of these chains replaces it or enters it" (`App.md:142-145`). Minting is likewise untied from it: "a level multiplies nothing" (`MTWalletCore.swift:343-346`), by the author's word of 19.10.2026 12:3x UTC that the Global Level is untied from the minting and defined as before (council journal line 3539). Theorems 1–6 therefore bound a quantity that, in the protocol's consensus and value planes, is consumed nowhere. This is not a weakness of the proofs; it is the reason the mechanism could be built as a client-side reading first.

**In the client: access by level.** The client names every function a level opens in one place (`MTWalletCore.swift:764-793`, enum `MTLevelAccess`):

```
level 7   keepDeleted   a message the correspondent deletes for everyone stays on this phone, and the correspondent is told
level 7   autoRecord    calls are recorded by themselves (consent asked once; below the level the call screen's own mark records)
level 8   ownNode       a machine the person owns joins Montana's network through this app; copies of the phone go to it
```

(`MTWalletCore.swift:773-777`; the settings page `MontanaSettings.swift:2977-3052`; the node gate `MontanaNodeSetup.swift:131`, `MontanaHomeNode.swift:40, 186, 353`.) Below its level a switch stands off and keeps the person's choice for the day the level opens it (`MontanaSettings.swift:3014-3016`).

**Between two people: the recording precedence.** A correspondent's switch against recording "holds by level": with the switch off, recording is permitted to the other side only if the other side's level is strictly higher (`MTCallRecording.swift:22-31`, `mayRecord`: the recorder's level must exceed the forbidding side's); whether a call counts as recorded for both phones is the symmetric rule `callRecorded` (`MTCallRecording.swift:32-40`), read from the two levels each phone says in the call's capabilities (`MontanaCall.swift:1334-1338`, `1629`). This is the one place in the set where one person's level is weighed against another's. The level a phone reads from its peer here is the peer's own statement.

**Shown beside the person.** The avatar carries the balance on the left and the level on the right (`MontanaShapes.swift:656-668`), and the person's presence word to a correspondent carries "L" and the level while the owner's switch is on (`MontanaE2E.swift:624-630`). The wallet shows the three chains and the level (`MTWalletScreen.swift:1711`; `MontanaSettings.swift:2993-3010`).

**Counted across the network.** The client publishes its own level to the nodes under a seed-derived owner token, and reads back the counts of levels, from which it shows a rank (`MTWalletCore.swift:795-881`, `MTLevelDistribution`; the node door `/level-put`, `/level-get`, `montana-node-store.py:1870-1893` under `Audit/Internal`). Section 8 returns to this.

**Summary.** At the client of today the level opens two switches at 7 and a node at 8, decides who may record whom, and is shown. Theorem 1 says what those cost a manufacturer of identities: π_7 = 3 141 592 coins and 128 seconds for level 7; π_8 = 31 415 926 coins and 256 seconds for level 8; plus, from the fifteenth day, seven or eight regular correspondents stating ceilings at or above 7 or 8. The council recorded the consequence the author accepted: "for most people the fabric will be the smallest term; access 7 and 8 at seven or eight regular correspondents" (council journal line 3226).

---

## 8. Privacy of the graph

The fabric is a measure over a graph, and the graph is the most sensitive object the mechanism touches. The set's rule is absolute privacy of the graph (council journal line 3223: seals are never published; the graph of acquaintance is absolutely private), and the specification's observability ledger (`App.md:232-245`) states the closure row by row:

| Quantity | Status in the specification |
|---|---|
| the level of a person, of their wallet and of their fabric | closed to the network: computed and shown on the person's own devices, published nowhere (`App.md:242`) |
| the ceiling of a person | stated by the person to their correspondents only, inside the testimonies they give (`App.md:243`) |
| a testimony of an exchange | closed: given to the person it names alone; the network receives it only as a blinded leaf under its identifier (`App.md:244`) |
| with whom a person exchanges, how many, and when | closed: one root over blinded leaves, witnessed once in every half of τ₂ whatever the count (`App.md:245`; `Identity.md:208-213`) |

**What the construction gives.** A testimony names its addressee by a hash of the addressee's own key after 5 200 iterations (`Canon.md:4592-4613`), travels only inside what the addressee opens, and is signed by a key the client derives for that correspondence alone, so that "no key and no value of a testimony is the same in two correspondences, so none names the person to anyone else" (`MTWalletCore.swift:2349-2354`, invariant [I-17]). The witnessed root commits to leaves blinded with a factor of their own, "so that two observations of one person are not comparable and no leaf can be guessed from anything public" (`Identity.md:193-195`); the leaves are ordered and positioned so that the root is a function of the set and not of the sequence, "which is also why the moment of an observation cannot be read back out of it" (`Identity.md:198-204`). One root of thirty-two bytes stands whether one edge was seen or a hundred (`Identity.md:208-210`), and the witnessing happens once per half of τ₂ regardless of the count (`App.md:264`), so the frequency of witnessing reveals nothing about the degree.

**What a proof of the fabric must show, and where it stands.** The specification proves the level of the fabric by opening (`App.md:200-202`): the person shows the testimonies of a window to a chosen verifier, who checks k signatures, k addressees equal to the person's fingerprint hash, windows in both halves, distinct signer keys, and membership of each `testimony_id` under the witnessed root. The council's design names the next stage: a zero-knowledge proof of h over hashes, revealing neither the correspondents nor the count beyond the threshold (`project-fabric-of-time-level.md`: "a zero-knowledge proof of h is the next stage"). Such a proof must establish, inside a circuit, k ML-DSA-65 verifications over 43-byte scopes, k Merkle paths under the fabric domains, k window comparisons and k distinct keys; nothing in the set specifies that circuit, and this paper claims nothing about its cost. Until it exists, opening is selective disclosure: the verifier learns the k keys, which are per-correspondence keys naming no account.

**Two places where the client today speaks the level beyond the ledger.** (i) The client publishes its own level to the nodes (`MTWalletCore.swift:854-857`, `/level-put`) under a token derived from the seed with HKDF under the label `mt-level-distribution-v1`, and the nodes hold counts per level. The token names no account, but the node learns a level per token and the population's distribution of levels; the specification's row says "published nowhere". The council's record lists this as an open question to the author (journal line 3320, Agent 87, item 5). (ii) The presence word carries "L" and the level to each correspondent while the owner's switch is on (`MontanaE2E.swift:627-630`): a deliberate statement to correspondents, consistent with `App.md:243` in kind, broader than it in content (the level rather than the ceiling), and opt-in.

**What the graph's privacy costs the Sybil bound.** Because the per-correspondence key names no account, the stated ceiling cannot be checked against the public balance by anyone — not even by the holder (Remark 3.7). The council's definition of 17.10.2026 had the wallet part of a stated level "checked against the public balance: stated above the balance, the seal is discarded" (journal line 3221); the specification at `7194655` bounds the stated ceiling by nineteen only (`Canon.md:5253`). The two cannot both hold under [I-17]: a check against a balance needs a link from the signing key to an account, and that link is what [I-17] forbids. Section 11 lists this as a divergence for the author; the theorems above are stated for the specification as it stands.

---

## 9. Limits, and attacks the model does not close

Each item below is a claim the paper does *not* make, with the reason in the set.

1. **A cluster certifies itself.** Theorem 4(c): n adversarial seeds that state ceilings ≥ n − 1 to each other reach fabric n − 1 with no real person involved. The fabric then bounds nothing; Theorem 1 does. The specification accepts this in so many words: a false ceiling "can at most spare a person a lowering; they cannot carry anyone above that person's own ceiling" (`App.md:204-207`).

2. **The stated ceiling is unverifiable by design** (Remark 3.7, Section 8). Any bound that uses the values of correspondents, rather than their count, is a bound on honest correspondents' statements.

3. **Self-reported levels at the consumers.** Every consumer of another person's level in today's client — the recording precedence (`MTCallRecording.swift:27-31`), the avatar badge of a correspondent, the node's count — reads a self-statement from the other phone or from the caller's own. A modified client states 19. The theorems bound L*, the verified level; the consumers do not yet verify. Closure is the proof by opening of `App.md:200-202` or its zero-knowledge successor, applied at the consumer.

4. **Consent farming.** An honest person who answers strangers gives attack edges away; Theorem 4(d) counts them. The specification's defence is the two-way rule and the sixty-second bound on calls ("against a person's fabric filling with the people who merely reached them", `Canon.md:2769-2771`); against a person who chooses to answer, the set offers nothing, and a bot that elicits two replies a fortnight from many people earns an attack edge from each.

5. **Purchased balance.** The wallet term is money (Corollary 1.1). A balance moved into a seed for the window of a statement is caught by the "lowest ceiling in τ₂" rule only if the correspondent states honestly; against an adversary's own seeds, a balance moved from seed to seed serially raises each seed's ceiling for the window it holds it, and Theorem 1(c) counts seeds *at once*, not over time. An adversary with B coins can therefore hold at most B div π_k seeds at level ≥ k at any one window, but may rotate which seeds those are.

6. **Presence is parallel across seeds.** Lived time "does not parallelize for one holder" (`Identity.md:112-113`), but a seed's seconds are counted when a device holding it exchanges with a machine and is answered (`App.md:108-113`), and one machine can hold many seeds. The time wall of Theorem 1 is wall-clock per seed, not device-hours in total. The consensus plane states the same boundary for machines and the same answer: "a thousand processes on one machine would answer as a thousand living machines" were reachability the test, so the test is a place in the tree of admitted machines, bought with a continuity period; and "common ownership of several machines is not detected by this protocol and this protocol does not undertake to detect it. What bounds it is price and not detection, and the price is time" (`docs/Montana Consensus.md:1028-1041`). For seeds, the set bounds the number one device may age only through the identity plane's per-record and per-window barriers (`Identity.md:221-225`), which this paper does not analyse.

7. **Device compromise and key theft.** A stolen seed is the person: its testimonies, its ceiling, its fabric. The fabric gives the thief what it gave the owner, and the owner's correspondents keep counting the key. Revocation is outside this paper.

8. **Collusion of two real people** is two honest-looking keys, each a regular of the other, each stating a true ceiling; the fabric counts it as it should — two people — and the model has nothing to add.

9. **Self-declared leaves of the other kind.** The witnessed root also admits leaves over "the record commitment of the other" (`Identity.md:191-193`), which the observer places with no signature of the observed; the council's critic found that the cheapest action fills that scale (journal line 3502, Agent 97, first finding of the critic's record of 19.10.2026). The testimony leaf closes this for exchanges, since the testimony is signed by the other; the other kind of leaf stays self-declared and counts in no formula of this paper. The consensus plane has the rule the person plane lacks for that leaf: "Presence is witnessed and never self-declared … Self-declared presence weighs nothing, and the rule takes no exception" (`Consensus.md:1004-1010`).

10. **Window drift.** A holder accepts a window one past its own reading (`Canon.md:5252`), and the client's window is the nodes' second divided by sixty rather than the core's window (`MTWalletCore.swift:2228-2231`). A testimony near a half boundary may fall into either half on two devices that read the window one apart; the frozen vectors fix the boundary (`Canon.md:3454-3461`) but not the two readings. The effect is at most one testimony moving between halves; it changes regularity only when that testimony was the sole one in its half.

11. **The core's part is not built.** The witnessing of testimonies into the Global TimeChain is specified (`App.md:195-202`) and the council's plan names it stage 4 (journal line 3232); the client at `93fd8386` keeps testimonies in a file beside the chain of the person and writes no leaf to the identity plane (`MTWalletCore.swift:2339-2347`, `2375`; journal line 3321, Agent 87, item 6: no witnessing of the turn in the core). Until then, the root of Section 8 exists in the specification and not on the nodes, and opening proves against nothing the network holds.

12. **No global claim.** The fabric is one hop. It says nothing about the mixing time of the exchange graph, about communities, or about the number of Sybils the whole network admits per attack edge in the sense of [YKGF06, YGKX08]. Section 10 says why that is a choice and what it costs.

---

## 10. Comparison with other Sybil defences

**Douceur's impossibility.** Without a trusted authority that certifies identities, an entity can present multiple identities unless the verifier can test a resource the attacker cannot multiply [Dou02]. Montana tests three: wall-clock age of a seed, coins held at once, and the answers of real people a fortnight apart. None is a certificate of personhood; each is a resource whose multiplication has a price, and Section 5 states the price.

**Random-walk defences on a social graph.** SybilGuard [YKGF06] and SybilLimit [YGKX08] bound the number of Sybil identities an honest verifier accepts to O(√n · log n) and O(log n) per attack edge respectively, under the assumptions that the honest region of the social graph is fast mixing and that the attack edges are few. SybilInfer [DM09] makes the same assumption in a Bayesian form; SybilRank [CSYP12] propagates trust from seed nodes by early-terminated power iteration and ranks. Each of these needs the graph, or random walks over it, to be available to the party that judges: the verifier samples routes through other people's edges. In Montana the graph is published to nobody and is a root over blinded leaves at the network (Section 8); the invariant of absolute privacy of the graph removes these defences by construction, and the paper claims none of their bounds. What remains is one-hop: a person judges their own edges (Theorem 4(d)), and a verifier judges a seed by what the seed can open (Section 6). The price of the choice is Item 12 of Section 9: no bound on the Sybils the whole network admits per attack edge. Viswanath et al. [VPGM10] showed the random-walk family to be community detection in disguise and sensitive to the community structure of the honest region; Alvisi et al. [ACELP13] surveyed the field and argued for defences that make the attacker's gain per attack edge explicit. Theorem 4(d) is such a statement at one hop: one attack edge, one unit of fabric, at one honest person, never more.

**k-core decomposition and the H operator.** The coreness of a vertex is the largest k such that it belongs to a subgraph in which every vertex has degree at least k [Sei83], computable for the whole graph in O(m) [BZ03]. The council's first specification defined the fabric as the core number of the graph of regular calls (`fcd2f57`; `project-fabric-of-time-level.md`, status of 17.10.2026 22:27 UTC). The specification at `7194655` replaces it by the H-index [Hir05] over the ceilings of the regular correspondents. Lü, Zhou, Zhang and Stanley [LZZS16] proved that iterating the H operator over the neighbours' values, starting from degrees, converges to coreness: H⁽⁰⁾ is the degree, H⁽¹⁾ the h-index, H⁽∞⁾ the core number. Montana's fabric is one application of H to an exogenous value, the ceiling, rather than to degrees; the recursive variant the council left open (Section 11, D1) is the iteration, whose greatest fixed point, by Theorem 3 applied repeatedly, is the ceiling-capped analogue of coreness. The specification chose the single application because a sliding window gives the iteration no moment to restart from (`App.md:183-191`), and Theorem 2(b) is what the choice buys: a reading that no third person moves.

**Proof of personhood.** Pseudonym parties bind one token to each body physically present at an event [BKJGGF17]; later systems bind to biometrics or to synchronous tests, and a review of the subjective approaches is [SISB20]. Montana binds nothing to a body: "what the fabric counts is keys, and nothing beyond them" (`App.md:212`), and the council's critic recorded that "this is a human" is provable by nothing in the set (journal line 3503, second finding of the critic's record of 19.10.2026). The fabric's unit is instead *a key that a real person answered twice a fortnight*, and its scarcity is the time of honest people — the time-based scarcity invariant [I-15] of the role, which places anti-spam barriers in time rather than money. The wallet term of the ceiling is money; the level is consumed by no plane of the protocol (Section 7), so no protocol barrier rests on it.

**Webs of trust.** A key-signing web certifies that a signer believes a key belongs to a name; certificates are public, transitive through paths, and permanent until revoked. A testimony of an exchange certifies that an exchange happened in a window, is private to its addressee, cannot be re-homed (Theorem 6(b)), expires from the window after τ₂ (`MTWalletCore.swift:2482-2492`, [I-14]) and says nothing about a name. The two objects share only the signature.

**Summary table.**

```
                      graph known to   bound per            what is scarce          privacy of the graph
                      the verifier     attack edge
SybilGuard/Limit      yes (walks)      O(√n log n), O(log n) honest edges            none (walks cross it)
SybilRank/Infer       yes (whole)      ranking, no bound     trust seeds             none
pseudonym parties     no               one token per body    physical presence       the event's attendance
Montana fabric        own edges only   1 unit at one person  honest answers in       root over blinded leaves;
                                       (Theorem 4(d));       both halves; age 2^k;   testimonies private;
                                       cluster unbounded     coins π_k               opening is selective
                                       (Theorem 4(c))
```

---

## 11. Divergences within the set, and questions for the author

This paper decides none of the following. Each is stated with where the set says what.

**D1. The weight of a correspondent: their level or their ceiling.** The council's definition of 17.10.2026 weighs a correspondent by "their Global Level, computed and signed by their phone, the lowest over τ₂" (journal lines 3219-3221; `project-fabric-of-time-level.md`). The specification at `7194655` weighs by the ceiling and gives its reason (`App.md:183-193`); the client's header records the author's word of 18.10.2026 07:2x UTC, "a correspondent weighed by their ceiling, «yes, do it»" (`MTWalletCore.swift:2184`), while the council's memory file still lists the question as open (status of 17.10.2026 22:27 UTC, Agent 87; journal lines 3310-3313). The mathematics of the recursive variant is this. On a snapshot, define the operator Φ on assignments ℓ : seeds → {0, …, 19} by Φ(ℓ)(s) = min(c(s), H({ℓ(t) : t ∈ Reg_s})). Φ is monotone on a finite lattice, so by Tarski's theorem [Tar55] it has a greatest fixed point, reached by iterating from ℓ⁰ = c (the descent "from above", Theorem 3 applied at each seed), and a least one; the all-zero assignment is a fixed point, since Φ(0)(s) = min(c(s), H({0, …})) = 0, which is the "deadlock at zero" the council named (journal line 3220). In a sliding window the system is not restarted from c: each person holds the minimum of the levels their correspondents *stated* within τ₂, so a dip of one person's ceiling for one window lowers their stated level for τ₂, lowers each correspondent's reading for the same τ₂, and the correspondents' lowered statements lower the first person in turn; the state converges to a fixed point below the one before the dip and has no step by which to climb back, because Φ iterated from a point below a fixed point never rises above it. The two remedies the council named are the ceiling (no recursion; chosen in the specification) and a restart from c in epochs of one day (journal lines 3312-3313). *Question to the author:* confirm the ceiling as the specification holds it, or name the epoch.

**D2. Checking the wallet part of a stated ceiling against the public balance.** The council's definition: "the wallet part is checked against the public balance: stated above the balance, the seal is discarded" (journal line 3221). The specification: a stated ceiling is refused only above nineteen (`Canon.md:5253`); the client's signing key for a correspondence names no account ([I-17], `MTWalletCore.swift:2349-2354`), so no holder can perform the check. *Question:* accept the unverifiable ceiling as the price of [I-17] (the theorems above are stated this way), or specify a proof that a stated ceiling is at most the signer's wallet level without naming the account.

**D3. Calls only, or every live act.** The definition of 17.10.2026 counts calls of sixty seconds with voice both ways (journal line 3219), and the client shipped in 2238 counted calls only (journal lines 3300-3301, 3321). The author's word of 18.10.2026 00:4x — "the current result of a sliding τ₂ window over live activity: chats, calls, transfers, chess, games, video, audio, media, stickers, GIFs" (journal lines 3293-3294) — is what the specification holds (`App.md:156-160`) and what the client at `93fd8386` does (`MTWalletCore.swift:2220-2227`). Theorem 4(b) states the call-only cost separately so that either reading has its bound. The author's design of the clock fabric (the document `Montana Chasovaya Tkan prostymi slovami.md`) goes further than any of these (ribbons, echoes, seals of effort, attested marks, the rule of islands, weights from fingerprint comparison; journal line 3460); of it the set implements the level alone, and this paper covers the level alone.

**D4. "Published nowhere" against the level distribution.** `App.md:242` closes the level to the network; the client publishes its own level to the nodes under a seed-derived token (`MTWalletCore.swift:854-857`) and the nodes count levels. The council recorded this as a question to the author (journal line 3320). *Question:* keep the distribution and amend the ledger row, or withdraw `/level-put`.

**D5. The core's witnessing.** Specified (`App.md:195-202`, `Identity.md:185-213`, `Canon.md:510-518`), planned as stage 4 (journal line 3232), unbuilt (journal line 3321; `MTWalletCore.swift:2339-2347`). Until built, the proof by opening (`App.md:200-202`) has no root on the network to open against (Section 9, item 11).

**D6. The window a client reads.** The client's window is the nodes' second divided by sixty (`MTWalletCore.swift:2228-2231`), named there as a deviation from `Canon.md:2781-2782`.

**D7. The addressee.** The specification binds the addressee to the fingerprint of "the key the two of them compare out of band" (`Canon.md:5228`, `5244-5246`); the client binds it to the fingerprint material of the correspondence's secret, which both ends compute and neither tells (`MTWalletCore.swift:2349-2354`), recorded as a deviation in the client's audit (`Audit/AUDIT.md`, as the header names it), after the council found that an addressee hash "from the holder's words" let colluders name a third person (journal line 3343, closed by commit `1c031504`, journal line 3360). Theorem 6(b) holds under either binding.

**D8. The voice floor.** The client counts received voice only above −40 dBov (`MTWalletCore.swift:2233-2243`); the council recorded the threshold as not yet measured on devices (journal line 3321).

**D9. One coin per second.** Corollary 1.1 converts coins to presence under the Constitution's article 11; the Canon's emission row and that article are under the author's open decision (constitution log, record 41, 22.10.2026 12:53 UTC). The conversion is illustrative; Theorem 1 is stated in coins and does not depend on it.

**D10. One number in two places.** τ₂ = 20 160 stands in the Genesis Decree (`Canon.md:4637`) and as a constant of the client (`MontanaNames.swift:108`, "the numbers the Canon states"), equal at both revisions read. The single-source invariant [I-10] asks for one authoritative place and a reference; this is an observation of agreement, not a finding of divergence.

---

## 12. Bibliography

- [Dou02] J. R. Douceur. The Sybil Attack. *Peer-to-Peer Systems (IPTPS 2002)*, LNCS 2429, pp. 251–260.
- [YKGF06] H. Yu, M. Kaminsky, P. B. Gibbons, A. Flaxman. SybilGuard: Defending Against Sybil Attacks via Social Networks. *ACM SIGCOMM 2006*.
- [YGKX08] H. Yu, P. B. Gibbons, M. Kaminsky, F. Xiao. SybilLimit: A Near-Optimal Social Network Defense Against Sybil Attacks. *IEEE Symposium on Security and Privacy 2008*.
- [DM09] G. Danezis, P. Mittal. SybilInfer: Detecting Sybil Nodes using Social Networks. *NDSS 2009*.
- [CSYP12] Q. Cao, M. Sirivianos, X. Yang, T. Pregueiro. Aiding the Detection of Fake Accounts in Large Scale Social Online Services. *USENIX NSDI 2012*.
- [VPGM10] B. Viswanath, A. Post, K. P. Gummadi, A. Mislove. An Analysis of Social Network-Based Sybil Defenses. *ACM SIGCOMM 2010*.
- [ACELP13] L. Alvisi, A. Clement, A. Epasto, S. Lattanzi, A. Panconesi. SoK: The Evolution of Sybil Defense via Social Networks. *IEEE Symposium on Security and Privacy 2013*.
- [Sei83] S. B. Seidman. Network structure and minimum degree. *Social Networks* 5(3), 1983, pp. 269–287.
- [BZ03] V. Batagelj, M. Zaveršnik. An O(m) Algorithm for Cores Decomposition of Networks. arXiv:cs/0310049, 2003.
- [Hir05] J. E. Hirsch. An index to quantify an individual's scientific research output. *PNAS* 102(46), 2005, pp. 16569–16572.
- [LZZS16] L. Lü, T. Zhou, Q.-M. Zhang, H. E. Stanley. The H-index of a network node and its relation to degree and coreness. *Nature Communications* 7, 10168, 2016.
- [BKJGGF17] M. Borge, E. Kokoris-Kogias, P. Jovanovic, L. Gasser, N. Gailly, B. Ford. Proof-of-Personhood: Redemocratizing Permissionless Cryptocurrencies. *IEEE EuroS&P Workshops 2017*.
- [SISB20] D. Siddarth, S. Ivliev, S. Siri, P. Berman. Who Watches the Watchmen? A Review of Subjective Approaches for Sybil-resistance in Proof of Personhood Protocols. *Frontiers in Blockchain* 3, 2020.
- [Tar55] A. Tarski. A lattice-theoretical fixpoint theorem and its applications. *Pacific Journal of Mathematics* 5(2), 1955, pp. 285–309.
- [FIPS204] NIST. FIPS 204: Module-Lattice-Based Digital Signature Standard. August 2024.
- [FIPS180] NIST. FIPS 180-4: Secure Hash Standard. August 2015.
Bibliographic entries were compiled from the two sessions' knowledge of the publications (the researcher's dossier of 22.10.2026 18:52 and this author's) and agree between them; neither session had access to the publishers' pages, so page numbers and venues are stated as remembered and should be checked before external publication.

- Montana set: `docs/Montana App.md`, `docs/Montana Canon.md`, `docs/Montana Identity.md`, `Montana-Core/crates/mt-derive/src/levels.rs` at `7194655` (branch `spec/fabric-v2-88`); the iOS client at `93fd8386` (branch `rollback-898`); the council journal `~/.montana/council/journal.md` (lines as cited); the memory records `project-fabric-of-time-level.md` and `project-time-window-doubling.md`; the Constitution of the chain (`CouncilWall/constitution.py log`).

---

## Appendix A. Frozen vectors shared by the specification, the core and the client

From `Canon.md:3436-3483`, `levels.rs` (tests) and `MTWalletCore.swift:2283-2306` (`selfCheck`):

```
wallet_level(2) = 0   wallet_level(3) = 1   wallet_level(313) = 2   wallet_level(314) = 3
wallet_level(3141592653589793238) = 19

H() = 0   H(5) = 1   H(3, 3, 3) = 3   H(9, 1, 7, 2, 6) = 3   H(2, 2, 2, 2, 2, 2) = 2

half(20160, 10081) = 0   half(20160, 10080) = 1   half(20160, 0) = 2   half(10080, 20160) = 0

level_of_person(20, 5, 3) = 3   level_of_person(7, 2, 9) = 2   level_of_person(0, 9, 9) = 0

suite_id = 1, addressee = 0x22 × 32, window = 0x0102030405060708, ceiling = 9
testimony_id = ea5deddd35b6355762867a5e744e4d3fdc76c3e72d9e70d17d5907a3b056d5da
```

Each vector is named by the wrong implementation it refuses (`Canon.md:3446-3449`, `3459-3461`, `3471-3472`, `3482-3483`): a weight instead of a count, a count instead of a height, values read as already sorted, a half rounded upward, a boundary drawn after the half, a dropped fabric term, a mean, a big-endian window, a ceiling written before the window.

## Appendix B. The computations

Every number in this paper is produced by the following integer program (no floating point enters any formula; the day-hour-minute renderings are integer divisions of seconds).

```python
TAU2 = 20160; HALF = TAU2 // 2; SEGMENT = TAU2 // 14; WINDOW_S = 60
PI = "3141592653589793238"

def pi_prefix(k): return int(PI[:k])
def wallet_level(b): return sum(1 for k in range(1, 20) if pi_prefix(k) <= b)
def person_level(seconds): return seconds.bit_length() - 1 if 1 <= seconds else 0
def half(now, t): return (now - t if t <= now else 0) // HALF
def H(values):
    g = 0
    for v in sorted(values, reverse=True):
        if v <= g: break
        g += 1
    return g
def descent(u, values):
    for g in range(u, -1, -1):
        if g <= sum(1 for v in values if g <= v): return g
def level_of_person(p, w, f): return min(p, w, f)

def dhms(s):
    d, s = divmod(s, 86400); h, s = divmod(s, 3600); m, s = divmod(s, 60)
    return d, h, m, s

assert TAU2 * WINDOW_S == 1209600 and dhms(TAU2 * WINDOW_S)[0] == 14
assert HALF == 10080 and SEGMENT == 1440 and 2 + 32 + 8 + 1 + 3309 == 3352
assert [H([]), H([5]), H([3,3,3]), H([9,1,7,2,6]), H([2]*6)] == [0, 1, 3, 3, 2]
assert all(descent(u, [9,1,7,2,6]) == min(u, 3) for u in range(0, 20))
assert [wallet_level(2), wallet_level(3), wallet_level(313), wallet_level(314), wallet_level(pi_prefix(19))] == [0,1,2,3,19]
assert [half(20160,10081), half(20160,10080), half(20160,0), half(10080,20160)] == [0,1,2,0]
assert [level_of_person(20,5,3), level_of_person(7,2,9), level_of_person(0,9,9)] == [3,2,0]
assert [2**k for k in (7, 8, 10, 13, 19, 20)] == [128, 256, 1024, 8192, 524288, 1048576]
assert dhms(2**20) == (12, 3, 16, 16) and dhms(2**19) == (6, 1, 38, 8)
assert [pi_prefix(k) for k in (7, 8, 10, 13)] == [3141592, 31415926, 3141592653, 3141592653589]
assert dhms(pi_prefix(7)) == (36, 8, 39, 52) and dhms(pi_prefix(8)) == (363, 14, 38, 46)
assert [(k + 1) * pi_prefix(k) for k in (7, 8, 9, 10)] == [25132736, 282743334, 3141592650, 34557519183]
assert [10**9 // pi_prefix(k) for k in (7, 8, 9, 10)] == [318, 31, 3, 0]
assert [2 * n * (n - 1) for n in (8, 9)] == [112, 144]
```
