# 12. Reconcile source, specification, audits and publication

**Status: open. This directory records current limits explicitly.**

The root repository links this audit separately and reports zero closed criteria.
Its application releases remain separately identified in `RELEASES.md`. Candidate
native fixes are not described as present in the pinned public core snapshot.
Historical closure prose is not current end-to-end proof; unresolved findings
override it. The old and native core generations are evaluated separately.

Candidate proof changes update Canon/Core versions, AIR identifiers, parameter
digest, serialized widths and Genesis. The current candidate Genesis is
`ee515d902ae16ad88497ff97cb0579ddcfe19af1b60a46d4598eda68c0760ec7`.
It is not a production trust anchor or an authorization to migrate balances.
No fallback accepting retired vulnerable proof descriptions was added.

The deployed explorer now describes verified signatures and checkpoint
reconstruction within their actual limits, rather than equating root agreement
with finality or recorded sums with authorized supply. Website evidence and core
acceptance evidence remain distinct.

Closure still requires reconciling every outstanding audit entry, including
encoding/table domains, accumulation soundness, entropy assumptions and delivery.
Each closed finding needs a published implementation revision, reproducible
checks and matching statements. Public artifacts are scanned on the separate
host before publication. Historical internal reports require review; their
wholesale publication and whole-repository consistency are not claimed here.
