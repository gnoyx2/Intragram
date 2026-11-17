# Changelog

Versions follow the app version in `pubspec.yaml`. The wire protocol version
(`kProtocolVersion` in `lib/core/constants.dart`) is listed because apps on
different protocol versions refuse to talk to each other.

## Unreleased (1.0.0 release candidate)

Protocol 7. Not a supported release yet: device QA is pending on every
platform (see `DEVICE_QA.md`).

Added after `v1.0.0-rc.1` (app `1.0.0+11`; the v7 wire protocol is unchanged):

- Fixed: dialogs with a text field (connection codes, PIN, rename, IP address)
  dropped its focus and closed the keyboard as soon as the keyboard left less
  than 480 px of window height, so nothing could be typed there. That is every
  phone browser, and small phones or large text in the apps. The compact dialog
  layout now keeps the same widget structure (`1.0.0+11`; the `1.0.0+10` store
  files predate this fix).
- Fixed (web): Back in an open chat on a phone browser closed the chat and also
  asked to leave the page; it now only closes the chat and Home asks. With chats
  open, a reload, tab close or address change asks through the browser
  (`beforeunload`), because browsers let two back presses in a row without
  touching the page skip the in-app question.
- Fixed (web): after a camera permission prompt, the share sheet or a file
  picker, phone browsers stayed blurred until the next tap, and that tap hit the
  control underneath. The page is covered only while the tab is hidden.
- Fixed (web): Chrome offered to translate the app from Korean on English
  phones, because the page starts as `lang="ko"` before the app sets its
  language. The app page opts out of page translation, which cannot change
  canvas text anyway.
- Fixed (web): Back never reached the app in Firefox. Flutter adds the history
  entry that catches Back as soon as the page starts, and Firefox skips history
  entries nobody touched, so Back in an open chat asked to leave the page (or
  closed a tab opened from another app). The entry is now added after the first
  touch or key press: Back in Firefox closes the chat and Home asks, as in the
  other browsers. Web only; the native `1.0.0+11` builds are unchanged.
- Fixed (web): iPhone browsers drew Flutter's web back arrow (←) on pushed
  screens; they now show the iOS chevron the iPhone app uses.

- Phone browsers: the web app now covers what the phone apps get from the OS.
  The scan icon on Home and **Scan their code** in the security code dialog use
  the camera (`getUserMedia`, frames read in memory with the app's QR decoder,
  **Read a QR image** kept as the fallback); received files and photos are kept
  through the system share sheet (**Share or save**, download where sharing a
  file is unsupported); Android browsers vibrate where the app does; with chats
  open, the back gesture on Home asks before leaving the page; the browser bar
  follows the app bar color; Settings drops page notifications that phone
  browsers cannot show and states the background limit instead.
- Fixed: Korean text in Cupertino dialogs (iPhone and Mac browsers) showed as
  empty boxes because the web bundle had no `CupertinoSystemText` font; the
  bundled font is now registered under that name on the web.
- Fixed: Android browsers read the back and close buttons twice ("Back Back").
- `tool/shared_flutter_mobile_test.mjs`: iPhone- and Android-emulated Chromium
  against a desktop peer, including a fake camera that plays the desktop's
  invitation QR.
- WebRTC third-party notices: bundled the 39 third-party component license texts
  shipped in the native WebRTC M150 (`branch-heads/7871`) prebuilt binaries into
  `assets/licenses/WEBRTC_NOTICES.md`, registered each component in the in-app
  open-source license page (`LicenseRegistry`), and attached `WEBRTC_NOTICES.md`
  to GitHub Releases alongside `THIRD_PARTY_NOTICES.md`.
- Fixed: closing an automatically joined WebRTC room before the link opens no
  longer starts the 60-second automatic-invitation cooldown on that v7 peer link.
- Fixed: frames deferred before WebRTC peer identity proof are now bounded by an
  8 MiB byte cap (`webChatMaxPendingIdentityBytes`) in addition to the 32-frame
  count cap, and unreserved `MobileFileSource` handles in a multi-file batch are
  released if an oversized file is skipped or a mid-batch reservation fails.
