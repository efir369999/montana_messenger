# Credits

Montana and its iOS original (`apps/messenger/ios` of this repository) belong to their original authors. Their authorship,
the existing licences and every earlier notice stand as they are — among them `core/Code/LICENSE-APACHE`,
`core/Code/LICENSE-MIT` and the notices of `core/`.

## Montana for Windows

Porting and adaptation from Montana iOS to Windows: **DinetPDA — Linkora**.

## Montana for Android (`apps/messenger/android-dinetpda/`, branch `dinetpda/android`)

Porting work towards iOS parity on top of the project's own Android client, and the counterpart of the Windows checks:
**DinetPDA — Linkora**. Until 25.10.2026 these changes stood on branch `dinetpda/android-windows-counterpart`.

These credits cover the ports alone; they do not claim the authorship of Montana itself.

## Dinet Device Sync

Dinet Device Sync: **DinetPDA — Linkora**.

A planned additional module of the Windows port (then of Android), for what the original protocol does not already carry
between the devices of one identity: an encrypted transfer between one's own devices and, by the person's choice, end-to-end
encrypted transit through a relay that keeps nothing. Everything the iOS original already does is ported compatibly with it
and stays the original authors' work; the module neither replaces nor changes Montana's protocol, and the iOS client is not
touched. Status: design and requirements only — no code on this branch.

## Third-party components

Rust crates and npm packages are pinned in `app/src-tauri/Cargo.lock`, `app/protocol-core/Cargo.lock` and
`app/package-lock.json` and keep their own licences (among them Tauri — MIT OR Apache-2.0; React — MIT; qrcodegen — MIT;
russh — Apache-2.0; lzfse_rust — MIT OR Apache-2.0).
