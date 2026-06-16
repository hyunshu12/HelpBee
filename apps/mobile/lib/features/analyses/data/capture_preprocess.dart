import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

/// Thrown when an image can't be decoded/compressed (corrupt / unsupported).
class ImagePreprocessException implements Exception {
  const ImagePreprocessException();
}

/// Prepares a captured/picked image for upload (mobile CLAUDE.md §8.2):
/// downscale so the longest side ≲1920, JPEG quality 85, **EXIF stripped**
/// (incl. GPS) with orientation baked in. Handles iOS HEIC inputs natively.
///
/// Returns JPEG bytes; upload with `Content-Type: image/jpeg`.
///
/// `flutter_image_compress` treats minWidth/minHeight as an upper bound: the
/// image is scaled down to fit within that box keeping aspect ratio. `keepExif:
/// false` drops all metadata (privacy) after applying the orientation.
Future<Uint8List> preprocessForUpload(String path) async {
  final Uint8List? out = await FlutterImageCompress.compressWithFile(
    path,
    minWidth: 1920,
    minHeight: 1920,
    quality: 85,
    format: CompressFormat.jpeg,
    keepExif: false,
  );
  if (out == null || out.isEmpty) {
    throw const ImagePreprocessException();
  }
  return out;
}
