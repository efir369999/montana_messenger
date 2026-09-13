# Changelog

Version and build number are those shown in Settings → About. Builds before 1.0 were
published on the public TestFlight link only.

## 1.0 (1507) — 2026-09-13, TestFlight

- Calls: a ringing phone stops the moment the caller hangs up. A ring raised by the wake carries its
  own end — it cannot outlive the call's ninety seconds — and the signalling lane stays awake for as
  long as the phone rings, so the hang-up is collected at once instead of lying on the node.
- Calls: ringback starts in seconds instead of a dozen. The phone knocks the doors it has proof of
  first, and a standing question leaves a door the moment that door falls silent; a call's birth
  and a network change cut it by the same one move.
- Calls: the camera of a person who answers from the lock screen comes up seconds sooner — a camera
  the system holds is awaited and then tested, never torn down against the system's own resume.
- Calls: no line under the name on the call screen. The status line and the light say what the call
  is doing; every cause behind a failure is written to the diaries instead of the screen.
- Notifications: one call shows exactly one notification. A missed call is announced loudly only to
  a phone that never rang; the second bell waits the ten seconds it names; the bell and the
  missed-call word share one place on the screen, so the newer replaces the older; and a
  notification left over from a call the phone has already served is taken down by itself.
- Notifications: when the extension cannot run, the words a phone shows are in its own language and
  true to the event — Incoming call, Missed call, New message — resolved from the phone's own
  catalogue. A build that does not hold those words is sent the wording it has always been sent.
- Messages: editing a message changes it on the other person's screen too, with an edited mark. A
  word off the wire can never rewrite one's own letters, and an edit that outran its letter is
  applied the moment the letter lands.
- Messages: every rung of the delivery ladder carries its word — Sending, Sent, Delivered, Read,
  Not sent. Dots without a word are gone.
- Sharing: the share sheet asks the door that answered last and holds one deadline instead of
  standing on a dead one; a link shared from any app arrives as a link in a text bubble, never as a
  text file.
- Presence: a locked phone is no longer shown as being in the chat — only a live word lights
  presence — and leaving a chat reaches the other side even as the app goes to the background.

## 1.0 (1496) — 2026-09-13, TestFlight

- Calls: the ring reaches the other phone by every road for the whole life of a call. The caller
  knocks every five seconds until the other phone says it is ringing; a call lives ninety seconds
  on both phones and at the wake service alike, one number; a wake delayed longer than that never
  rings as a ghost.
- Calls: the second bell. When the wake was accepted but the other phone did not say "ringing"
  within ten seconds, the invitation arrives as an ordinary notification — "incoming call, tap to
  answer"; the tap opens the app and the call rings natively while it is still alive. The native
  ring, the missed-call word and the end of the call take that notification down.
- Calls: a call carries one name on every road (the wake, the letter, the live channel), so a late
  copy of an invitation cannot ring after the call has ended, and a call born on the live channel
  is no longer lost by the node queue; an invitation from an older build that came without the
  name is kept and adopted when the named one arrives.
- Calls: the phone knocks the doors alive for it first and stands one attempt on each; "the other
  phone is not set up for calls" is said only when every wake service says so; the relay pass is
  renewed before a call when it nears its end.
- Calls: the call record names whose side a missed call is on — a wake accepted by Apple without
  a ring word, no road to the network, no registration, the other person's hand, the media path.
- Diagnostics: the notification extension stamps the moment it drew breath, so the delivery time
  of a push is measurable from the diaries.

## 1.0 (1490) — 2026-09-12, TestFlight

- Calls: a call no longer drops half a minute in. A phone could receive its own ring letter back
  from the node and answer it with a hang-up sent to the other side; now the node never wakes the
  sender of a word, the phone buries a call word carrying its own seed, and the ring letter leaves
  the queue the moment the other phone rings. The caller's name is learned in one place — the
  branch that accepts the call — so a returned echo can no longer rename a contact.
- Calls: the call record tells the road from the person — the time from the answering hand to
  the first media path stands apart from the ringing; every end is named (the lock-screen End
  too); the battery is read for voice calls as well.
