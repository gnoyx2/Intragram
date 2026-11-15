import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:share_plus/share_plus.dart' show XFile;
import 'package:web/web.dart' as web;

const int _kSliceBytes = 64 * 1024;

Future<List<PlatformFile>> pickBrowserPlatformFiles({
  FileType type = FileType.any,
}) {
  final completer = Completer<List<PlatformFile>>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..multiple = true
    ..accept = switch (type) {
      FileType.image => 'image/*',
      FileType.audio => 'audio/*',
      FileType.video => 'video/*',
      FileType.media => 'image/*,video/*',
      _ => '',
    }
    ..style.display = 'none';
  var settled = false;
  late final JSFunction onChange;
  late final JSFunction onCancel;
  void cleanup() {
    input.removeEventListener('change', onChange);
    input.removeEventListener('cancel', onCancel);
    input.remove();
  }

  onChange = ((web.Event _) {
    if (settled) return;
    settled = true;
    final list = input.files;
    final out = <PlatformFile>[];
    if (list != null) {
      for (var i = 0; i < list.length; i++) {
        final item = list.item(i);
        if (item != null) out.add(_BrowserPickedPlatformFile(item));
      }
    }
    cleanup();
    completer.complete(out);
  }).toJS;
  onCancel = ((web.Event _) {
    if (settled) return;
    settled = true;
    cleanup();
    completer.complete(const <PlatformFile>[]);
  }).toJS;
  input.addEventListener('change', onChange);
  input.addEventListener('cancel', onCancel);
  web.document.body?.appendChild(input);
  input.click();
  return completer.future;
}

final class _BrowserPickedPlatformFile extends PlatformFile {
  _BrowserPickedPlatformFile(this._file);

  final web.File _file;

  @override
  String get name => _file.name;

  @override
  Uri get uri => Uri();

  @override
  XFile get xFile => XFile.fromData(Uint8List(0), name: name);

  @override
  int? lengthSync() => _file.size;

  @override
  Future<int> length() async => _file.size;

  @override
  Future<Uint8List> readAsBytes() async {
    final buffer = await _file.arrayBuffer().toDart;
    return buffer.toDart.asUint8List();
  }

  @override
  Stream<Uint8List> readAsByteStream() async* {
    final total = _file.size;
    for (var offset = 0; offset < total; offset += _kSliceBytes) {
      final end = offset + _kSliceBytes < total ? offset + _kSliceBytes : total;
      final buffer = await _file.slice(offset, end).arrayBuffer().toDart;
      yield buffer.toDart.asUint8List();
    }
  }
}