- Fixed: message bubbles cap their laid-out paragraph text at 65,536 characters
  while keeping the full message text for **Copy text**, so near-64 MiB messages
  in **Unlimited** mode render without stalling the browser paragraph shaper.

- Web app (preview, beta): the same Flutter app runs in a browser
  (`lib/main_web.dart`) at https://gnoyx2.github.io/Intragram/web/, deployed by
  the new `pages` workflow. It shares the home, chat, search, settings, PIN
  vault, audit and organization screens with the installed app. Checked by
  automated Chromium and Firefox runs on one computer only; Safari, phone
  browsers and two-device Wi-Fi are not run yet.
- Encrypted app–web connection: browsers and apps exchange `IGW1.` invitation
  and response codes and talk over one WebRTC data channel (SCTP over DTLS, no
  signaling, STUN or TURN server), with a six-digit security code per link.
  1:1 chats, rooms of up to 32 members relayed by the host, text up to the
  **Large messages** setting, files up to 64 GiB streamed with flow control
  (three at once per direction, batches with **Accept all**), voice messages,
  signed receipts, room author signatures, audit bundles and organization
  credentials. The `v1.0.0-rc.1` builds cannot use this connection.
- Apps already linked over v7 join a WebRTC room without typing a code: the
  authenticated v7 link carries the codes, the new link must prove the same
  device identity, and its security code starts unconfirmed. After an automatic
  invitation that failed, the app refuses new ones on that link for 60 seconds.
- An auxiliary HTML client (`/web/lite.html`) with its own storage format.
- Hosting safeguards: the web app and the auxiliary client refuse to run inside
  another site's frame, register no service worker and load no third-party
  resources.
- Accessibility: screen readers get names for read-only text on the web (peer
  ID, credential details, Merkle root, error details); a message longer than
  4,000 characters is announced as a notice plus its first 4,000 characters,
  and a reply quote or search result carries the first 1,000.
- Fixed: an open search (global and in-chat) now follows new, deleted and
  burned messages instead of keeping stale results.
- Fixed: a peer that only announced it had queued file offers and never
  accepted them could hold the sender's file budget until the room closed.
- Fixed: picking a file over 64 GiB for an encrypted web connection raised an
  unhandled error and dropped the other files picked with it. Now that file is
  left out with a notice and the others are offered.
- Bundled Noto Sans KR, Noto Emoji and Roboto so no font is fetched at run
  time, and the license page now carries the WebRTC license text next to the
  package notices.
- Security contact: GitHub private vulnerability reporting is the only private
  route; the unavailable backup e-mail address was removed from the documents
  and the in-app privacy text.

- Fixed: serialized and coalesced mDNS broadcast restarts (`DiscoveryController`)
  and excluded browser guest portal rooms (`PeerTransport.web`) from app-peer
  mDNS room hints, preventing an iOS/macOS main-thread `DNSServiceProcessResult`
  hang (`0x8BADF00D`) when a browser guest connects to the Guest Portal or an
  app group room starts.

- Fixed: native and release Apple CI jobs select the `xcode-27` runner and
  pin Xcode 27.1 through `DEVELOPER_DIR` for the iOS 27.1 hinge APIs; the
  selected Xcode version and iOS SDK are logged.

- iOS 27 Liquid Glass accessibility: live Reduce Transparency/high contrast,
  opaque surfaces and defined borders, Safari fallbacks, and resizing privacy
  covers on every iOS scene/window without chat indexing.
- Bidirectional chat/draft continuity for the requested iPhone Duo profiles,
  idiom-based iOS/iPadOS identification, vertical hinge panes below 840 pt,
  book/clamshell tabletop scanner/portal QR placement and hinge-safe dialogs.
- Android 17 `ACCESS_LOCAL_NETWORK` runtime gate (API/target 37+), denial with
  Open settings recovery, compile-36-compatible permission strings, resizable
  edge-to-edge activities and keyboard-safe PIN/audit floating-window layouts.
- Flat book folds and unfolded iPhones (split at the center)
  get two panes, with a 1 pt divider on a zero-width fold. On narrow screens a
  chat opens over the list with the platform transition again (iOS edge swipe
  back, Android predictive back) while folding still keeps the draft, the
  scroll position and an active voice recording. In tabletop posture a chat
  keeps messages above the fold and the composer below it; the
  two-pane list is no longer hidden from screen readers by the chat pane, and
  Esc/Cmd+W close the open chat when the list has focus.
