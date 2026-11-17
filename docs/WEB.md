# Intragram Web

The primary web app runs `lib/main_web.dart` → the same `IntragramApp` as
`lib/main.dart`: HomeScreen, ChatRoomScreen, MessageBubble, ChatInput,
TransferTile, search, settings, PIN/vault, audit and organization screens.
`WebChatBridge` connects WebRTC peers to the existing store and LinkRegistry,
so a browser conversation uses the same models, strings, themes and widgets as
the installed app. This is a Flutter build, not the separate HTML client.

| Entry | Purpose | Storage |
| --- | --- | --- |
| `/web/` → `/web/app/` | Primary shared Flutter app, built with `tool/build_web_app.sh` | Native vault codec in browser IndexedDB; PIN optional |
| `/web/lite.html` | Auxiliary HTML client, separate UI and tests | Separate password-encrypted AES-GCM vault/backup format |
| Host app's HTTP guest URL / `IGA1.` | Legacy plaintext portal | Old guest behavior; never a fallback for the encrypted app |

The public address is **https://gnoyx2.github.io/Intragram/web/**. It is a
**preview (beta)**: the checks so far are automated runs in Chromium 151,
Edge 157, Firefox 160 and Safari 27 on one Mac, and phone runs in iPhone- and
Android-emulated Chromium, in Chrome and Firefox on the Android 17 Emulator and
in Safari on the iOS 27 Simulator. Real phones (iOS Safari and Android browsers
on a device), two devices on a real Wi-Fi and screen readers are **NOT RUN**
(see *Phone browsers* and *Browser support* below and
[DEVICE_QA.md](../DEVICE_QA.md)).

Local source changes do not publish the website. `docs/web/app/` is generated
and ignored by git: GitHub Pages must use the **GitHub Actions** source
(repository Settings › Pages › Source). The `pages` workflow builds the app for
`/<repository name>/web/app/`, with the repository name's exact letter case,
and deploys it together with `docs/` on pushes to `main`. With the branch
source, `/web/` would redirect to a missing `/web/app/`. Deployment steps and
rollback are in [RELEASING.md](../RELEASING.md).

The v1.0.0-rc.1 app downloads were built before this connection existed and
cannot use it; apps built from the current source can.

## Encrypted browser and app connections

1. Put both devices on the same Wi-Fi or hotspot and keep both apps/tabs open.
2. Open **Encrypted app–web connection**: in the installed app under **Guest portal**
   (QR icon on Home), in the web app from the link button or the card on Home.
3. Choose **Create a connection** → **Create invitation code** and give the
   `IGW1.` code (text, or **Show QR code**) to the intended participant.
4. They choose **Join with a code**, paste it into **Their invitation code** or
   use **Read a QR image**, choose **Create response code** and return it.
5. Paste the response into **Their response code** and choose **Connect**.
6. Open **Check security code** on both devices. Choose **They match** only if
   both show the same six digits; otherwise end the chat and exchange new codes.

Every app↔web, web↔web and app↔app WebRTC connection uses one reliable, ordered
SCTP-over-DTLS data channel. Text, file chunks and controls use this channel;
file bytes never fall back to `/api/transfer` or `/api/download`. ICE servers
are empty: there is no external signaling, STUN or TURN service. The page and
its program files are first loaded from their website host; this differs from
peer traffic, which starts only after the manual code exchange.

Codes contain session credentials, local addresses or mDNS names and certificate
fingerprints. They are encoded, not encrypted. Share them only with the intended
participant. Reloading or ending a session requires fresh codes. A QR image is
shown when a code fits QR capacity; image import or text copy/paste replaces
camera scanning. An image without a readable QR code shows an error instead of
doing nothing. Data channels carry no audio/video: voice messages are
separately consented WAV files, not live microphone streams.

## Shared chat and files

