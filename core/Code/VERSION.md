# Version

**Implementation:** `1.3.0` (mainnet — Genesis = empty window 0: no baked bootstrap operator, no N_SEED cohort, no proof-of-work; PARAMS_ENCODED_SIZE 198. Account/Node/Candidate tables start empty; their roots are the empty sparse-Merkle root. The first node bootstraps via the existing admission path — at zero Active operators selection_slots(0)=1 self-admits the first candidate and quorum(1)=1 lets it cement its own chain. Every node starts as a candidate; candidates disabled by default (observers sync+heartbeat, --enable-candidate to re-arm). build sha tracked in git log per [C-1])
**Spec target:** Montana Protocol v36.1.0 + Montana Network v1.5.0 + Montana App v3.16.4 (2026-07-10)
**Release tag:** v1.3.0 — Genesis = empty window 0 (PARAMS_ENCODED_SIZE 198); removed baked bootstrap operator + N_SEED cohort + proof-of-work; Genesis State Hash re-baked; the first node self-bootstraps via existing admission rules (selection_slots(0)=1, quorum(1)=1)
**Cohort:** empty genesis on mainnet — Genesis State carries no baked operators. Consensus starts from the first node self-admitting through the standard candidate → admission path; the manifest nodes are discovery peers only.
**Spec paths:**
- Protocol: `../Montana Protocol v36.1.0.md`
- Network:  `../Montana Network v1.5.0.md`
- App:        `../../App/Montana App v3.16.4.md`
- Whitepaper: `../Montana Whitepaper.md`
