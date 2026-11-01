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
| `apps/apple` | 1.0 (2330) | `d0886d400527` | `38fc77763b006aab184387698d26f2c0596af569` | 2026-11-01 15:00 UTC |
| `core` | 1.0 (2325) | `dcc0f406adc2` | `e330d5de048e3b82aea1c8bad876a950d8d6968a` | 2026-10-30 21:28 UTC |
<!-- sources:end -->
