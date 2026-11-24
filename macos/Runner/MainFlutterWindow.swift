import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  private var voicePlayer: VoicePlayer?
  private var privacyChannel: FlutterMethodChannel?
  private var menuChannel: FlutterMethodChannel?

  override func awakeFromNib() {
    self.sharingType = .none
    let flutterViewController = FlutterViewController()
    // 첫 프레임 전엔 FlutterView 기본색이 검정이라 라이트 모드에서 검은 창이 번쩍이므로 외형별 앱 배경색을 미리 지정함
    flutterViewController.backgroundColor = NSColor(name: nil) { appearance in
      appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        ? NSColor(srgbRed: 0x0D / 255, green: 0x0F / 255, blue: 0x14 / 255, alpha: 1)
        : .white
    }
    self.backgroundColor = flutterViewController.backgroundColor
    self.contentViewController = flutterViewController

    // 420×560은 두 줄 채팅 앱바 제목과 오른쪽 액션, 오프라인 배너, 말풍선 3개, 입력창이 글자 배율 1.0에서 안 찌그러지는 최소치임
    self.minSize = NSSize(width: 420, height: 560)

    // setFrameAutosaveName은 같은 이름으로 저장된 프레임이 있으면 바로 복원해서, 저장된 게 없을 때(첫 실행)만
    // 기본 크기와 가운데 정렬을 씀 (안 그러면 실행할 때마다 방금 복원한 위치·크기를 기본값으로 덮어씀)
    let autosaveName = "MainWindow"
    let hasSavedFrame =
      UserDefaults.standard.string(forKey: "NSWindow Frame \(autosaveName)") != nil
    self.setFrameAutosaveName(autosaveName)
    if !hasSavedFrame {
      self.setContentSize(NSSize(width: 1100, height: 760))
      self.center()
    }

    RegisterGeneratedPlugins(registry: flutterViewController)

    // macOS는 스크린샷을 감지하지 않음 (intragram/screenshot 채널 없음). 샌드박스 앱은 기본 저장 위치인 바탕화면의
    // Spotlight 결과를 못 받아 Cmd+Shift+3을 놓치고, 컴퓨터 전체 kMDItemIsScreenCapture 질의는 다른 앱이 저장한
    // 화면 캡처 파일까지 잡아 상대에게 틀린 알림을 보냄. 창은 sharingType = .none으로만 보호함
    voicePlayer = VoicePlayer(messenger: flutterViewController.engine.binaryMessenger)
    privacyChannel = FlutterMethodChannel(
      name: "intragram/privacy",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    privacyChannel?.setMethodCallHandler(MainFlutterWindow.handlePrivacy)
    NSWorkspace.shared.notificationCenter.addObserver(
      self, selector: #selector(accessibilityChanged(_:)),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil
    )
    menuChannel = FlutterMethodChannel(
      name: "intragram/menu",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    super.awakeFromNib()
  }

  // 메뉴 막대(MainMenu.xib, First Responder 액션) 명령은 Dart(AppCommands)가 단축키와 동일한 경로로 처리함
  @objc func showSettings(_ sender: Any?) { menuChannel?.invokeMethod("settings", arguments: nil) }
  @objc func newConnection(_ sender: Any?) {
    menuChannel?.invokeMethod("newConnection", arguments: nil)
  }
  @objc func closePage(_ sender: Any?) { menuChannel?.invokeMethod("close", arguments: nil) }

  @objc func findMessages(_ sender: Any?) { menuChannel?.invokeMethod("search", arguments: nil) }
  @objc func increaseTextSize(_ sender: Any?) {
    menuChannel?.invokeMethod("textSize", arguments: 1)
  }
  @objc func decreaseTextSize(_ sender: Any?) {
    menuChannel?.invokeMethod("textSize", arguments: -1)
  }
  @objc func resetTextSize(_ sender: Any?) {
    menuChannel?.invokeMethod("textSize", arguments: 0)
  }

  @objc private func accessibilityChanged(_ notification: Notification) {
    let workspace = NSWorkspace.shared
    privacyChannel?.invokeMethod(
      "onReduceTransparencyChanged", arguments: workspace.accessibilityDisplayShouldReduceTransparency)
    privacyChannel?.invokeMethod(
      "onReduceMotionChanged", arguments: workspace.accessibilityDisplayShouldReduceMotion)
    privacyChannel?.invokeMethod(
      "onHighContrastChanged", arguments: workspace.accessibilityDisplayShouldIncreaseContrast)
  }

  override func addChildWindow(_ childWin: NSWindow, ordered place: NSWindow.OrderingMode) {
    childWin.sharingType = .none
    super.addChildWindow(childWin, ordered: place)
  }

  override func beginSheet(_ sheetWindow: NSWindow, completionHandler handler: ((NSApplication.ModalResponse) -> Void)? = nil) {
    sheetWindow.sharingType = .none
    super.beginSheet(sheetWindow, completionHandler: handler)
  }

  deinit {
    NSWorkspace.shared.notificationCenter.removeObserver(self)
    NotificationCenter.default.removeObserver(self)
  }

  // 마지막 copySensitive 직후의 changeCount. 내용을 안 읽고 우리 복사본인지 비교함
  private static var sensitiveChangeCount: Int?

  // copySensitive: 이 Mac에서만(.currentHostOnly라 Universal Clipboard로 다른 기기에 안 넘어감), 클립보드
  // 관리자가 기록하지 않게 nspasteboard.org의 Concealed 표식을 같이 둠
  // clipboardKinds: 붙여넣기 버튼용으로 형식 목록만 봄 (내용을 읽으면 macOS 15.4+ 붙여넣기 경고가 뜰 수 있음)
  private static func handlePrivacy(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let board = NSPasteboard.general
    switch call.method {
    case "copySensitive":
      _ = board.prepareForNewContents(with: .currentHostOnly)
      board.setString(call.arguments as? String ?? "", forType: .string)
      board.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
      sensitiveChangeCount = board.changeCount
      result(nil)
    case "clearIfOwn":
      let own = sensitiveChangeCount == board.changeCount
      if own { board.clearContents() }
      sensitiveChangeCount = nil
      result(own)
    case "clearClipboard":
      board.clearContents()
      sensitiveChangeCount = nil
      result(nil)
    case "revealFile":
      // Finder에서 받은 파일을 선택 상태로 엶 (같은 프로세스 안이라 선택한 폴더의 샌드박스 권한이 유지됨)
      guard let path = call.arguments as? String else { return result(false) }
      NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
      result(true)
    case "bookmarkDirectory":
      // 샌드박스는 고른 폴더 권한을 이번 실행 동안만 줌. 크래시로 남은 .part를 다음 실행에서 지우려고 북마크를 둠
      guard let path = call.arguments as? String,
        let data = try? URL(fileURLWithPath: path, isDirectory: true).bookmarkData(
          options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
      else { return result(nil) }
      result(FlutterStandardTypedData(bytes: data))
    case "openBookmark":
      // 접근은 앱이 끝날 때까지 둠 (패닉 정리도 같은 폴더를 다시 훑음)
      // stale(옮겨진 폴더)이어도 그대로 씀: 그 폴더를 다시 고르면 새 북마크로 적힘
      var stale = false
      guard let bookmark = call.arguments as? FlutterStandardTypedData,
        let url = try? URL(
          resolvingBookmarkData: bookmark.data, options: [.withSecurityScope, .withoutUI],
          relativeTo: nil, bookmarkDataIsStale: &stale)
      else { return result(nil) }
      _ = url.startAccessingSecurityScopedResource()
      result(url.path)
    case "reduceTransparency":
      result(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    case "highContrast":
      result(NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast)
    case "reduceMotion":
      result(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    case "clipboardKinds":
      let types = (board.types ?? []).map(\.rawValue)
      result([
        "image": types.contains { NSImage.imageTypes.contains($0) },
        "files": types.contains(NSPasteboard.PasteboardType.fileURL.rawValue),
      ])
    default:
      result(FlutterMethodNotImplemented)
    }
  }
}