- Album: the pages are the system's own paging — the picture follows the finger and settles;
  the album opens on the photo you tapped and the strip below stands on it; a tap at the left or
  right edge turns exactly one page, and a tap that lands mid-turn is taken right after it; a
  button bottom left returns to the message in the chat; closing is a plain pull, no fly-back.
- Attachments: tapping a photo in the picker opens the album from below with the caption field
  and the send button under it — pick, write and send without going back to the grid; sending
  with nothing picked sends the page on screen.
- The app icon and the logo carry the gold time symbol, centred on its trunk.
- Diagnostics: a death of the app on screen is judged for a cause (a reinstall, a reboot, a
  stalled main thread, a memory warning) instead of a bare verdict; a main-thread reading that
  crossed sleep is thrown away and says so.

## 1.0 (1470) — 2026-09-11, TestFlight

- Chats: the refresh coin has its own pull — both faces turn with the finger, a full turn presses
  the logo, and every pull checks the mailbox in the background. Status dots stand left of the hour
  on the row, the same three as under your last bubble; the name and the preview sit centred between
  the row lines. Saved Messages wears your own face, shows no status and can no longer fall into
  "Retry".
- Presence: a peer's last time online is learned without opening the chat (the node answers one
  question for every peer at once); anything under a minute reads as one minute.
- Bubbles: translucent by the dark reference — theirs dark grey, yours blue, white text on both,
  the fill as see-through as the slider allows by default; one default for every message style,
  and the appearance preview draws exactly your own settings. One text bubble holds 4500 characters.
- The system text size changes the letters of a message and nothing else: menus, buttons,
  reactions, the call screen and the photo viewer keep their shape at every setting.
- Media: a save circle to the right of their photo or video — saving does not open the picture;
  a green diskette marks a saved file. Photos and videos share one gallery with the strip, the
  play button in the middle of the frame; the photo feed uses the video feed's format; links are a
  list in time order.
- Bubble menu: the status of your letter and the time it reached it stand above the actions.
- Calls: the Calls tab wears the Chats tab's style and is built from one call log fed by the
  native recents and the chats; a battery light replaces the saving notice.

## 1.0 (1449) — 2026-09-10, TestFlight

- Chats: the logo folds and unfolds its bar and the search as one; a pull on the feed refreshes
  with the Montana coin spinning; the crest stands behind the conversations; the compose button
  wears the bar's glass; the native skin is the default for everyone. The list no longer crashes on scrolling (a layout recursion of the
  previous builds is gone) and builds of one screen compile in a minute and a half after the
  source was cut into screen files.
- Pictures pasted into the message field stand above it as attachments and go out as photos;
  a see-through picture is sent as a sticker.
- The photo viewer pages through every photo of the conversation; the strip at the bottom is a
  cover flow — the centred cover is the page; one tap hides the strip and the button.
- Calls: renegotiation is idempotent (a duplicate offer or answer from the second signal road is
  buried), so turning video on no longer stalls for a minute; the battery, the charger, Low
  Power Mode and the thermal state are measured during a call and drive a power floor on the
  video ladder — half resolution and 15 fps under pressure, the voice untouched.

## 1.0 (1430) — 2026-09-10, TestFlight

- The Chats tab wears one glass bar, the mirror of the tab bar below: seven glyphs on one plate
  (menu, player, links, logo, photos, video, globe), and a glass puck that flows to the glyph you
  tap. The search field is the first row of the list and scrolls with it; while it holds focus
  the results stand under it.
- Two new feeds: every link and every photo of your conversations as a still of that minute —
  five messages before, three after, drawn with the chat's own bubbles — swiped vertically like
  the video feed; a tap under the still opens the chat at that message.
- A sent message floats from the field into its bubble at one size, without widening or
  narrowing on the way; each skin keeps its own lift.
- Links are white and underlined under the native skin; round video notes arrive round and open
  full width over the chat, then fold into a video dock; voice messages carry the waveform and
  1x / 1.5x / 2x speed; the music player is music only, with a playlist on a swipe up.

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
