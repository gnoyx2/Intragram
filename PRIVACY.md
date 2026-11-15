# Privacy / 개인정보 처리 방침

This policy is also available under *Settings › App › Privacy policy* in the shared Flutter app. The primary Flutter web app, auxiliary HTML client and legacy HTTP guest portal have different storage/transport behavior as described below. 앱과 주 웹의 정책은 *설정 › 앱 › 개인정보 처리 방침*에서도 볼 수 있습니다. 주 Flutter 웹·HTML 보조 클라이언트·레거시 HTTP 포털의 저장·전송 방식을 아래에서 구분합니다.

## English

### No server, no account

Intragram automatically sends no data to the developer or to a cloud service, and needs no sign-up, phone number or email address.

### What stays on this device

Messages, transfer records and session keys are held in memory; selected messages and transfer history can also be saved when the vault is enabled. Burning a message drops its body; up to 512 body-free signed receipts with salted commitments, 64 signed Merkle batches and 64 witness-root observations can remain in RAM. Receipt metadata includes event/subject/attempt IDs, peer IDs and public keys, commitments, policy/outcome, nonce and time. File receipts contain a SHA-256 content digest, which permits known-file comparisons. Evidence, organization credentials and room integrity state are excluded from the vault. Panic wipe blocks new evidence and clears these states synchronously before waiting for shutdown, then clears them again; quitting also clears them. The app writes accepted files and, if enabled, a vault with optional PIN protection. Choosing to remember a display name stores it in the vault, or in a plaintext identity.json when the vault is off. On desktop it also records picked download folders to clean up interrupted downloads. Panic wipe attempts to erase the vault, saved name and folder list. Uninstalling can leave desktop app data and accepted files behind. File selection, sharing and the OS may also leave temporary copies or caches.

### What leaves this device

Messages go to devices you connect to on this local network. App-to-app 1:1 chats are end-to-end encrypted; the host reads an app group room and room files cross the LAN unencrypted. Browser portal rooms are separate and their traffic is plaintext on Wi-Fi. Optional offline organization credentials contain organization, department, role, issuer, policy, trust snapshot, expiry and the session identity public key. They are held in RAM and presented only after an encrypted app link is established, with proof of key possession; they do not verify the security code. The bundled demo issuer is public and proves no real affiliation; offline revocation checks cover only the selected snapshot. Signed author events and checkpoints accompany app room messages. When you explicitly copy an audit bundle, it contains selected signed receipts, IDs, public keys, commitments, times, salts/proof paths, a signed batch header and any attached witness receipt, without message bodies. Manual witness exchange lets another device inspect that exported metadata and sign its root; no gateway is contacted automatically. Audit copying uses sensitive clipboard handling and attempts to clear the app's own copy after 60 seconds; on Android this can wait until the app returns to the foreground. Linux clipboard managers may keep copies. You control who receives an exported copy.

### Desktop and browser privacy

macOS does not donate conversations or aliases to Siri, Spotlight or NSUserActivity. Its legacy window sharing restriction cannot guarantee protection against ScreenCaptureKit or Visual Intelligence. Windows uses capture exclusion for supported OS capture APIs and payload-free taskbar flashing instead of Toast history; neither is a security boundary. Linux marks copied text with the KDE secret hint and clears only clipboard contents it owns; clipboard managers may ignore the hint. Browser guests use the host-served inline page with SHA-256 CSP, no external requests or persistent message storage. Cancelled or incomplete downloads are not acknowledged, and burning a voice message or hiding the page releases its audio URL; a voice message released this way says it is no longer available when the page comes back and is not downloaded again. Releasing browser resources cannot guarantee physical memory erasure or prevent OS swap.

### Being found

So that nearby devices can find it, the app announces your display name, platform and port on the local network (mDNS). Anyone on the same network can see them.

### Primary Flutter web and auxiliary HTML client

