import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:intragram/core/qr_image.dart';

void main() {
  testWidgets(
    'uploaded QR images read complete SAS and long invitation payloads',
    (tester) async {
      await tester.runAsync(() async {
        for (final text in [
          'intragram-sas:123456',
          'IGW1.${List.generate(1800, (i) => 'aZ1_bQ2-k8'[i % 10]).join()}',
        ]) {
          // Include the 300 px dialog minus its QR padding, plus exported images.
          for (final side in [280.0, 600.0, 800.0]) {
            await _expectRoundTrip(text, side);
          }
          await _expectRoundTrip(text, 300, transparent: true);
        }
        expect(await decodeQrImage(Uint8List.fromList([1, 2, 3])), isNull);
        expect(await decodeQrImage(Uint8List(10 * 1024 * 1024 + 1)), isNull);
      });
    },
  );
}

Future<void> _expectRoundTrip(
  String text,
  double side, {
  bool transparent = false,
}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  if (!transparent) canvas.drawColor(Colors.white, BlendMode.src);
  canvas.translate(24, 24);
  QrPainter(
    data: text,
    gapless: true,
    version: QrVersions.auto,
    errorCorrectionLevel: QrErrorCorrectLevel.L,
  ).paint(canvas, Size(side, side));
  final picture = recorder.endRecording();
  final image = await picture.toImage(side.ceil() + 48, side.ceil() + 48);
  try {
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    expect(await decodeQrImage(png!.buffer.asUint8List()), text);
  } finally {
    image.dispose();
    picture.dispose();
  }
}
