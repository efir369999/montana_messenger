# Changelog

Version and build number are those shown in Settings → About. Builds before 1.0 were
published on the public TestFlight link only.

## 1.0 (1404) — 2026-09-08, TestFlight

- A small photo no longer crawls behind the app's own noise: a file already on the node is not
  uploaded again (the profile picture used to be re-sent on every retry, twelve times a minute,
  and a 221 KB photo took nineteen seconds beside it); after a local socket fault a door is
  knocked again after the fast step, not in a loop; the diaries-only door is no longer handed
  out as a network door.

## 1.0 (1403) — 2026-09-08, TestFlight

- Delivery receipts and "Read" no longer get stuck between two phones in a chat: the node keeps
  every letter even when a pair's ring budget is spent (only the ring is dosed), and a phone with
  the chat open is told at once that its mailbox has something; a newer read mark replaces the
  queued one.
- No clock inside the bubble: the three dots under your last message carry the state; only the
  red mark of a failed send stays (tap to retry).
- A close button in a hexagon over any opened file.
- QR code with the time symbol in a hexagon; the chats search bar and the profile picture wear
  the same shapes; the share sheet shows a correspondent's new photo at once.
- The invitation page offers the TestFlight beta to a phone without Montana.

## 1.0 (1400) — 2026-09-08, TestFlight (beta review approved); submitted to the App Store the same evening

- Privacy on the network side: the storage nodes keep no address logs any more — the reverse
  proxy and relay journals that recorded who asked what and when are off, and the remaining
  journals live two to three days. Push notifications no longer carry a conversation tag in the
  part Apple can read; each receiver gets its own thread tag.
- One name per message: every row carries its own name from birth, quotes and pins follow it,
  and an old history is healed once when a chat opens (a message stored twice under one name
  is shown once).
- A media message that lost the three-second push race is now boxed on the node like any
  letter — it used to stay "sending" while the two texts beside it arrived.
- Chats header: the title plate and the corner buttons are octagons, the player button a hexagon.
- Node: the mailbox keeps a waiting letter for one day; abandoned upload chunks are swept again.

## 1.0 (1391) — 2026-09-08, TestFlight (beta review approved); submitted to the App Store the same day

- Delivery status in words: "Sent", "Delivered" and "Read" stand under your last message
  instead of checkmarks in the bubble. "Read" is sent only while the chat is on the
  correspondent's screen with the app in the foreground; "mark as read" from the chat list no
  longer reports "read" to the other side.
- No more false "Retry" on a delivered message: the red mark now needs evidence — the node's
  mailbox is asked before a message is painted unsent, and a message waiting for its receipt
  asks the mailbox on every attempt.
- Long messages and forwarded files reach every build: the two storage nodes answer for each
  other when a file lies on the other one; a raw service reference is never shown or sent as
  text, and rows left by older builds are healed when the chat opens.
- Ringback tells the truth: soft searching pips until the other phone confirms ringing, then
  the ring tone; captions "Calling…" → "Ringing…" → "Connecting…".
- Music player: a full page with the chat's music as a queue, search across every chat's music,
  a web search that opens inside the app and saves the found file to Saved Messages; the page
  folds into a bar over the chat and the chat list; a music button beside the chats title.
- Business card: a gold plate written in the attachment sheet, sent as a sticker, filled in
  live on the correspondent's screen while it is typed.
- Saved Messages: a note to yourself never shows "Retry"; tags (your reactions) and source
  chats narrow the search; long-press the send arrow for "Remind me" — the system rings at
  the chosen time even with the app closed.
- Chat profile: "Links" and "Music" panes beside media, video, files and voice; links open
  inside the app.
- The invitation link is an https link everywhere; opening it shows the inviter's photo at once.
- Sharing from other apps keeps the file's own name; the share sheet lists chats in the same
  order as the chat list.
- Avatars are hexagons everywhere, including the photo crop.

## 1.0 (1348) — 2026-09-06, TestFlight

Submitted to the App Store (United States) on 2026-09-08 in place of build 1344, after passing
the TestFlight beta review.

- The 24 words open your history: the sealed archive on the device is read back into the
  chats after "Forget this device" and a sign-in with the same words; conversations return with
  their names and can be answered. Each conversation carries its key and the correspondent's
  name sealed beside its letters, so a second device of the same person receives them too.
- A conversation whose key was lost before this build comes back as "Recovered history":
  readable, not answerable.
- Share a contact: a correspondent's one-day code can be passed on from their profile, the way
  you share your own; it reaches you when either side opens the chat and stays shareable for a day.
- "Forget this device" says exactly what it does; deleting the app erases the history as well.

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
