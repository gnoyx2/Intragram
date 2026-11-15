import 'package:file_picker/file_picker.dart';

Future<List<PlatformFile>> pickBrowserPlatformFiles({
  FileType type = FileType.any,
}) => throw UnsupportedError('pickBrowserPlatformFiles is web-only');