The primary app reuses the native responsive panes, themes, Korean/English
strings, local fonts, keyboard commands and chat controls. Replies, reactions,
delivery/read status, typing, read-triggered expiry, deletion, search, renames,
blocking, verified auto-accept and room membership use the same models. A chat
marks messages read only while the page (or app) is in front; a background tab
holds read receipts and read-triggered timers until it returns.

Text follows the **Large messages** setting exactly as in the app: **In memory**
(default, up to 1 MiB), **Unlimited** (up to the 64 MiB frame ceiling) or
**As a file** (over 64 KiB becomes `message.txt`). Long text and signed room
frames are split into bounded parts and reassembled before display.

Files need recipient acceptance. Files picked together are offered as one batch
of up to 32, so the receiver sees every offer and can use **Accept all** or
**Decline all**, as in the app. Larger selections are offered in groups of 32.
Up to three files flow at once in each direction of a link, the same limit as
the app's v7 transfers, in the order the receiver accepts. Further accepted files
wait for a free slot and show as accepted on the sender while earlier files are
still flowing, so they are not mistaken for unanswered offers. A peer that
queues offers and then accepts none of them is treated as not having answered. A peer that does not announce this ability (the
auxiliary HTML client) gets one file at a time. A picked file may be up to
**64 GiB**; a larger one is left out with a notice while the files picked with
it are still offered. The app writes it to
disk and the browser streams it into its origin-private file system (OPFS) with
credit-based flow control, then **Save to device** downloads it. Where a browser
lacks OPFS writable files or Web Locks, received files are held in memory up to
100 MiB. Each tab keeps its OPFS files in its own folder under a Web Lock; they
are removed when the message is deleted, at Panic wipe, and when the app next
starts after that tab was closed or reloaded. A live tab's files are never
removed by another tab's start.
Pasted images and voice notes use the in-memory path (voice up to the native
**4 MiB** / two-minute bound; a larger file named `voice-*.wav` follows normal
file consent). Completion acknowledges exactly the declared bytes after the
receiver committed them; **Save to device** is the separate browser download.
File receipt hashes and signatures are bound to the live DTLS session.

WebRTC rooms hold up to 32 members (host plus 31 links). The host relays text,
controls and files over each member's encrypted link, so a room is encrypted hop
by hop and the host can read it, as with native v7 rooms. Each member compares a
security code with the host. Signed author events and checkpoints use the common
RoomIntegrityBook: once a member's signature has been observed in the room, the
host cannot alter or invent that member's messages without the room showing a
conflict. Reactions, read marks, typing, renames and burn or delete requests are
not signed, so a host could invent those in a member's name (for example remove
a delivered message for the others). The auxiliary HTML client does not sign. A member's file reaches the
others only after the host accepted it, and each recipient accepts
independently; files a member sent together stay one batch for the others. Audit bundles, Merkle proofs, witness receipts
and organization credentials require their own verification; they do not prove
OS physical erasure or real-world identity.

### Bringing nearby apps into a room without codes

A browser cannot join a v7 chat, so the path runs the other way. In a v7 chat or
v7 room, **Add people › Encrypted app–web connection** opens a new WebRTC room
for the browser (codes are exchanged by hand as usual) and then invites the apps
of that chat into the new room automatically. In a WebRTC room the host can also
tick a nearby app under **Add people**. No one types a code for those apps: the
already authenticated app link carries the invitation and response codes.

- An app takes an automatic invite only under the rule for v7 room invites: from
  the host of a room it is already in, or in a 1:1 chat from a device it dialled
  itself or after both sides confirmed that chat's security code. Otherwise it
  refuses and the host is told why.
- The new WebRTC link must prove the same device identity as the app link that
  carried the codes. A device that answers in someone else's place is dropped
  before it receives anything from the room.
- The new link has its own security code, which starts unconfirmed. Confirming
  the v7 chat does not confirm the room.
- One app link keeps one live automatically joined room. A room that never
  connects is removed after 30 seconds, and the host is told the invite failed.
