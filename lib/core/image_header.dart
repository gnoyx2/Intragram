import 'dart:typed_data';

({int width, int height})? probeEncodedImageDimensions(Uint8List bytes) {
  if (bytes.length < 4) return null;
  final dims =
      _probePng(bytes) ??
      _probeJpeg(bytes) ??
      _probeGif(bytes) ??
      _probeWebp(bytes) ??
      _probeBmp(bytes);
  if (dims == null || dims.width <= 0 || dims.height <= 0) return null;
  return dims;
}

({int width, int height})? _probePng(Uint8List b) {
  if (b.length < 24 ||
      b[0] != 0x89 ||
      b[1] != 0x50 ||
      b[2] != 0x4E ||
      b[3] != 0x47 ||
      b[4] != 0x0D ||
      b[5] != 0x0A ||
      b[6] != 0x1A ||
      b[7] != 0x0A ||
      b[12] != 0x49 ||
      b[13] != 0x48 ||
      b[14] != 0x44 ||
      b[15] != 0x52) {
    return null;
  }
  final bd = ByteData.sublistView(b);
  final w = bd.getUint32(16), h = bd.getUint32(20);
  if (w > 0x7fffffff || h > 0x7fffffff) return null;
  return (width: w, height: h);
}

({int width, int height})? _probeGif(Uint8List b) {
  if (b.length < 10 ||
      b[0] != 0x47 ||
      b[1] != 0x49 ||
      b[2] != 0x46 ||
      b[3] != 0x38 ||
      (b[4] != 0x37 && b[4] != 0x39) ||
      b[5] != 0x61) {
    return null;
  }
  final bd = ByteData.sublistView(b);
  return (
    width: bd.getUint16(6, Endian.little),
    height: bd.getUint16(8, Endian.little),
  );
}

({int width, int height})? _probeBmp(Uint8List b) {
  if (b.length < 22 || b[0] != 0x42 || b[1] != 0x4D) return null;
  final bd = ByteData.sublistView(b);
  final dib = bd.getUint32(14, Endian.little);
  if (dib == 12) {
    return (
      width: bd.getUint16(18, Endian.little),
      height: bd.getUint16(20, Endian.little),
    );
  }
  if (dib >= 40 && b.length >= 26) {
    final w = bd.getInt32(18, Endian.little);
    final rawH = bd.getInt32(22, Endian.little);
    if (w <= 0 || rawH == -0x80000000) return null;
    return (width: w, height: rawH.abs());
  }
  return null;
}

({int width, int height})? _probeWebp(Uint8List b) {
  if (b.length < 30 ||
      b[0] != 0x52 ||
      b[1] != 0x49 ||
      b[2] != 0x46 ||
      b[3] != 0x46 ||
      b[8] != 0x57 ||
      b[9] != 0x45 ||
      b[10] != 0x42 ||
      b[11] != 0x50 ||
      b[12] != 0x56 ||
      b[13] != 0x50 ||
      b[14] != 0x38) {
    return null;
  }
  final bd = ByteData.sublistView(b);
  if (b[15] == 0x20 && b[23] == 0x9D && b[24] == 0x01 && b[25] == 0x2A) {
    return (
      width: bd.getUint16(26, Endian.little) & 0x3FFF,
      height: bd.getUint16(28, Endian.little) & 0x3FFF,
    );
  }
  if (b[15] == 0x4C && b[20] == 0x2F) {
    final bits = bd.getUint32(21, Endian.little);
    return (width: (bits & 0x3FFF) + 1, height: ((bits >> 14) & 0x3FFF) + 1);
  }
  if (b[15] == 0x58) {
    return (
      width: (b[24] | (b[25] << 8) | (b[26] << 16)) + 1,
      height: (b[27] | (b[28] << 8) | (b[29] << 16)) + 1,
    );
  }
  return null;
}

({int width, int height})? _probeJpeg(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 1 < b.length) {
    if (b[i] != 0xFF) return null;
    while (i < b.length && b[i] == 0xFF) {
      i++;
    }
    if (i >= b.length) return null;
    final marker = b[i++];
    if (marker == 0xD9 || marker == 0xDA) return null;
    if (marker == 0x01 || (marker >= 0xD0 && marker <= 0xD8)) continue;
    if (i + 1 >= b.length) return null;
    final segLen = (b[i] << 8) | b[i + 1];
    if (segLen < 2 || i + segLen > b.length) return null;
    if (marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC) {
      if (segLen < 7) return null;
      return (
        width: (b[i + 5] << 8) | b[i + 6],
        height: (b[i + 3] << 8) | b[i + 4],
      );
    }
    i += segLen;
  }
  return null;
}
