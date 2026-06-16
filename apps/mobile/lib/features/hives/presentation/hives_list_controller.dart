import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analyses/data/analyses_api.dart';
import '../../auth/presentation/auth_controller.dart';
import '../../auth/presentation/auth_flow_state.dart';
import '../data/hive_dto.dart';
import '../data/hives_repository_impl.dart';
import '../domain/hives_repository.dart';

/// Loads and mutates the current user's hive list.
///
/// `build()` fetches the list, scoped to the signed-in user (see below); the
/// screen renders the [AsyncValue] (loading / error / data). [refresh] re-fetches
/// (pull-to-refresh) without blanking the list. [createHive] / [deleteHive]
/// mutate the server then update local state, and rethrow [AppException] so the
/// screen can show a localized message.
class HivesListController extends AsyncNotifier<List<Hive>> {
  HivesRepository get _repo => ref.read(hivesRepositoryProvider);

  @override
  Future<List<Hive>> build() async {
    // Scope to the signed-in user: when the authenticated user changes
    // (logout / different login) `build` re-runs and the list is re-fetched, so
    // we never show a previous user's hives. This is an accepted hives->auth
    // dependency (session scope), analogous to the documented home->auth one.
    final userId = ref.watch(
      authControllerProvider.select(
        (s) => s is AuthFlowAuthenticated ? s.user.id : null,
      ),
    );
    if (userId == null) return const <Hive>[];
    return _repo.listHives();
  }

  /// Pull-to-refresh: re-fetch while keeping the current list visible.
  /// [AsyncValue.guard] does not emit an intermediate loading state, so the
  /// in-place RefreshIndicator spinner is used instead of a full-screen one.
  Future<void> refresh() async {
    // Home cards show each hive's latest analysis (tier/score) from a separate
    // family provider — refresh those too so a new diagnosis is reflected.
    ref.invalidate(latestAnalysisProvider);
    state = await AsyncValue.guard(() => _repo.listHives());
  }

  /// Creates a hive. Prepends it to the list when one is already loaded;
  /// otherwise re-fetches (never replaces an unknown list with a single item).
  /// Rethrows [AppException] on failure.
  Future<Hive> createHive({
    required String name,
    String? note,
    double? latitude,
    double? longitude,
    String? address,
    DateTime? installedAt,
  }) async {
    final created = await _repo.createHive(
      name: name,
      note: note,
      latitude: latitude,
      longitude: longitude,
      address: address,
      installedAt: installedAt,
    );
    if (state.hasValue) {
      state = AsyncValue.data([created, ...state.requireValue]);
    } else {
      state = await AsyncValue.guard(() => _repo.listHives());
    }
    return created;
  }

  /// Partially updates a hive then replaces it in the loaded list (or re-fetches
  /// if the list isn't loaded). Rethrows [AppException] on failure.
  Future<Hive> updateHive(
    String id, {
    String? name,
    String? note,
    double? latitude,
    double? longitude,
    String? address,
    DateTime? installedAt,
  }) async {
    final updated = await _repo.updateHive(
      id,
      name: name,
      note: note,
      latitude: latitude,
      longitude: longitude,
      address: address,
      installedAt: installedAt,
    );
    if (state.hasValue) {
      state = AsyncValue.data([
        for (final h in state.requireValue) h.id == id ? updated : h,
      ]);
    } else {
      state = await AsyncValue.guard(() => _repo.listHives());
    }
    return updated;
  }

  /// Soft-deletes a hive. Removes it from the loaded list, or re-fetches if the
  /// list is not currently loaded. Rethrows on failure (the row stays on error).
  Future<void> deleteHive(String id) async {
    await _repo.deleteHive(id);
    if (state.hasValue) {
      state = AsyncValue.data(
        state.requireValue.where((h) => h.id != id).toList(growable: false),
      );
    } else {
      state = await AsyncValue.guard(() => _repo.listHives());
    }
  }
}

/// App-wide hive list controller.
final hivesListControllerProvider =
    AsyncNotifierProvider<HivesListController, List<Hive>>(
  HivesListController.new,
);
