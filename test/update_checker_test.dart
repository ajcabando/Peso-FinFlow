import 'dart:convert';

import 'package:finflow/features/updates/data/update_checker.dart';
import 'package:finflow/features/updates/presentation/providers/update_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  group('isNewerVersion', () {
    test('newer minor release wins', () {
      expect(
        UpdateChecker.isNewerVersion(candidate: '0.3.0', current: '0.2.0'),
        isTrue,
      );
    });

    test('numeric comparison, not lexicographic', () {
      expect(
        UpdateChecker.isNewerVersion(candidate: '0.10.0', current: '0.9.9'),
        isTrue,
      );
      expect(
        UpdateChecker.isNewerVersion(candidate: '0.9.0', current: '0.10.0'),
        isFalse,
      );
    });

    test('same version with build metadata is not newer', () {
      expect(
        UpdateChecker.isNewerVersion(candidate: '0.2.0+2', current: '0.2.0'),
        isFalse,
      );
      expect(
        UpdateChecker.isNewerVersion(candidate: 'v0.2.0', current: '0.2.0'),
        isFalse,
      );
    });

    test('older candidate is not newer', () {
      expect(
        UpdateChecker.isNewerVersion(candidate: '0.1.0', current: '0.2.0'),
        isFalse,
      );
      expect(
        UpdateChecker.isNewerVersion(candidate: '1.0.0', current: '1.1.0'),
        isFalse,
      );
    });

    test('major version bump wins', () {
      expect(
        UpdateChecker.isNewerVersion(candidate: '1.0.0', current: '0.9.9'),
        isTrue,
      );
    });
  });

  group('UpdateChecker.check', () {
    test('returns UpdateInfo for a newer release', () async {
      final client = MockClient(
        (request) async {
          expect(request.url.path, endsWith('/releases/latest'));
          return http.Response(
            jsonEncode({
              'tag_name': 'v0.3.0',
              'html_url': 'https://github.com/ajcabando/Peso-FinFlow/releases/tag/v0.3.0',
              'published_at': '2026-09-01T00:00:00Z',
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        },
      );
      final checker = UpdateChecker(httpClient: client);
      final update = await checker.check(currentVersion: '0.2.0');

      expect(update, isNotNull);
      expect(update!.version, '0.3.0');
      expect(update.url, contains('/releases/tag/v0.3.0'));
      expect(update.publishedAt, DateTime.parse('2026-09-01T00:00:00Z'));
    });

    test('returns null when the installed version is already current', () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode({'tag_name': 'v0.2.0', 'html_url': 'https://x/y'}),
          200,
        ),
      );
      final checker = UpdateChecker(httpClient: client);
      final update = await checker.check(currentVersion: '0.2.0');

      expect(update, isNull);
    });

    test('throws UpdateCheckException on a non-200 response', () async {
      final client = MockClient((_) async => http.Response('rate limited', 403));
      final checker = UpdateChecker(httpClient: client);

      expect(
        () => checker.check(currentVersion: '0.2.0'),
        throwsA(isA<UpdateCheckException>()),
      );
    });

    test('throws UpdateCheckException when the body is not JSON', () async {
      final client = MockClient((_) async => http.Response('<html>', 200));
      final checker = UpdateChecker(httpClient: client);

      expect(
        () => checker.check(currentVersion: '0.2.0'),
        throwsA(isA<UpdateCheckException>()),
      );
    });

    test('malformed release maps to null instead of an update', () async {
      final client = MockClient(
        (_) async => http.Response(jsonEncode({'tag_name': ''}), 200),
      );
      final checker = UpdateChecker(httpClient: client);

      expect(await checker.check(currentVersion: '0.2.0'), isNull);
    });
  });

  group('UpdateController', () {
    test('gates the check when the installed version is unknown', () async {
      // PackageInfo is unavailable in tests, so the controller resolves the
      // fallback '0.0.0' and must refuse to check rather than claim every
      // release is newer than an unknown version.
      TestWidgetsFlutterBinding.ensureInitialized();
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final status = await container
          .read(updateControllerProvider.notifier)
          .checkForUpdates();

      expect(status.state, UpdateCheckState.error);
      expect(status.error, contains("Couldn't determine"));
    });
  });
}
