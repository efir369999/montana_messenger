# Releases

This file names what each folder of this repository is. The table Sources is written by the publisher in the same commit as
the folder it names.

## Sources

Each folder of this repository is the tree of one commit of the project's private history, staged as it is built. The
publisher writes this table in the same commit as the folder it names, and the message of that commit names the source
commit in full. The column Folder tree is the git tree of the folder in the commit that carries the table:
`git rev-parse HEAD:FOLDER` answers it.

<!-- sources:start -->
| Folder | Build | Source commit | Folder tree | Staged |
|---|---|---|---|---|
| `apps/apple` | 1.0 (2342) | `0e1d9b73dbee` | `52c7f497f27da9218bf9d4908e0332be3bb0c9ec` | 2026-11-01 20:43 UTC |
| `core` | 1.0 (2342) | `52ec11998aa8` | `d47fc795d1ca0c1f419a0b428286bb9efddee496` | 2026-11-01 20:43 UTC |
<!-- sources:end -->