- Alert dialogs and sheets scroll in 320×360 floating windows with the keyboard
  up or larger text, chat banners leave room for the composer, and iOS/macOS
  alerts turn opaque under Reduce Transparency or Increase Contrast. The
  *On this network* section names a denied Android 17 Local Network permission
  with Open Settings, returning from Settings re-checks it even without Wi-Fi,
  iOS covers drop the recording notice when capture ends while inactive, and
  browser guests keep the tabletop segment height after the keyboard opens.
- On iOS 27.1 and later the fold the system reports
  (`UIView` division regions with the `UIHingeInteraction` state) goes into
  `MediaQuery.displayFeatures`, so two panes, tabletop layouts and hinge-safe
  dialogs follow the real crease (older iOS keeps the center split), and a
  crease with margins is painted with a centered divider. Back and Android
  predictive back close a dialog or screen above a chat instead of the chat
  underneath. Tabletop chat and scanner layouts measure the crease from below
  the status bar. Alert dialog buttons scroll with the content in low windows
  (large text plus the keyboard overflowed before), the narrow-window attach
  menu scrolls, the link confirmation uses the platform alert, and backing out
  of the *Connecting* dialog cancels opening the chat.
- Desktop/Web update for requested macOS 27 Golden Gate, Windows 11 25H2/26H2,
  GNOME 50 Wayland and KDE Plasma 6: live transparency/contrast/motion events,
  native menu/keyboard parity, safe received-file selection, SDK-compatible DWM
  corners/background/capture exclusion and payload-free Windows taskbar flashing.
  macOS privacy manifest now declares DiskSpace E174.1 for the existing statvfs
  receive-space check alongside UserDefaults CA92.1.
- GTK3/GIO asynchronous XDG Settings and FileManager integration, desktop-aware
  CSD/SSD, ownership-only sensitive clipboard with KDE secret hint, target-only
  paste probing and raw PulseAudio/PipeWire pipe fallbacks for playback/recording.
- Inline web streaming progress/cancel with blob fallback and no incomplete ACK,
  voice URL disposal on burn/remove/pagehide, BFCache reconnect, 840px reading
  column, visible reaction controls, slash focus and forced-colors completion.
  Zero-Disk/no-external-request/SHA-256 CSP contracts and dependencies unchanged.
- Fixed: Windows never cleared a sensitive copy after 60 seconds, because the
  clipboard sequence number was read before `CloseClipboard`, which raises it
  when Windows synthesizes text formats. The expiry now uses the number read
  after closing plus the clipboard owner window, so another app's copy (even of
  the same text, or one that lands right after ours) is never cleared.
- Fixed: Linux voice switches once to PipeWire when the PulseAudio tools exist
  but end with an error such as a missing server (recording before its first
  audio, playback from where it stopped; no retry loop); a recording that stops
  on its own is reported instead of being sent truncated, playback whose
  PipeWire output dies too shows an error instead of finishing, and the paused
  position no longer counts the played time twice.
- Fixed: Linux no longer pins GTK's dark preference without a portal value and
  drops the override when the portal exits or restarts; the first background
  follows the Flutter engine's brightness rule instead of a "dark" substring.
- Fixed: a guest 👍 double-click or held Enter/Space toggles once; a voice message
  released on page hide says it is no longer available after a BFCache restore
  and is not downloaded again.
- Changed: macOS window protection does no work for already protected windows
  on each event (the redundant move observer is gone); Windows prints a failed
  capture exclusion with its error code on the debug console only.
- Historical verification on 2026-10-26 (development snapshot):
  **1,411 Flutter tests passed**
  (`large` excluded, 0 failed, 0 skipped), **21 browser guard groups** (374
  assertion calls), **88 web design assertion calls**, 0 analyzer issues; all ten
  required commands exit 0. macOS debug build succeeds with third-party plugin
  warnings and a local CoreSimulator version diagnostic. Headless Firefox 158
  ran the served page under its CSP and real-input browser checks. Private CI
  built Windows, Linux and macOS debug apps and an Android debug APK from
  development snapshot `95a1db6`, whose application code and tests
  match this public snapshot. Check this commit's own Actions runs before release. The private snapshot's iOS debug build failed on a runner Xcode
  without iOS 27.1's
  `UIHinge`. Large-transfer tests and physical QA remain pending. Capture
  APIs cannot guarantee ScreenCaptureKit/Visual Intelligence or absolute Windows
  capture prevention.