- After an automatic invite that failed (the code could not be joined, the room
  never connected, or its link failed before it opened), the app refuses new
  automatic invites on that app link for 60 seconds, and the host gets the usual
  refusal. Repeated failed invites therefore cannot keep opening WebRTC
  connections. A room that opened and ended later, a room closed by the user
  before it opened, or an invite refused because a room is still live starts no
  wait. The wait belongs to the app link and ends when that link closes.
- The earlier v7 chat and its history stay where they are. Apps that predate
  this feature ignore the invite; connect them with a code instead.

Blocking is per device identity. Blocking someone in any 1:1 chat closes the v7
chat, a separate WebRTC chat with the same device and their link in any WebRTC
room, and unblocking clears all of them. A v7 room stays managed by its host as
before: blocking does not remove that device from a v7 room you both are in.

## Phone browsers

Flutter takes the platform from the browser, so an iPhone browser shows the iOS
app's screens, page transitions and dialogs and an Android browser the Android
app's, with the same gestures (a long press on a message opens reactions and
actions). What the installed phone apps get from the OS has a browser
counterpart:

- **Camera scanning.** The scan icon on Home opens the camera and reads an
  invitation QR straight into **Join with a code**; **Scan their code** in the
  security code dialog reads the other screen's code QR, as in the app. Frames
  are read in memory and dropped, and the camera is released when the page is
  hidden or the screen closes. Without a camera, or when the browser blocks it,
  **Read a QR image** stays available (the image icon on the scan screen).
- **Share sheet.** A received file or photo is kept with **Share or save**,
  which hands it to the system share sheet (Save Image, Files, other apps).
  Where the browser cannot share that file, the same button downloads it.
- **Vibration.** Android browsers vibrate where the app does (a message arriving
  in the open app, a scan). iOS Safari has no vibration API.
- **Leaving the page.** The app keeps its chats when you go back from Home; a
  page loses them. Back in an open chat closes the chat, as in the app. With
  chats open, Android back, the iOS edge swipe or the browser back button on
  Home asks before leaving, and a reload, tab close or address change asks
  through the browser. Browsers stop pages from trapping the back button: in
  Chrome, two back presses in a row without touching the page leave without the
  question (an Android tab opened from another app closes); Firefox skips
  history entries nobody touched, so the app adds the entry that catches Back
  only after the first touch or key press (Back before that leaves at once, with
  no chats to lose yet); iOS Safari never shows the browser's own question. When
  the app is the first page in its tab, **Leave** has no page to go back to and
  the page stays open; close the tab instead.
- **Keyboard.** Tapping a text field brings up the phone keyboard and the field
  or the chat input stays above it; dialogs switch to a compact layout without
  dropping the field's focus. Send keeps the keyboard open.
- **Browser prompts.** A camera permission prompt, the share sheet or a file
  picker no longer leaves the page blurred; the page is covered only while the
  tab is hidden.
- **Browser bar.** The address bar color follows the app bar in light and dark
  themes.
- **Notifications and background.** Phone browsers cannot show this page's
  notifications (Android Chrome needs a service worker, an iOS Safari tab has no
  notification API), so Settings does not offer them there and instead says
  that the browser pauses the page soon after you switch apps or tabs.
- **Fonts.** iPhone and Mac browsers draw Cupertino dialogs with the bundled
  font, so Korean dialog text no longer turns into empty boxes.

## Differences that remain

- **Discovery.** Browsers cannot open raw TCP sockets or browse mDNS, so there is
  no automatic nearby-device list and no v7 wire protocol in the browser. Every
  WebRTC chat with a browser starts with the manual code exchange. Native v7
  chats and WebRTC chats are separate conversations: an existing v7 room cannot
  take a browser in. Its apps are brought into a new WebRTC room instead (see
  *Bringing nearby apps into a room without codes*), and an installed app keeps
  its v7 discovery for app↔app chats.
