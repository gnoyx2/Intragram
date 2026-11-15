import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'browser_received_files.dart';

abstract final class BrowserClipboard {
  static bool get canRead =>
      web.window.isSecureContext &&
      web.window.navigator.has('clipboard') &&
      web.window.navigator.clipboard.has('read');

  // These methods are called only from explicit paste actions. Browsers cannot
  // safely inspect image/file availability without reading clipboard contents.
  static Future<Uint8List?> readImage() async {
    if (!canRead) return null;
    final items = await web.window.navigator.clipboard.read().toDart;
    for (final item in items.toDart) {
      final types = item.types.toDart.map((type) => type.toDart);
      final mime =
          types.where((type) => type == 'image/png').firstOrNull ??
          types.where((type) => type.startsWith('image/')).firstOrNull;
      if (mime == null) continue;
      final blob = await item.getType(mime).toDart;
      if (blob.size > 20 * 1024 * 1024) return null;
      return Uint8List.view((await blob.arrayBuffer().toDart).toDart);
    }
    return null;
  }

  static Future<List<String>> readFiles() async {
    if (!canRead) return [];
    final items = await web.window.navigator.clipboard.read().toDart;
    final paths = <String>[];
    var total = 0;
    try {
      for (final item in items.toDart.take(100)) {
        final mime = item.types.toDart
            .map((type) => type.toDart)
            .where((type) => !type.startsWith('text/'))
            .firstOrNull;
        if (mime == null) continue;
        final blob = await item.getType(mime).toDart;
        total += blob.size;
        if (total > 100 * 1024 * 1024) throw StateError('clipboard too large');
        final bytes = Uint8List.view((await blob.arrayBuffer().toDart).toDart);
        final suffix = switch (mime) {
          'image/png' => 'png',
          'image/jpeg' => 'jpg',
          'image/webp' => 'webp',
          'image/gif' => 'gif',
          _ => 'bin',
        };
        paths.add(
          BrowserReceivedFiles.put(
            'clipboard-${paths.length + 1}.$suffix',
            bytes,
          ),
        );
      }
      return paths;
    } on Object {
      for (final path in paths) {
        BrowserReceivedFiles.remove(path);
      }
      rethrow;
    }
  }
}
