import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_test/flutter_test.dart';
import 'package:intragram/core/private_dir.dart';
import 'package:intragram/network/web_chat_storage.dart';
import 'package:intragram/network/web_stream_io.dart';

class _Picker extends FilePickerPlatform {
  _Picker(this.path);
  final String path;
  int asked = 0;

  @override
  Future<String?> getDirectoryPath({
    String? dialogTitle,
    String? initialDirectory,
    AndroidOptions androidOptions = const AndroidOptions(),
    WindowsOptions windowsOptions = const WindowsOptions(),
    LinuxOptions linuxOptions = const LinuxOptions(),
    WebOptions webOptions = const WebOptions(),
  }) async {
    asked++;
    return path;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support, dir;
  setUpAll(() async {
    support = Directory.systemTemp.createTempSync('intragram_web_folder_app_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.flutter.io/path_provider'),
          (_) async => support.path,
        );
    await privateAppDir();
    dir = Directory.systemTemp.createTempSync('intragram_web_folder_');
  });
  tearDownAll(() {
    support.deleteSync(recursive: true);
    dir.deleteSync(recursive: true);
  });

  test(
    'WebRTC native receives ask for a folder once per run, like v7',
    () async {
      final picker = _Picker(dir.path);
      FilePickerPlatform.instance = picker;
      Future<void> receive(String name) async {
        final sink = await openWebReceiveSink(name, 3, wanted: () => true);
        await sink!.write(Uint8List.fromList([1, 2, 3]));
        expect(await sink.commit(wanted: () => true), isNotNull);
      }

      await receive('a.bin');
      await receive('b.bin');
      expect(picker.asked, 1);
      // Bridge disposal (panic, lock, shutdown) forgets the folder.
      clearWebReceived();
      await receive('c.bin');
      expect(picker.asked, 2);
      expect(File('${dir.path}/b.bin').readAsBytesSync(), [1, 2, 3]);
    },
  );
}
