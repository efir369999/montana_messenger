# Changelog

Version and build number are those shown in Settings → About. Builds before 1.0 were
published on the public TestFlight link only.

## 1.0 (1344) — 2026-09-06

The first release. Build 1344 is the release build: the App Store (United States) and
TestFlight carry the same binary under version 1.0.


- Forwarding now delivers: a forwarded text, photo, video, voice message or document rides
  the same road as a sent one and reaches the recipient. Earlier builds put the copy into
  the sender's own chat and never sent it.
- A minimised call shows a green handset (return to the call) left of the contact's name
  and a red handset (end the call) right of it, in the open chat and in the chat list; the
  floating pill no longer covers names.
- A voice call is recorded as a voice call: the chat marks a call as video only after a
  video frame has actually been rendered.
- Presence is refreshed by any word from the other side — receipts, typing, call signals —
  not only by opening the chat, and "on a call" is shown in the status line.
- The direct road between two phones is TCP by address (local network, IPv6, forwarded
  port). The UDP hole-punching of earlier builds is gone: it opened no channel and exhausted
  file descriptors on a network switch.
- The signalling lane to the nodes holds one elected door per network, re-elects on a
  network change, and remembers a dead door for a minute; the typing indicator no longer
  freezes on a Wi-Fi/cellular switch.

## 0.312 (1277) — 2026-09-02

- A message keeps its own moment: the hour shown on a received message is the hour it was
  sent, and media takes its place by the same rule.
- Opening a chat lands at the bottom; a picture or video announced by a banner is shown
  whole.
- The typing indicator shows exactly what stands in the field and ends when the field is
  emptied.
- The full set of reactions has no empty cells.
- Delivery walks machines rather than doors, so a busy node is asked once.