- Body-free Ed25519 delivery/burn/cleanup receipts, Salted Merkle batches,
  inclusion verification, selected JSON disclosure and manual second-device
  witness exchange; all audit copies use the sensitive clipboard route.
- Offline issuer-signed organization credentials and session-bound holder
  proof, with independent badges, expiry and public demo issuer labeling.
- App group room author signatures, salted payload commitments, chained
  counters, checkpoint conflict reporting and replay rejection after burn.
  Browser portal rooms remain separate.
- Panic immediately freezes evidence and clears evidence/credentials/room
  ledgers before shutdown awaits, then clears again after draining resources.
- Fixed predecode bounds for cryptographic fields, small-order metadata key
  checks, lazy audit proof construction, defensive key copies and composite
  audit layouts at 320/375/840 pt. Privacy/security documentation now describes
  retained RAM metadata and explicit export limits.

- 1:1 handshake commits to the dialer's ephemeral key before the listener
  answers, so a relay can no longer steer both screens to the same 6-digit
  code; "codes don't match" ends the link and explains why.
- Rooms close every member link when they end, and the vault keeps no room
  messages.
- Voice messages play from memory with each OS's audio API; no media library
  is bundled and no audio is written to disk.
- Wide windows (iPad landscape, desktop) show the chat next to the list;
  desktop gets the same shortcuts everywhere, context menus at the cursor, a
  text size setting and a macOS menu bar.
- Browser guests stay in after a reload, see who joins and leaves, can send
  several files and like a message from the keyboard, and their burn timers
  start on reading like the app's.
- Linux gets an app menu entry (`install.sh`), notifications and clear errors
  when a portal, `parecord` or `avahi-daemon` is missing.
- Encrypted frames must arrive in exact order: a frame dropped on the way
  ends the link instead of going unnoticed.
- A device that reconnects while both apps keep running keeps a confirmed
  6-digit code, since it proves the same identity key again; after a restart
  you compare again.
- Room file offers carry the file's SHA-256 (`dg`, older v7 apps ignore it).
  A receiving app deletes a file whose bytes were changed on the LAN and asks
  before taking the same file again.
- A tapped link opens only after a dialog that shows the real host (punycode
  when it mixes alphabets). Addresses with invisible characters or over 2048
  characters stay plain text.
- Received file names lose bidi and other invisible characters, Windows device
  names and a leading dot, and more file types ask before they open.
- The browser portal takes up to 32 guests, closes idle connections sooner and
  serves files when the host has only a link-local or IPv6 address.
- QR codes are decoded on the device by a pure-Dart ZXing port instead of
  Google ML Kit; the Android APK no longer carries ML Kit or Firelog code.
- Desktop: select part of a message with the mouse, reply and react buttons on
  hover, Fluent corners and button order on Windows, libadwaita header bars and
  boxed settings on Linux.
- macOS reopens picked download folders after a crash to delete half-received
  files. Wi-Fi details show on Korean Windows and Linux.
- Chats say why a code changed, why a transfer stopped and why the local
  server failed; Korean lines break between words; iOS and macOS use a
  readable red for destructive actions.
- Address checks read only plain decimal octets, and a peer can only name one
  of the app's own platforms.
- An offered file shows the name it will be saved under, and a folder or link
  already at that name counts as taken.
- In a room, confirming or rejecting a member's code acts on the link whose
  code was shown, also right after that member reconnects.
- Voice audio the app collects (the pieces of a voice pull, the recorder's
  PCM) is overwritten after use, whether the transfer succeeds or fails.
- Rooms no longer show the file auto-accept switch, which never applied to
  them.
- Korean copy in the app and browser client reads as Korean: sentences end
  and start again instead of joining with an English dash; status labels use
  a middle dot.
