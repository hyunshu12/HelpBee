// Unit tests for the hand-written auth DTO parsing and the wire→ErrorCode map.
// These are the highest-risk hand-written pieces (no freezed/json codegen).

import 'package:flutter_test/flutter_test.dart';

import 'package:helpbee/core/errors/error_code.dart';
import 'package:helpbee/features/auth/data/auth_dto.dart';

void main() {
  group('PublicUser.fromJson', () {
    test('parses a full payload', () {
      final u = PublicUser.fromJson({
        'id': 'u1',
        'email': 'a@b.com',
        'name': '엄로이',
        'role': 'admin',
        'emailVerified': true,
        'createdAt': '2026-06-11T00:00:00.000Z',
      });
      expect(u.id, 'u1');
      expect(u.email, 'a@b.com');
      expect(u.name, '엄로이');
      expect(u.isAdmin, isTrue);
      expect(u.emailVerified, isTrue);
      expect(u.createdAt.isUtc, isTrue);
    });

    test('applies safe defaults for missing role/emailVerified', () {
      final u = PublicUser.fromJson({
        'id': 'u2',
        'email': 'c@d.com',
        'name': 'kim',
        'createdAt': '2026-01-01T00:00:00Z',
      });
      expect(u.role, 'user');
      expect(u.isAdmin, isFalse);
      expect(u.emailVerified, isFalse);
    });
  });

  group('AuthSession.fromAuthData (FLAT envelope)', () {
    test('reshapes flat { user, accessToken, refreshToken, expiresIn }', () {
      final s = AuthSession.fromAuthData({
        'user': {
          'id': 'u1',
          'email': 'a@b.com',
          'name': 'n',
          'role': 'user',
          'emailVerified': false,
          'createdAt': '2026-06-11T00:00:00Z',
        },
        'accessToken': 'access-xyz',
        'refreshToken': 'refresh-abc',
        'expiresIn': 900,
      });
      expect(s.user.email, 'a@b.com');
      expect(s.tokens.accessToken, 'access-xyz');
      expect(s.tokens.refreshToken, 'refresh-abc');
      expect(s.tokens.expiresIn, 900);
    });

    test('defaults expiresIn to 900 when absent', () {
      final s = AuthSession.fromAuthData({
        'user': {'id': 'u', 'email': 'e@e.com', 'name': 'n', 'createdAt': '2026-01-01T00:00:00Z'},
        'accessToken': 'a',
        'refreshToken': 'r',
      });
      expect(s.tokens.expiresIn, 900);
    });
  });

  test('MeResult.fromJson parses nested user + subscription', () {
    final me = MeResult.fromJson({
      'user': {'id': 'u', 'email': 'e@e.com', 'name': 'n', 'createdAt': '2026-01-01T00:00:00Z'},
      'subscription': {'plan': 'free', 'status': 'active'},
    });
    expect(me.user.id, 'u');
    expect(me.subscription.plan, 'free');
    expect(me.subscription.status, 'active');
  });

  group('errorCodeFromWire', () {
    test('maps known backend codes', () {
      expect(errorCodeFromWire('AUTH_INVALID_CREDENTIALS'), ErrorCode.authInvalidCredentials);
      expect(errorCodeFromWire('QUOTA_EXCEEDED'), ErrorCode.quotaExceeded);
      expect(errorCodeFromWire('AUTH_EMAIL_NOT_VERIFIED'), ErrorCode.authEmailNotVerified);
    });

    test('falls back to unknown for null / unrecognized', () {
      expect(errorCodeFromWire(null), ErrorCode.unknown);
      expect(errorCodeFromWire('SOMETHING_NEW'), ErrorCode.unknown);
    });
  });
}