- **The auxiliary HTML client** (`/web/lite.html`) keeps its own smaller limits
  (16 KiB text frames, 100 MiB in-memory files, one offer at a time). Peers fall
  back to single offers when it is in the chat.
- **Received files in browsers** live in OPFS or memory until downloaded. The
  browser decides the final download name and folder, a reload cannot reopen a
  received file, and deleting a message or running Panic wipe cannot remove a
  download.
- **Background.** A closed, reloaded or suspended tab cannot receive messages;
  there is no push server. Mobile browsers suspend background tabs.
- **OS integrations.** Pages cannot enforce screenshot or screen-recording
  exclusion, clipboard history or cloud-clipboard exclusion, the Android
  foreground service, native folder opening, or physical RAM zeroization.
  Browser equivalents are content-free notifications in desktop browsers while
  the page is open, user-triggered Clipboard API reads, explicit downloads or
  the phone share sheet, camera scanning or QR image import, and code exchange.
- **Hidden tabs.** A browser stops painting a page the moment its tab is hidden,
  so the privacy cover the installed apps draw over the app-switcher snapshot
  cannot be drawn there: a tab preview or thumbnail can keep showing the last
  painted screen. The background auto-lock still runs on time in a hidden tab
  (memory cleared, vault sealed), and when the tab is shown again the first new
  frame is the PIN screen. Before that frame the browser shows the old one again
  for an instant (20 to 25 ms measured in Chromium), which a page cannot prevent.
- **Keyboard shortcuts.** Cmd/Ctrl+F, Cmd/Ctrl+, and Cmd/Ctrl with +, - or 0
  work in the page, but browsers keep Cmd/Ctrl+N, Cmd/Ctrl+W and Ctrl+Tab for
  their own windows and tabs; use the on-screen buttons or Esc instead.
- **Frames.** The app and the auxiliary client do not run inside another site's
  frame; they show a link that opens them in a new tab. Static hosting cannot
  send a `frame-ancestors` header, so the page checks this itself.
- **Updates.** The app registers no service worker. GitHub Pages lets browsers
  reuse files for ten minutes (`Cache-Control: max-age=600`), so after a new
  deployment a browser can keep the previous version for up to ten minutes;
  reload after that.
- **Long messages and screen readers.** In the app and on the web, a message
  longer than 4,000 characters is announced as a notice and its first 4,000
  characters; copy the message to read all of it. A reply quote and a search
  result carry the first 1,000 characters. The screen shows the whole text.
- **Browser support.** Folder drag and drop, clipboard images, media codecs,
  OPFS, camera, microphone and notification permissions depend on the browser.
  Chromium 151 and Firefox 160 pass the automated runs listed under
  *Reproducible verification* on macOS 27, Edge 157 passes the three-browser
  run and the live smoke test, and Safari 27 passes the Safari WebDriver smoke
  test there. The phone behavior above passes in iPhone- and Android-emulated
  Chromium, in Chrome 145 and Firefox 160 on the Android 17 Emulator and in
  Safari on the iOS 27 Simulator (emulated cameras and input, not a real
  phone). Real phones are NOT RUN.
  Results are recorded in [DEVICE_QA.md](../DEVICE_QA.md); sharing a widget does
  not prove every platform integration.

## Vault and privacy

The primary app defaults to memory-only chats. Enabling **Keep chats on this
device** uses the existing vault settings, save scopes, debounce and lock flow.
Vault data and remembered names are persisted in IndexedDB through the browser
private-file adapter. With PIN protection, the native PBKDF2-HMAC-SHA256
(200,000 iterations) + ChaCha20-Poly1305 format is used. **Enabling the vault
without a PIN stores unencrypted data**, as in the native app; the web settings
say it is kept in this browser's site storage. A separate duress PIN opens a
decoy session whose writes do not overwrite the real archive. Browser and native
storage locations remain separate; they are not automatically synchronized.
The HTML client's AES-GCM encrypted JSON backups are a different format and are
not the primary app's vault.

