import '../data/analysis_dto.dart';

/// Navigation payloads passed via `GoRouterState.extra` through the capture →
/// review → analyzing → report flow. Plain classes (no codegen) so each screen
/// can type-check the `extra` it receives and bail to home if it's missing.

/// camera screen — the hive being diagnosed is already chosen.
class CaptureArgs {
  const CaptureArgs({required this.hiveId, required this.hiveName});
  final String hiveId;
  final String hiveName;
}

/// review + analyzing — adds the captured/picked local image path.
class PhotoArgs {
  const PhotoArgs({
    required this.hiveId,
    required this.hiveName,
    required this.imagePath,
  });
  final String hiveId;
  final String hiveName;
  final String imagePath;
}

/// report — the completed (or failed) analysis plus context for the header
/// card. [imagePath] is the local capture shown as the "분석된 사진" thumbnail
/// (the server stores only an S3 object key, not a public URL).
class ReportArgs {
  const ReportArgs({
    required this.analysis,
    required this.hiveName,
    this.imagePath,
  });
  final Analysis analysis;
  final String hiveName;
  final String? imagePath;
}