Opening the public website or `web/` page requests its static files from the hosting provider (GitHub Pages for the project site at https://gnoyx2.github.io/Intragram/), which can see ordinary web request information such as your IP address, browser and the page requested, under its own privacy policy. The web client uses no analytics, external fonts, signaling, STUN or TURN service. Browser-to-browser and the new native app-to-browser messages and file bytes travel over an encrypted WebRTC data channel, not through the website host. Connection codes contain session credentials, certificate fingerprints and local connection addresses or mDNS names; share them only with the intended peer. Browser copying uses the ordinary clipboard, so clipboard history or synchronization can retain a code.

The primary Flutter web app keeps conversations in memory by default. Received files stay in browser memory or in a per-tab folder of the browser's origin-private file system (OPFS) until you choose **Save to device**; they are removed when their message is deleted, at Panic wipe, and when the app next starts after that tab was closed or reloaded. Turning on the vault uses the shared native vault codec and selected save scope in IndexedDB; it is PIN-encrypted only when PIN protection is enabled. Transfer history does not contain file bytes. Revision checks reject stale tab writes to protect a newer vault. Before a file is accepted, the browser's storage quota is checked; where OPFS cannot be written, a received file is held in memory up to 100 MiB. Closing a conversation does not remove an already downloaded file. Reloading without a saved vault loses memory-only messages; with a vault, selected history can be restored after any required PIN unlock. Browser storage and downloaded files can be copied, cleared or evicted by the browser/OS. Browser routing and mDNS are not controlled by the native app's NetworkGuard.

`web/lite.html` is an auxiliary HTML client with its own UI and tests. Its explicitly saved password vault and JSON backups use PBKDF2-SHA256 + AES-256-GCM, a separate format from the primary app. Its 500-message display bound and backup/import flow do not describe the primary Flutter vault. Neither client promises physical memory erasure or removal of saved downloads/backups.

The encrypted web client rejects legacy `IGA1.`/HTTP invitations. The native app's explicitly marked legacy HTTP guest portal remains plaintext and follows the old guest policy above. The new encrypted native WebRTC connection does not send file bytes through the HTTP upload/download endpoints.

### Encrypted web connections

The web app uses the same screens, messages and PIN vault code as the native app. Initial program files come from the website host. App/web messages and files use encrypted WebRTC DTLS without signaling, STUN or TURN services; users exchange connection codes themselves. Optional web vaults and remembered names remain in browser IndexedDB. PIN protection uses the same PBKDF2 and ChaCha20-Poly1305 as the app; enabling a vault without a PIN stores unencrypted data. Received files require an explicit download, and saved transfer history contains no file bytes. Browsers cannot enforce OS screenshot exclusion, clipboard synchronization exclusion or automatic mDNS discovery. Text fields in the app and the web app (messages, connection codes, PINs, search) opt out of browser and OS autofill, so their contents are not offered as form history; a browser may still offer to save a typed PIN as a password, which you can decline. The legacy HTTP guest portal is a separate plaintext feature.

### Permissions

Local network: to find and talk to nearby devices. Microphone: only while you record a voice message. Camera: only to scan connection and security codes; no photos are kept. Notifications: new messages while the app is in the background. Photos: only the ones you pick.

### Third parties

Intragram sends no telemetry or automatic reports to third parties. Your connected peers and the recipients you choose for exported audit bundles receive the data described above. QR codes are read on the device by open-source code that has no network component.

### Questions

Open an issue on the project's GitHub page for general questions. Report a security problem privately with the Report a vulnerability form linked from https://github.com/gnoyx2/Intragram/security/policy (a GitHub account is needed). Do not post vulnerability details in public issues.

## 한국어

### 서버도 계정도 없음

Intragram은 개발자나 클라우드 서비스에 데이터를 자동으로 보내지 않고, 가입·전화번호·이메일이 필요 없어요.

### 이 기기에 남는 것

메시지·전송 기록·세션 키는 메모리에 두며, 보관소를 켜면 선택한 메시지와 전송 기록도 저장할 수 있어요. 메시지를 소각하면 본문 참조를 버리지만 본문 없는 서명 영수증과 Salted 커밋먼트 최대 512건, 서명된 Merkle 배치 64개, 증인 루트 관측 64건은 RAM에 남을 수 있어요. 영수증에는 사건·대상·시도 ID, 피어 ID와 공개키, 커밋먼트, 정책·결과, 난수와 시각이 담겨요. 파일 영수증에는 SHA-256 내용 해시가 있어 아는 파일과 대조할 수 있어요. 증적·조직 자격·방 무결성 상태는 보관소에 저장하지 않아요. 긴급 소거는 종료를 기다리기 전에 신규 증적을 차단하고 이 상태를 동기적으로 비운 뒤, 종료 정리 뒤에도 다시 비워요. 앱을 꺼도 사라져요. 디스크에는 수락한 파일과 설정에서 켠 보관소를 쓰며, PIN 보호는 선택 사항이에요. 기기 이름을 다음에도 쓰도록 고르면 보관소에 저장하고, 보관소가 꺼져 있으면 평문 identity.json에 저장해요. 컴퓨터에선 끊긴 다운로드 조각을 지우려고 저장 폴더 목록도 적어 둬요. 긴급 소거는 보관소·저장한 이름·폴더 목록 삭제를 시도해요. 데스크톱 앱을 제거해도 앱 데이터와 수락한 파일이 남을 수 있어요. 파일 선택·공유·OS가 임시 사본이나 캐시를 남길 수도 있어요.

### 이 기기 밖으로 나가는 것

메시지는 이 로컬 네트워크에서 연결한 기기로 가요. 앱끼리 1:1 대화는 종단 간 암호화돼요. 앱 그룹 방은 호스트가 읽을 수 있고 방 파일은 LAN에서 평문이에요. 브라우저 포털 방은 앱 그룹 방과 별개이며 Wi-Fi에서 평문이에요. 선택적으로 제시하는 오프라인 조직 자격에는 기관·부서·역할·발급기관·정책·신뢰 스냅샷·만료와 이번 실행의 신원 공개키가 들어가요. RAM에만 두고 암호화된 앱 링크가 선 뒤 키 소유 증명과 함께 제시하며, 보안 코드 확인과는 별개예요. 기본 시연 발급기관은 공개돼 있어 실제 소속을 보증하지 않고, 오프라인 폐기 확인은 선택한 스냅샷까지만 반영해요. 앱 방 메시지에는 작성자 서명 사건과 체크포인트가 따라가요. 직접 감사 번들을 복사하면 선택한 서명 영수증·ID·공개키·커밋먼트·시각·salt·증명 경로·서명된 배치 헤더·연결된 증인 영수증이 담기며 메시지 본문은 없어요. 수동 증인 교환에서는 다른 기기가 이 반출 메타데이터를 보고 루트에 서명해요. 자동으로 게이트웨이에 보내지 않아요. 감사 복사는 민감 클립보드 경로로 처리하고 60초 뒤 앱 소유 복사본 삭제를 시도해요. Android에서는 앱이 화면에 돌아올 때까지 미뤄질 수 있고, Linux 클립보드 관리자는 사본을 남길 수 있어요. 반출본을 누구에게 줄지는 사용자가 정해요.

### 데스크톱과 브라우저 개인정보

macOS는 대화나 별칭을 Siri·Spotlight·NSUserActivity에 기부하지 않아요. 레거시 창 공유 제한으로 ScreenCaptureKit이나 Visual Intelligence 캡처 차단을 보장할 수는 없어요. Windows는 지원되는 OS 캡처 API에 캡처 제외를 요청하고, Toast 기록 대신 내용 없는 작업 표시줄 점멸을 써요. 둘 다 보안 경계는 아니에요. Linux는 복사한 글에 KDE 비밀 힌트를 붙이고 앱 소유 클립보드만 비워요. 클립보드 관리자가 힌트를 무시할 수는 있어요. 브라우저 게스트는 SHA-256 CSP가 적용된 호스트의 인라인 페이지를 쓰며 외부 요청이나 영구 메시지 저장을 하지 않아요. 취소되거나 미완료인 다운로드는 수신 확인하지 않고, 음성 소각이나 페이지 숨김 때 음성 URL을 해제해요. 이렇게 해제한 음성은 페이지로 돌아와도 다시 받지 않고 더 이상 재생할 수 없다고 표시해요. 브라우저 자원 해제로 물리 메모리 소거나 OS 스왑 방지까지 보장할 수는 없어요.

### 기기 찾기

근처 기기가 찾을 수 있게 앱이 표시 이름·플랫폼·포트를 로컬 네트워크에 알려요(mDNS). 같은 네트워크의 누구나 볼 수 있어요.

### 주 Flutter 웹과 HTML 보조 클라이언트

공개 웹사이트나 `web/` 페이지를 열면 호스팅 업체(프로젝트 사이트 https://gnoyx2.github.io/Intragram/ 는 GitHub Pages)에서 정적 파일을 받아요. 업체는 IP 주소·브라우저 종류·요청한 페이지 같은 일반적인 웹 요청 정보를 볼 수 있고, 그 정보에는 업체의 개인정보 처리 방침이 적용돼요. 웹 클라이언트에는 분석 도구·외부 글꼴·연결 서버·STUN·TURN 서비스가 없어요. 브라우저끼리 또는 앱의 새 암호화 웹 연결에서 메시지와 파일 바이트는 웹사이트 서버를 거치지 않고 암호화된 WebRTC 데이터 채널로 전달돼요. 연결 코드에는 세션 인증 정보·인증서 지문·로컬 연결 주소나 mDNS 이름이 담겨요. 대화할 상대에게만 전달하세요. 브라우저는 일반 클립보드를 사용하므로 클립보드 기록이나 동기화에 코드가 남을 수 있어요.

주 Flutter 웹은 대화를 기본적으로 메모리에 둬요. 받은 파일은 **기기에 저장**을 누를 때까지 브라우저 메모리나 탭별 OPFS(사이트 전용 파일 공간) 폴더에 두고, 메시지를 지우거나 긴급 소거하거나 그 탭을 닫거나 새로 고친 뒤 앱을 다시 열면 지워요. 보관소를 켜면 공통 앱의 저장 범위와 형식으로 IndexedDB에 보관하고, PIN 보호를 켠 경우에만 암호화해요. 전송 기록에는 파일 바이트를 담지 않아요. 오래된 탭이 새 보관소를 덮어쓰지 않도록 revision 충돌을 거부해요. 파일을 수락하기 전에 브라우저 저장 공간을 확인하고, OPFS에 쓸 수 없는 브라우저에서는 받은 파일을 메모리에 100 MiB까지만 둬요. 대화를 닫아도 이미 다운로드한 파일은 지우지 않아요. 저장하지 않은 대화는 새로고침하면 사라지고, 보관소를 켠 대화는 필요한 PIN을 해제한 뒤 선택한 기록을 복원해요. 브라우저·OS가 저장소와 다운로드를 복사·삭제할 수 있고, 저장소를 자동으로 비울 수도 있어요. 브라우저의 WebRTC 경로·mDNS에는 네이티브 NetworkGuard가 적용되지 않아요.

`web/lite.html`은 UI와 검사가 별도인 HTML 보조 클라이언트예요. 직접 저장하는 비밀번호 보관소와 JSON 백업은 PBKDF2-SHA256·AES-256-GCM을 사용하며 주 앱과 형식이 달라요. 보조 앱의 메시지 500개 표시 상한과 백업 가져오기 흐름을 주 Flutter 보관소의 정책으로 해석하면 안 돼요. 두 웹 모두 물리 메모리 소거나 저장한 다운로드·백업 제거를 보장하지 않아요.

새 암호화 웹 클라이언트는 이전 `IGA1.`/HTTP 초대를 거부해요. 앱에서 레거시로 표시된 HTTP 게스트 포털은 별도 평문 기능이며 위의 기존 게스트 정책을 따라요. 새 앱↔웹 WebRTC 연결의 파일 바이트는 HTTP 업로드·다운로드 경로로 보내지 않아요.

### 암호화 웹 연결

웹은 앱과 동일한 화면·메시지·PIN 보관소 코드를 사용해요. 최초 페이지와 프로그램 파일은 웹 호스팅에서 받아요. 앱·웹 사이 메시지와 파일은 외부 연결 서버·STUN·TURN 없이 WebRTC DTLS로 암호화하며 연결 코드를 직접 교환해요. 웹의 선택 보관소와 저장한 이름은 브라우저 IndexedDB에 남아요. PIN을 켜면 앱과 같은 PBKDF2·ChaCha20-Poly1305로 봉인하고, PIN 없이 보관소를 켜면 암호화되지 않아요. 받은 파일은 별도로 다운로드해야 하며 보관소의 전송 기록에는 파일 바이트를 담지 않아요. 브라우저는 OS 화면 캡처 차단·클립보드 동기화 제외·자동 mDNS 탐색을 강제할 수 없어요. 앱과 웹의 입력칸(메시지·연결 코드·PIN·검색)은 브라우저·OS 자동 완성에 참여하지 않아 입력한 내용이 입력 기록으로 제안되지 않아요. 브라우저가 입력한 PIN을 비밀번호로 저장할지 물으면 거절하세요. 이전 HTTP 게스트 포털은 별도의 평문 기능이에요.

### 권한

로컬 네트워크: 근처 기기를 찾고 대화하려고. 마이크: 음성 메시지를 녹음하는 동안만. 카메라: 연결 코드와 보안 코드를 스캔할 때만, 사진은 남기지 않아요. 알림: 앱이 백그라운드일 때 새 메시지. 사진: 고른 것만.

### 제3자

Intragram은 제3자에게 원격 분석이나 자동 보고를 보내지 않아요. 연결한 피어와 사용자가 고른 감사 번들 수신자는 위에서 설명한 데이터를 받아요. QR 코드는 네트워크를 쓰지 않는 오픈소스 코드가 기기 안에서 읽어요.

### 문의

일반 문의는 프로젝트 GitHub 페이지에 이슈를 남겨 주세요. 보안 문제는 https://github.com/gnoyx2/Intragram/security/policy 페이지에 연결된 비공개 신고 폼(Report a vulnerability)으로 알려 주세요. GitHub 계정이 필요해요. 취약점 세부 내용은 공개 이슈에 남기지 마세요.

Capture API scope: [Apple NSWindow sharing type](https://developer.apple.com/documentation/appkit/nswindow/sharingtype-swift.enum), [Microsoft SetWindowDisplayAffinity](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-setwindowdisplayaffinity).
