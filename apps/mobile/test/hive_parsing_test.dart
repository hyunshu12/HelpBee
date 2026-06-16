// Unit tests for the hand-written Hive DTO parsing (no freezed/json codegen).
// Highest-risk piece: lat/lng arrive as STRINGS from the backend.

import 'package:flutter_test/flutter_test.dart';

import 'package:helpbee/features/hives/data/hive_dto.dart';

void main() {
  group('Hive.fromJson', () {
    test('parses a full payload, string lat/lng -> double', () {
      final h = Hive.fromJson({
        'id': 'h1',
        'userId': 'u1',
        'name': '양봉장 1호',
        'note': null,
        'latitude': '37.491200',
        'longitude': '127.487600',
        'address': '경기도 양평군',
        'installedAt': '2026-03-01T00:00:00.000Z',
        'createdAt': '2026-06-16T00:00:00.000Z',
        'updatedAt': '2026-06-16T00:00:00.000Z',
        'deletedAt': null,
      });
      expect(h.id, 'h1');
      expect(h.name, '양봉장 1호');
      expect(h.latitude, closeTo(37.4912, 1e-9));
      expect(h.longitude, closeTo(127.4876, 1e-9));
      expect(h.hasLocation, isTrue);
      expect(h.address, '경기도 양평군');
      expect(h.installedAt, isNotNull);
      expect(h.deletedAt, isNull);
    });

    test('tolerates null/absent coordinates and optional fields', () {
      final h = Hive.fromJson({
        'id': 'h2',
        'userId': 'u1',
        'name': '벌통',
        'latitude': null,
        'longitude': null,
        'createdAt': '2026-06-16T00:00:00Z',
        'updatedAt': '2026-06-16T00:00:00Z',
      });
      expect(h.latitude, isNull);
      expect(h.longitude, isNull);
      expect(h.hasLocation, isFalse);
      expect(h.note, isNull);
      expect(h.address, isNull);
      expect(h.installedAt, isNull);
    });

    test('accepts numeric coordinates too', () {
      final h = Hive.fromJson({
        'id': 'h3',
        'userId': 'u1',
        'name': 'n',
        'latitude': 37.5,
        'longitude': 127.0,
        'createdAt': '2026-06-16T00:00:00Z',
        'updatedAt': '2026-06-16T00:00:00Z',
      });
      expect(h.latitude, 37.5);
      expect(h.longitude, 127.0);
    });
  });

  test('HiveDeletion.fromJson parses id + deletedAt', () {
    final d = HiveDeletion.fromJson({
      'id': 'h1',
      'deletedAt': '2026-06-16T01:00:00Z',
    });
    expect(d.id, 'h1');
    expect(d.deletedAt, isNotNull);
  });

  test('Hive value equality holds for identical payloads', () {
    Map<String, dynamic> base() => {
          'id': 'h1',
          'userId': 'u1',
          'name': 'n',
          'createdAt': '2026-06-16T00:00:00Z',
          'updatedAt': '2026-06-16T00:00:00Z',
        };
    expect(Hive.fromJson(base()), Hive.fromJson(base()));
    expect(Hive.fromJson(base()).hashCode, Hive.fromJson(base()).hashCode);
  });
}