Only selected conversation/transfer history is archived. File bytes, live keys,
room integrity, audit evidence and organization state are not saved in the
vault. IndexedDB revision checks prevent a stale tab overwriting a newer vault;
a conflicting tab must reload/unlock before retrying. Browser storage can be
cleared or evicted by the browser, and private browsing may deny persistence.
An unavailable store stops startup to preserve an existing archive. Panic wipe
clears memory, the IndexedDB vault and every OPFS receive folder of the site,
including files that other open tabs received.

Every text field (messages, connection codes, PINs, search) opts out of browser
and OS autofill (`autocomplete="off"`, no autofill form), so typed contents are
not offered as form history. A browser may still offer to save a PIN typed into
a password field; decline it.

See [PRIVACY.md](../PRIVACY.md) and [SECURITY.md](../SECURITY.md) for the
distinct legacy portal policies.

## Network requirements

HTTPS or localhost is required. Plain HTTP at another device's private IP is
not a secure browser context; do not disable browser security to bypass this.
Only private, loopback, link-local or `.local` host ICE candidates are accepted.
Public/relay candidates are refused, but this is not a firewall or air-gap
guarantee. Browsers choose routes and resolve mDNS. VPNs, local-network
permissions, AP isolation, mDNS policy and firewalls can prevent a connection.

## Build and local preview

```sh
flutter pub get --enforce-lockfile
BUILD_OUTPUT_DIR=build/web-primary tool/build_web_app.sh /web/app/
python3 -m http.server 8765 --bind 127.0.0.1 --directory docs
```

Python's `http.server` keeps a listen backlog of five connections; a page with
many modules (`/web/lite.html`) can then see an occasional reset module request.
Reload, or use any static server with a larger backlog, for local checks.

Open `http://127.0.0.1:8765/web/` (it redirects to `/web/app/`, keeping only
the `lang`, `theme` and `mode` preferences) or the landing page at
`http://127.0.0.1:8765/`. `tool/web_entry.html` is the source of
`docs/web/index.html`. Rebuild the normal macOS app explicitly; an older bundle
may be a QA harness:

```sh
flutter build macos --debug --no-pub --target lib/main.dart
open build/macos/Build/Products/Debug/Intragram.app
```

For GitHub Pages project paths, build with
`BUILD_OUTPUT_DIR=build/web-pages tool/build_web_app.sh /Intragram/web/app/`.
The script always stages `docs/web/app/`, so run base-path builds sequentially
and restore `/web/app/` for the local preview afterward. Serve the entire `docs/`
folder with JavaScript MIME types for `.mjs`. The `pages` workflow compiles
Flutter before uploading `docs/` and runs on pushes to `main`; local QA needs no
workflow run or deployment.

## Reproducible verification

```sh
flutter analyze --no-pub
dart format --output=none --set-exit-if-changed .
python3 tool/check_loc.py
git diff --check
flutter test --no-pub --exclude-tags large
node tool/web_peer_test.mjs
node tool/web_portal_test.mjs
node tool/web_experience_test.mjs
node tool/web_file_queue_test.mjs
node tool/web_chat_replay_test.mjs
node tool/web_identity_reflection_test.mjs
node tool/landing_web_test.js
node tool/web_entry_test.mjs
python3 tool/build_web_app_test.py
```

Real-browser checks need `PLAYWRIGHT_MODULE` and `CHROME_PATH` pointing at a
local Playwright module and Chromium:

- `tool/shared_flutter_browser_test.mjs`, `tool/shared_flutter_extended_qa_test.mjs`,
  `tool/shared_flutter_more_qa_test.mjs`, `tool/shared_flutter_parity_qa_test.mjs`
  and `tool/shared_flutter_gap_qa_test.mjs` drive the real shared Flutter UI in
  isolated Chromium contexts (build `lib/main_web.dart` to `build/web` first).
  Only a final PASS counts.
