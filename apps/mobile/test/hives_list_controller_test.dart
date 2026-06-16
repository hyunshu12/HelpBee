// Controller tests for HivesListController — locks in the optimistic-update
// guards (create/delete must NOT discard an unknown list) and user-scoped build.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:helpbee/core/errors/app_exception.dart';
import 'package:helpbee/core/errors/error_code.dart';
import 'package:helpbee/features/auth/data/auth_dto.dart';
import 'package:helpbee/features/auth/presentation/auth_controller.dart';
import 'package:helpbee/features/auth/presentation/auth_flow_state.dart';
import 'package:helpbee/features/hives/data/hive_dto.dart';
import 'package:helpbee/features/hives/data/hives_repository_impl.dart';
import 'package:helpbee/features/hives/domain/hives_repository.dart';
import 'package:helpbee/features/hives/presentation/hives_list_controller.dart';

Hive _hive(String id, {String name = 'h'}) => Hive(
      id: id,
      userId: 'u1',
      name: name,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

class _FakeRepo implements HivesRepository {
  _FakeRepo(this._list, {this.failList = false});

  List<Hive> _list;
  bool failList;

  @override
  Future<List<Hive>> listHives({int? limit, int? offset}) async {
    if (failList) throw const AppException(ErrorCode.serverError);
    return List<Hive>.from(_list);
  }

  @override
  Future<Hive> createHive({
    required String name,
    String? note,
    double? latitude,
    double? longitude,
    String? address,
    DateTime? installedAt,
  }) async {
    final h = _hive('new', name: name);
    _list = [..._list, h]; // the server now holds it
    return h;
  }

  @override
  Future<void> deleteHive(String id) async {
    _list = _list.where((h) => h.id != id).toList();
  }

  @override
  Future<Hive> getHive(String id) async =>
      _list.firstWhere((h) => h.id == id);

  @override
  Future<Hive> updateHive(
    String id, {
    String? name,
    String? note,
    double? latitude,
    double? longitude,
    String? address,
    DateTime? installedAt,
  }) async =>
      _hive(id);
}

/// Auth stub fixed to an authenticated user (so hive build() is user-scoped).
class _AuthedController extends AuthController {
  @override
  AuthFlowState build() => AuthFlowState.authenticated(
        PublicUser(
          id: 'u1',
          email: 'a@b.com',
          name: 'n',
          createdAt: DateTime.utc(2026),
        ),
      );
}

ProviderContainer _container(HivesRepository repo) {
  final c = ProviderContainer(
    // Disable Riverpod 3.x auto-retry so a thrown build() settles to a
    // deterministic error state instead of retrying forever in the test.
    retry: (_, _) => null,
    overrides: [
      hivesRepositoryProvider.overrideWithValue(repo),
      authControllerProvider.overrideWith(_AuthedController.new),
    ],
  );
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('build loads the list for the signed-in user', () async {
    final c = _container(_FakeRepo([_hive('a'), _hive('b')]));
    final list = await c.read(hivesListControllerProvider.future);
    expect(list.map((h) => h.id), ['a', 'b']);
  });

  test('createHive prepends when the list is already loaded', () async {
    final c = _container(_FakeRepo([_hive('a')]));
    await c.read(hivesListControllerProvider.future);

    final created =
        await c.read(hivesListControllerProvider.notifier).createHive(name: '새 벌통');
    expect(created.name, '새 벌통');

    final state = c.read(hivesListControllerProvider).requireValue;
    expect(state.first.id, 'new'); // prepended
    expect(state.length, 2);
  });

  test('createHive from an error state re-fetches (never discards the real list)',
      () async {
    final repo = _FakeRepo([_hive('a'), _hive('b')], failList: true);
    final c = _container(repo);

    await expectLater(
      c.read(hivesListControllerProvider.future),
      throwsA(isA<AppException>()),
    );
    expect(c.read(hivesListControllerProvider).hasError, isTrue);

    // Recover: creating must show the FULL server list, not just the new item.
    repo.failList = false;
    await c.read(hivesListControllerProvider.notifier).createHive(name: 'x');

    final state = c.read(hivesListControllerProvider).requireValue;
    expect(state.length, 3);
    expect(state.map((h) => h.id).toSet(), {'a', 'b', 'new'});
  });

  test('deleteHive removes the row from the loaded list', () async {
    final c = _container(_FakeRepo([_hive('a'), _hive('b')]));
    await c.read(hivesListControllerProvider.future);

    await c.read(hivesListControllerProvider.notifier).deleteHive('a');

    final state = c.read(hivesListControllerProvider).requireValue;
    expect(state.map((h) => h.id), ['b']);
  });
}
