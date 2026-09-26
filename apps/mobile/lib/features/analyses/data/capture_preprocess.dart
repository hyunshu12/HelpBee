import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Thrown when an image can't be decoded/compressed (corrupt / unsupported).
class ImagePreprocessException implements Exception {
  const ImagePreprocessException();
}

/// Upload size cap (API allowlist ≤ 10 MB). Above it we downscale the long
/// side to [downscaleLongSide]; below it the ORIGINAL resolution is kept
/// (spec v2.2 §8: two-stage 판독은 원본 해상도가 필요하다).
const int uploadMaxBytes = 10 * 1024 * 1024;
const int downscaleLongSide = 4000;

/// A bound large enough to never shrink phone photos (flutter_image_compress
/// treats minWidth/minHeight as an upper box, keeping aspect ratio).
const int _noDownscaleBox = 100000;

/// Pure policy: the box (long-side bound) to use given the encoded size of
/// the no-downscale attempt. Tested without platform channels.
int uploadBoxForBytes(int bytes) =>
    bytes > uploadMaxBytes ? downscaleLongSide : _noDownscaleBox;

/// Prepares a captured/picked image for upload (spec v2.2 §8 / mobile
/// CLAUDE.md §8.2): **no downscale**, JPEG quality 95, **EXIF stripped**
/// (incl. GPS) with orientation baked in, HEIC→JPEG handled natively by the
/// platform codec. Only if the result exceeds 10 MB is the long side reduced
/// to 4000 px (a 12 MP JPEG q95 is normally 4–7 MB).
///
/// Returns JPEG bytes; upload with `Content-Type: image/jpeg`.
Future<Uint8List> preprocessForUpload(String path) async {
  Uint8List? out = await _encode(path, _noDownscaleBox);
  if (out != null && uploadBoxForBytes(out.length) != _noDownscaleBox) {
    out = await _encode(path, downscaleLongSide);
  }
  if (out == null || out.isEmpty) {
    throw const ImagePreprocessException();
  }
  return out;
}

Future<Uint8List?> _encode(String path, int box) =>
    FlutterImageCompress.compressWithFile(
      path,
      minWidth: box,
      minHeight: box,
      quality: 95,
      format: CompressFormat.jpeg,
      keepExif: false,
    );
