import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

// WEBRTC_NOTICES.md의 `## <이름>` + ```text 블록을 하위 구성요소별 고지로 풀어 냄 (Windows CRLF 체크아웃도 처리)
final _webrtcNoticePattern = RegExp(
  r'^## (.+)\n\n```text\n([\s\S]*?)\n```$',
  multiLine: true,
);

List<LicenseEntry> parseWebrtcNoticeEntries(String markdown) => [
  for (final match in _webrtcNoticePattern.allMatches(
    markdown.replaceAll('\r\n', '\n'),
  ))
    LicenseEntryWithLineBreaks([match.group(1)!, 'WebRTC'], match.group(2)!),
];

// 설정 › 오픈소스 라이선스에 Flutter 패키지 고지와 함께 이 앱 LICENSE와 THIRD_PARTY_NOTICES를 띄움.
// 저장소 파일을 에셋으로 그대로 실어서 문서와 앱 화면이 안 갈라짐
void registerAppLicenses() {
  LicenseRegistry.addLicense(() async* {
    yield LicenseEntryWithLineBreaks(const [
      'Intragram',
    ], await rootBundle.loadString('LICENSE'));
    // 이 파일에 LocalSend의 Apache 전문과 네이티브 빌드가 싣는 WebRTC의 BSD 전문이 들어 있음
    yield LicenseEntryWithLineBreaks(const [
      'Intragram',
      'LocalSend',
      'WebRTC',
    ], await rootBundle.loadString('THIRD_PARTY_NOTICES.md'));
    final webrtcNotices = await rootBundle.loadString(
      'assets/licenses/WEBRTC_NOTICES.md',
    );
    for (final entry in parseWebrtcNoticeEntries(webrtcNotices)) {
      yield entry;
    }
    for (final entry in const {
      'Noto Sans KR': 'OFL-NotoSansKR.txt',
      'Noto Emoji': 'OFL-NotoEmoji.txt',
      'Noto Sans Symbols': 'OFL-NotoSansSymbols.txt',
      'Roboto': 'Apache-Roboto.txt',
    }.entries) {
      yield LicenseEntryWithLineBreaks([
        entry.key,
      ], await rootBundle.loadString('assets/fonts/${entry.value}'));
    }
  });
}
