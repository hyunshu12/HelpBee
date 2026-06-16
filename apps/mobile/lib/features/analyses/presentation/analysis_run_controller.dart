import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/analyses_api.dart';
import '../data/analysis_dto.dart';
import '../data/capture_preprocess.dart';
import '../data/images_api.dart';

/// Input for one diagnosis run. A record so the [runAnalysisProvider] family
/// caches by value — the same (hiveId, imagePath) is executed exactly once even
/// if the analyzing screen rebuilds (prevents a duplicate upload + re-charge).
typedef AnalysisRequest = ({String hiveId, String imagePath});

/// Runs the full pipeline for the 분석중 screen and returns the resulting
/// [Analysis] (which may have `status: 'failed'` — a graceful 200 the report
/// screen renders, not an error):
///
///   preprocess(JPEG, EXIF-stripped) → presign → S3 PUT → confirm → create
///
/// Thrown [AppException]s (network / quota / email-not-verified / image errors)
/// before `create` surface as the provider's error state. On success the per-hive
/// caches are invalidated so the home card + detail timeline reflect the result.
final runAnalysisProvider = FutureProvider.autoDispose
    .family<Analysis, AnalysisRequest>((ref, req) async {
      final images = ref.read(imagesApiProvider);

      final bytes = await preprocessForUpload(req.imagePath);
      final presign = await images.presign(
        filename: 'hive-capture.jpg',
        contentType: 'image/jpeg',
      );
      await images.uploadToS3(
        uploadUrl: presign.uploadUrl,
        bytes: bytes,
        contentType: 'image/jpeg',
      );
      final image = await images.confirm(
        objectKey: presign.objectKey,
        hiveId: req.hiveId,
        capturedAt: DateTime.now(),
      );
      final analysis = await ref
          .read(analysesApiProvider)
          .create(hiveId: req.hiveId, imageId: image.id);

      ref.invalidate(latestAnalysisProvider(req.hiveId));
      ref.invalidate(hiveAnalysesProvider(req.hiveId));
      return analysis;
    });
