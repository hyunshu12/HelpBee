import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/hive_dto.dart';
import '../data/hives_repository_impl.dart';

/// Fetches a single hive by id (detail screen), keyed by hive id.
///
/// `autoDispose` so the cached hive is discarded once the detail screen is
/// popped — this avoids serving a stale (or just-deleted) hive on re-open, and
/// avoids accumulating one cached entry per visited hive / across users.
/// Refetch a live one with `ref.invalidate(hiveDetailProvider(id))`.
final hiveDetailProvider = FutureProvider.autoDispose.family<Hive, String>(
  (ref, id) => ref.read(hivesRepositoryProvider).getHive(id),
);
