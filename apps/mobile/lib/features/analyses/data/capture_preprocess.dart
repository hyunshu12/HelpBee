import 'dart:io';
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

/// API `sharp` `limitInputPixels` (50 MP). Bigger inputs are rejected at
/// confirm, so cap the long side beforehand (M4).
const int maxInputPixels = 50 * 1000 * 1000;
const int pixelCapLongSide = 7000; // 7000×5250 ≈ 36.8 MP < 50 MP for 4:3

/// A bound large enough to never shrink phone photos (flutter_image_compress
/// treats minWidth/minHeight as an upper box, keeping aspect ratio).
const int _noDownscaleBox = 100000;

/// Pure policy: the box (long-side bound) to use given the encoded size of
/// the no-downscale attempt. Tested without platform channels.
int uploadBoxForBytes(int bytes) =>
    bytes > uploadMaxBytes ? downscaleLongSide : _noDownscaleBox;

/// Pure policy: initial box from the source pixel count (≤ 50 MP passes
/// through untouched; above it the long side is capped so the API accepts it).
int uploadBoxForPixels(int? width, int? height) {
  if (width == null || height == null) return _noDownscaleBox;
  return width * height > maxInputPixels ? pixelCapLongSide : _noDownscaleBox;
}

/// Minimal JPEG SOF parser → (width, height). Returns null for non-JPEG
/// (e.g. HEIC) or malformed data; callers then skip the pixel guard.
(int, int)? jpegDimensions(Uint8List b) {
  if (b.length < 4 || b[0] != 0xFF || b[1] != 0xD8) return null;
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    if (marker == 0xD8 ||
        (marker >= 0xD0 && marker <= 0xD7) ||
        marker == 0x01) {
      i += 2;
      continue;
    }
    final len = (b[i + 2] << 8) | b[i + 3];
    final isSof =
        (marker >= 0xC0 && marker <= 0xCF) &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isSof) {
      final h = (b[i + 5] << 8) | b[i + 6];
      final w = (b[i + 7] << 8) | b[i + 8];
      return (w, h);
    }
    if (marker == 0xDA) return null; // start of scan without SOF
    i += 2 + len;
  }
  return null;
}

/// Prepares a captured/picked image for upload (spec v2.2 §8 / mobile
/// CLAUDE.md §8.2): **no downscale**, JPEG quality 95, **EXIF stripped**
/// (incl. GPS) with orientation baked in, HEIC→JPEG handled natively by the
/// platform codec. Only if the result exceeds 10 MB is the long side reduced
/// to 4000 px (a 12 MP JPEG q95 is normally 4–7 MB).
///
/// Returns JPEG bytes; upload with `Content-Type: image/jpeg`.
Future<Uint8List> preprocessForUpload(String path) async {
  // M4: ≤ 50 MP guard from the source JPEG header (HEIC: unknown → no guard).
  int box = _noDownscaleBox;
  try {
    final head = await _readHead(path, 256 * 1024);
    final dims = jpegDimensions(head);
    box = uploadBoxForPixels(dims?.$1, dims?.$2);
  } catch (_) {
    // 헤더를 못 읽으면 가드 없이 진행(플랫폼 코덱이 처리).
  }
  Uint8List? out = await _encode(path, box);
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

Future<Uint8List> _readHead(String path, int max) async {
  final f = File(path);
  final len = await f.length();
  final n = len < max ? len : max;
  final raf = await f.open();
  try {
    return await raf.read(n);
  } finally {
    await raf.close();
  }
}

/// I1: persist the exact uploaded bytes so the report can crop evidence
/// regions (server coordinates refer to the UPLOADED image, which may be
/// downscaled). Returns the temp file path.
Future<String> saveUploadedCopy(Uint8List bytes) async {
  final dir = Directory.systemTemp;
  final f = File(
    '${dir.path}/helpbee_upload_${DateTime.now().millisecondsSinceEpoch}.jpg',
  );
  await f.writeAsBytes(bytes, flush: true);
  return f.path;
}
