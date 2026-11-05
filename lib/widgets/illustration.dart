import 'package:flutter/material.dart';

// 전서구 캐릭터(P1)의 두 색(#C3C3C9·#4C586E)만으로 그린 투명 배경 컷아웃 일러스트
// 바깥 둘레에 은은한 톤 단차가 있어 별도 배경 타일 없이 라이트(#FFFFFF)·다크(#0D0F14) 바탕에 바로 올림
enum IllustrationName {
  brandPigeon('brand-pigeon.png'),
  chatBubbles('chat-bubbles.png'),
  welcomeWave('welcome-wave.png'),
  savedVault('saved-vault.png'),
  chatEnded('chat-ended.png'),
  addPeople('add-people.png'),
  searchLooking('search-looking.png'),
  radarEmpty('radar-empty.png'),
  wifiOff('wifi-off.png'),
  pinLock('pin-lock.png'),
  cameraScan('camera-scan.png'),
  errorAlert('error-alert.png'),
  loadingHourglass('loading-hourglass.png');

  const IllustrationName(this.fileName);

  final String fileName;

  String get assetPath => 'assets/illustrations/$fileName';
}

class Illustration extends StatelessWidget {
  const Illustration(this.name, {this.size = 136, super.key});

  final IllustrationName name;
  final double size;

  @override
  Widget build(BuildContext context) {
    // 장식용 일러스트라 스크린 리더 탐색에서 제외함 (옆 문구가 의미를 전달함)
    return ExcludeSemantics(
      child: Image.asset(
        name.assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}

// 앱바·게스트 포털·정보 화면 등에 놓는 정면 전서구 마스코트 아이콘
class BrandPigeonIcon extends StatelessWidget {
  const BrandPigeonIcon({this.size = 28, super.key});

  final double size;

  @override
  Widget build(BuildContext context) =>
      Illustration(IllustrationName.brandPigeon, size: size);
}