- `tool/shared_flutter_hidden_tab_test.mjs` opens a visible Chromium window: a
  headless page never becomes hidden. It checks the background auto-lock in a
  really hidden tab and saves the first frames shown after coming back.
- `tool/shared_flutter_hostile_host_test.mjs` makes the room host hostile with a
  wire hook in the host page only: it alters the text of another member's signed
  message, strips its signature, replays signed frames and invents timer and
  burn controls. The other Flutter member must show the room integrity warning
  or ignore the frame; the one accepted case (a burn sent in the author's name)
  is the documented limit above.
- `tool/shared_flutter_limits_qa_test.mjs` checks limits in the real UI: a sparse
  file of 64 GiB + 1 byte is left out with a notice (a small file picked with it
  is still offered), a file of exactly 64 GiB is offered, and a hands-free
  recording stops by itself at two minutes and arrives as 120 s of audio.
- `tool/shared_flutter_room_capacity_test.mjs` fills a room to its limit: a
  Flutter host with 31 members (2 Flutter pages and 29 auxiliary HTML clients,
  to keep memory in bounds), broadcast and relay to everyone, the refused 33rd
  invitation and a seat reused after a member left.
- `tool/shared_flutter_firefox_test.mjs` runs the same UI in the installed
  Firefox (WebDriver BiDi, `FIREFOX_PATH`) against Chromium: both invitation
  directions, security code, text and files both ways, a Firefox room member.
- `tool/safari_webdriver_smoke_test.mjs` runs the same UI in Safari through
  `safaridriver` (Safari Settings > Developer > Allow remote automation)
  against Chromium: both invitation directions, the same security code, text
  both ways and a file each way byte-exact, nothing loaded outside the page
  origin and no ICE server. Set `WEB_APP_URL` to the app page, local or
  deployed, and keep the Safari automation window in front during the run.
- `tool/shared_flutter_mobile_test.mjs` runs the app in iPhone- and
  Android-emulated Chromium against a desktop Chromium peer. The desktop shows
  its invitation QR, a fake camera plays that QR to the phone, and the phone
  scans it, connects, chats both ways, opens message actions with a long press,
  hands a received photo byte-exact to a recording share sheet, vibrates on
  Android only, asks before the back gesture leaves Home, hides page
  notifications in Settings and colors the browser bar like the app bar. Set
  `WEB_APP_URL` to the app page, local or deployed.
- `tool/browser_platform_test.mjs` uses a separate `tool/browser_platform_qa.dart`
  build (`--output build/browser-qa`) for vault/download/voice adapters; it does
  not establish production UI parity.
- `tool/web_package_browser_test.mjs` checks the packaged `/web/` entry; set
  `WEB_PACKAGE_PREFIX=/Intragram` for a Pages-path build.
- `tool/live_web_smoke_test.mjs` checks a deployed site without changing it: set
  `WEB_BASE_URL` (for example `https://gnoyx2.github.io/Intragram/`); two
  browser contexts connect through the public page, exchange text and a file
  each way, and every request must stay on that origin.
- `tool/web_browser_test.mjs` and `tool/web_experience_browser_test.mjs`
  exercise only the auxiliary HTML client.

`tool/web_peer_harness.dart` is QA-only, never imported by production. Run it
with loopback and a random `QA_SECRET` of at least 16 characters; use its logged
`INTRAGRAM_QA_PORT` with `tool/native_web_browser_test.mjs`. This checks real
native WebRTC/Chromium DTLS, file bytes, receipts and fingerprint tampering,
using `/web/lite.html`. It cannot substitute for normal app UI testing. If its
build overwrote the app bundle, rebuild `lib/main.dart` afterward.

Physical devices, Safari/Firefox/Edge, other operating systems, actual recording
permissions and two-device Wi-Fi require their own measured results in
[DEVICE_QA.md](../DEVICE_QA.md). Missing environments remain **NOT RUN**.
