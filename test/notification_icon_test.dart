import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/notifications_service.dart';
import 'package:sloth/todo_theme.dart';

/// The status-bar icons are only ever named from Dart strings, so the release
/// resource shrinker sees no reference to them and strips them out of the APK —
/// every launch then fails with `PlatformException(invalid_icon)` and
/// notifications never initialise. `res/raw/keep.xml` is what stops that.
void main() {
  final res = Directory('android/app/src/main/res');

  /// The drawable names the app asks for, e.g. `ic_notification`.
  Set<String> usedIcons() => {
    for (final scheme in TodoColors.all)
      NotificationsService.notificationIconFor(
        scheme,
      ).replaceFirst('@drawable/', ''),
  };

  test('the icons the app names exist in every density bucket', () {
    final names = usedIcons();
    expect(names, hasLength(2), reason: 'light and dark themes differ');

    for (final name in names) {
      final buckets = res
          .listSync()
          .whereType<Directory>()
          .where((d) => d.path.split(Platform.pathSeparator).last.startsWith('drawable-'))
          .where((d) => File('${d.path}/$name.png').existsSync())
          .length;
      expect(buckets, greaterThan(0), reason: '$name.png is missing');
    }
  });

  test('a keep rule protects the icons from the release shrinker', () {
    final keep = File('${res.path}/raw/keep.xml');
    expect(
      keep.existsSync(),
      isTrue,
      reason: 'nothing in Kotlin or XML references the drawable',
    );
    final rules = keep.readAsStringSync();
    for (final name in usedIcons()) {
      expect(
        rules,
        contains('@drawable/$name'),
        reason: '$name is stripped by shrinkResources in release builds',
      );
    }
  });
}
