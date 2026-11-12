//
//  ql_image_size.dart — reads width/height from PNG, JPEG, GIF and WebP
//  headers without decoding pixels.
//

import 'dart:io';
import 'dart:typed_data';

(int, int)? qlImageSizeOfFile(String path) {
  try {
    final file = File(path);
    final raf = file.openSync();
    try {
      final length = raf.lengthSync();
      final head = raf.readSync(length < 262144 ? length : 262144);
      return qlImageSize(head);
    } finally {
      raf.closeSync();
    }
  } on FileSystemException {
    return null;
  }
}

(int, int)? qlImageSize(Uint8List b) {
  if (b.length < 24) return null;
  // PNG
  if (b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    final d = ByteData.sublistView(b);
    return (d.getUint32(16), d.getUint32(20));
  }
  // GIF
  if (b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
    return (b[6] | (b[7] << 8), b[8] | (b[9] << 8));
  }
  // WebP
  if (b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
      b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50 &&
      b.length >= 30) {
    final chunk = String.fromCharCodes(b.sublist(12, 16));
    if (chunk == 'VP8X') {
      final w = 1 + (b[24] | (b[25] << 8) | (b[26] << 16));
      final h = 1 + (b[27] | (b[28] << 8) | (b[29] << 16));
      return (w, h);
    }
    if (chunk == 'VP8 ') {
      final w = (b[26] | (b[27] << 8)) & 0x3FFF;
      final h = (b[28] | (b[29] << 8)) & 0x3FFF;
      return (w, h);
    }
    if (chunk == 'VP8L') {
      final bits = b[21] | (b[22] << 8) | (b[23] << 16) | (b[24] << 24);
      return ((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1);
    }
    return null;
  }
  // JPEG
  if (b[0] == 0xFF && b[1] == 0xD8) {
    var i = 2;
    int? orientation;
    while (i + 9 < b.length) {
      if (b[i] != 0xFF) {
        i++;
        continue;
      }
      final marker = b[i + 1];
      if (marker == 0xD8 || marker == 0x01 || (marker >= 0xD0 && marker <= 0xD7)) {
        i += 2;
        continue;
      }
      final len = (b[i + 2] << 8) | b[i + 3];
      if (marker == 0xE1 && orientation == null) {
        orientation = _exifOrientation(b, i + 4, len - 2);
      }
      if ((marker >= 0xC0 && marker <= 0xC3) ||
          (marker >= 0xC5 && marker <= 0xC7) ||
          (marker >= 0xC9 && marker <= 0xCB) ||
          (marker >= 0xCD && marker <= 0xCF)) {
        final h = (b[i + 5] << 8) | b[i + 6];
        final w = (b[i + 7] << 8) | b[i + 8];
        if (orientation != null && orientation >= 5 && orientation <= 8) {
          return (h, w);
        }
        return (w, h);
      }
      i += 2 + len;
    }
  }
  return null;
}

int? _exifOrientation(Uint8List b, int start, int length) {
  try {
    if (start + 14 > b.length) return null;
    if (String.fromCharCodes(b.sublist(start, start + 4)) != 'Exif') return null;
    final tiff = start + 6;
    final little = b[tiff] == 0x49;
    int u16(int o) => little ? b[o] | (b[o + 1] << 8) : (b[o] << 8) | b[o + 1];
    int u32(int o) => little
        ? b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)
        : (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];
    final ifd = tiff + u32(tiff + 4);
    final count = u16(ifd);
    for (var k = 0; k < count; k++) {
      final entry = ifd + 2 + k * 12;
      if (entry + 12 > b.length) return null;
      if (u16(entry) == 0x0112) return u16(entry + 8);
    }
  } on RangeError {
    return null;
  }
  return null;
}
