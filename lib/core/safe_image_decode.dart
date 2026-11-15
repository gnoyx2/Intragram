import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;

import 'browser_received_files.dart';
import 'image_header.dart';

Future<bool> isSafeToDecodeImage(
  String filePath, {
  int maxPixels = 50000000,
  int maxFileBytes = 50 * 1024 * 1024,
}) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  try {
    final browserBytes = BrowserReceivedFiles.read(filePath);
    if (browserBytes != null) {
      if (browserBytes.length > maxFileBytes) return false;
      if (kIsWeb) {
        final dims = probeEncodedImageDimensions(browserBytes);
        return dims != null && dims.width * dims.height <= maxPixels;
      }
      buffer = await ui.ImmutableBuffer.fromUint8List(browserBytes);
    } else {
      if (kIsWeb || await File(filePath).length() > maxFileBytes) return false;
      buffer = await ui.ImmutableBuffer.fromFilePath(filePath);
    }
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    return descriptor.width > 0 &&
        descriptor.height > 0 &&
        descriptor.width * descriptor.height <= maxPixels;
  } on Object {
    return false;
  } finally {
    descriptor?.dispose();
    buffer?.dispose();
  }
}
