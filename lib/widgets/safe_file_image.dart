import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intragram/core/os_privacy.dart';
import 'package:intragram/core/safe_image_decode.dart';
import 'package:intragram/core/browser_received_files.dart';

class SafeFileImage extends StatefulWidget {
  const SafeFileImage({
    required this.path,
    required this.fit,
    required this.placeholder,
    this.width,
    this.height,
    super.key,
  });

  final String path;
  final BoxFit fit;
  final Widget placeholder;
  final int? width;
  final int? height;

  @override
  State<SafeFileImage> createState() => _SafeFileImageState();
}

class _SafeFileImageState extends State<SafeFileImage> {
  late Future<bool> _safe = isSafeToDecodeImage(widget.path);
  late ImageProvider? _image = _provider();

  ImageProvider? _provider() {
    final bytes = BrowserReceivedFiles.read(widget.path);
    if (bytes != null) return MemoryImage(bytes);
    return kIsWeb ? null : FileImage(File(widget.path));
  }

  @override
  void didUpdateWidget(SafeFileImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      _safe = isSafeToDecodeImage(widget.path);
      _image = _provider();
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<bool>(
    future: _safe,
    builder: (context, snapshot) {
      final image = _image;
      if (snapshot.connectionState != ConnectionState.done ||
          snapshot.data != true ||
          image == null) {
        return widget.placeholder;
      }
      return Image(
        image: OsPrivacy.trackImage(
          widget.path,
          ResizeImage(
            image,
            width: widget.width,
            height: widget.height,
            policy: ResizeImagePolicy.fit,
          ),
        ),
        fit: widget.fit,
        errorBuilder: (_, _, _) => widget.placeholder,
      );
    },
  );
}
