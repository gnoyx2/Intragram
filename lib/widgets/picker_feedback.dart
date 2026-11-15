import 'dart:async';

import 'package:flutter/material.dart';

import 'package:intragram/core/qr_image.dart';
import 'package:intragram/l10n/strings.dart';
import 'package:intragram/network/registry/incoming_path_resolver.dart';

// 파일·폴더 대화상자를 못 띄웠을 때 원인을 안내함 (대부분 Linux에 xdg-desktop-portal 백엔드가 없는 경우임)
void showPickerUnavailable(BuildContext context) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(S.of(context).t('picker.unavailable'))),
  );
}

// QR 이미지 읽기: 못 읽으면 알리고 null (취소도 null)
Future<String?> pickQrImageOrExplain(BuildContext context) async {
  final messenger = ScaffoldMessenger.of(context);
  final message = S.of(context).t('qr.unreadable');
  try {
    return await pickQrImage();
  } on QrImageUnreadable {
    messenger.showSnackBar(SnackBar(content: Text(message)));
    return null;
  }
}

// 암호화 웹 연결의 상한(64 GiB)을 넘어 빠진 파일을 알리는 콜백. 나머지 파일은 그대로 제안됨
VoidCallback fileTooLargeNotice(BuildContext context) {
  final messenger = ScaffoldMessenger.of(context);
  final message = S.of(context).t('secureWeb.fileTooLarge');
  return () => messenger.showSnackBar(SnackBar(content: Text(message)));
}

// 수락은 저장 폴더를 물을 수 있어서 대화상자 실패를 화면에 알림 (나머지 실패는 타일 상태가 보여 줌)
void acceptWithPicker(BuildContext context, Future<void> Function() accept) {
  final messenger = ScaffoldMessenger.of(context);
  final message = S.of(context).t('picker.unavailable');
  unawaited(
    accept().catchError(
      (Object _) =>
          messenger.showSnackBar(SnackBar(content: Text(message))).closed,
      test: (error) => error is PickerUnavailableException,
    ),
  );
}
