import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:zxing2/qrcode.dart';

import 'image_header.dart';

const _maxEncodedBytes = 10 * 1024 * 1024;
const _maxSourcePixels = 16000000;
const _maxDecodeSide = 1600;

// 고른 이미지에서 QR을 못 읽음 (고르기 취소는 null)
final class QrImageUnreadable implements Exception {
  const QrImageUnreadable();
}

Future<String?> pickQrImage() async {
  final files = await FilePicker.pickFiles(type: FileType.image);
  if (files.isEmpty) return null;
  final file = files.first;
  final text = await file.length() > _maxEncodedBytes
      ? null
      : await decodeQrImage(await file.readAsBytes());
  return text ?? (throw const QrImageUnreadable());
}

// Image-based QR reading is also available where camera frame streams are not.
//
// Screenshots and exported images rarely land on an integer number of pixels
// per module. Dense codes (long IGW1 invitations reach version 30+) then drift
// off the sampling grid at the native size, so the same image is retried at a
// few resampled widths and with a second binarizer before giving up.
Future<String?> decodeQrImage(Uint8List encoded) async {
  if (encoded.length > _maxEncodedBytes) return null;
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(encoded);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    final int width, height;
    if (kIsWeb) {
      final dims = probeEncodedImageDimensions(encoded);
      if (dims == null) return null;
      width = dims.width;
      height = dims.height;
    } else {
      width = descriptor.width;
      height = descriptor.height;
    }
    if (width <= 0 || height <= 0 || width * height > _maxSourcePixels) {
      return null;
    }
    final longest = width > height ? width : height;
    final base = longest > _maxDecodeSide ? _maxDecodeSide / longest : 1.0;
    for (final factor in const [1.0, 0.75, 1.5, 0.5, 1.25, 2.0]) {
      final scale = base * factor;
      if (longest * scale > _maxDecodeSide * 1.5 || longest * scale < 64) {
        continue;
      }
      final text = await _decodeScaled(descriptor, width, height, scale);
      if (text != null) return text;
    }
    return null;
  } on Object {
    return null;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}

Future<String?> _decodeScaled(
  ui.ImageDescriptor descriptor,
  int srcW,
  int srcH,
  double s,
) async {
  ui.Codec? codec;
  ui.Image? image;
  try {
    codec = await descriptor.instantiateCodec(
      targetWidth: (srcW * s).round(),
      targetHeight: (srcH * s).round(),
    );
    image = (await codec.getNextFrame()).image;
    final rgba = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    if (rgba == null) return null;
    final luma = Int8List(image.width * image.height);
    for (var i = 0; i < luma.length; i++) {
      final at = i * 4;
      // rawRgba is premultiplied; composite transparent pixels onto white.
      luma[i] =
          (rgba.getUint8(at) * 299 +
                  rgba.getUint8(at + 1) * 587 +
                  rgba.getUint8(at + 2) * 114) ~/
              1000 +
          255 -
          rgba.getUint8(at + 3);
    }
    final source = RGBLuminanceSource.crop(
      luma,
      image.width,
      image.height,
      0,
      0,
      image.width,
      image.height,
    );
    for (final binarizer in [
      HybridBinarizer(source),
      GlobalHistogramBinarizer(source),
    ]) {
      final bitmap = BinaryBitmap(binarizer);
      for (final hint in [
        DecodeHintType.tryHarder,
        // Exported QR images have no perspective; use the exact module grid.
        DecodeHintType.pureBarcode,
      ]) {
        try {
          return QRCodeReader()
              .decode(bitmap, hints: DecodeHints()..put(hint))
              .text;
        } on Object {
          // Try the next strategy.
        }
      }
    }
    return null;
  } finally {
    image?.dispose();
    codec?.dispose();
  }
}
