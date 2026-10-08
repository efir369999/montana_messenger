# Versions

| What | Where it lives | Value |
|---|---|---|
| Canon, the set this tree reproduces | the header of `../docs/Montana Canon.md` | 4.2.0 |
| Montana Core | this file | 0.19.0 |

This file is the accounting place and not a second source: the set states its own version in its
own header, and a parameter of the protocol lives in `../docs` and in `mt-genesis`, nowhere else.
A change of the set's version is a change of what this tree must reproduce, and the harness is what
turns that into a failing build rather than into a thing somebody has to remember.
