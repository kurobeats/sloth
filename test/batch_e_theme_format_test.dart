import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/todo_format.dart';
import 'package:sloth/todo_theme.dart';

/// Server colours and date formats were recomputed on every tile and every
/// text build. Both are now memoised; the visible results must not move.
void main() {
  group('F-061 serverColor', () {
    test('repeated identical calls return the identical Color', () {
      for (final (hex, scheme, min) in [
        ('ff0000', TodoColors.gruvboxLight, 3.0),
        ('00ff00', TodoColors.gruvboxLight, 3.5),
        ('1e1e2e', TodoColors.catppuccinMocha, 3.0),
        ('336699', TodoColors.patinaLight, 3.0),
      ]) {
        final first = TodoColors.serverColor(hex, scheme, min: min);
        final second = TodoColors.serverColor(hex, scheme, min: min);
        expect(
          identical(first, second),
          isTrue,
          reason: '$hex on ${scheme.id} @$min must come from the cache',
        );
      }
    });

    test('the memoised results are the values the app already painted', () {
      final fixtures = <(String, TodoColors, double, int)>[
        ('ff0000', TodoColors.gruvboxLight, 3.0, 0xffff0000),
        ('ff0000', TodoColors.gruvboxLight, 3.5, 0xffff0000),
        ('00ff00', TodoColors.gruvboxLight, 3.0, 0xff00a100),
        ('00ff00', TodoColors.gruvboxLight, 3.5, 0xff009100),
        ('1e1e2e', TodoColors.catppuccinMocha, 3.0, 0xff6a6a74),
        ('1e1e2e', TodoColors.catppuccinMocha, 3.5, 0xff787882),
        ('ffffff', TodoColors.catppuccinMocha, 3.0, 0xffffffff),
        ('336699', TodoColors.patinaLight, 3.0, 0xff336699),
        ('#336699', TodoColors.oceanicNext, 3.0, 0xff4775a3),
        ('#336699', TodoColors.oceanicNext, 3.5, 0xff5982ac),
      ];
      for (final (hex, scheme, min, expected) in fixtures) {
        expect(
          TodoColors.serverColor(hex, scheme, min: min).toARGB32(),
          expected,
          reason: '$hex on ${scheme.id} @$min',
        );
        // Twice: the second read is the cached one.
        expect(
          TodoColors.serverColor(hex, scheme, min: min).toARGB32(),
          expected,
          reason: '$hex on ${scheme.id} @$min (cached)',
        );
      }
    });

    test('unset and unparsable colours stay on the accent', () {
      final scheme = TodoColors.gruvboxLight;
      expect(TodoColors.serverColor(null, scheme), scheme.accent);
      expect(TodoColors.serverColor('', scheme), scheme.accent);
      expect(TodoColors.serverColor('not-a-colour', scheme), scheme.accent);
    });

    test('legible is memoised and keeps its contrast guarantee', () {
      const raw = Color(0xFF00FF00);
      final background = TodoColors.gruvboxLight.primaryBackground;
      final first = TodoColors.legible(raw, background, 3.5);
      expect(identical(first, TodoColors.legible(raw, background, 3.5)), isTrue);
      expect(TodoColors.contrast(first, background), greaterThanOrEqualTo(3.5));
      // A colour that already clears the minimum is returned untouched.
      expect(identical(TodoColors.legible(raw, background, 1.0), raw), isTrue);
    });

    test('swatches still come from the scheme accent', () {
      final swatches = TodoColors.swatches(TodoColors.gruvboxLight);
      expect(swatches, contains(TodoColors.gruvboxLight.accent));
      expect(swatches.length, greaterThan(3));
    });
  });

  group('F-062 date formats', () {
    final now = DateTime(2026, 10, 24, 9, 30);

    test('dueLabel keeps its wording', () {
      expect(TodoFormat.dueLabel(DateTime(2026, 10, 24, 17), now: now), 'Today');
      expect(TodoFormat.dueLabel(DateTime(2026, 10, 25), now: now), 'Tomorrow');
      expect(TodoFormat.dueLabel(DateTime(2026, 10, 23), now: now), 'Yesterday');
      expect(TodoFormat.dueLabel(DateTime(2026, 10, 28), now: now), 'Wednesday');
      expect(TodoFormat.dueLabel(DateTime(2026, 12, 1), now: now), 'Tue 1 Dec');
      expect(
        TodoFormat.dueLabel(DateTime(2027, 1, 5), now: now),
        'Tue 5 Jan 2027',
      );
    });

    test('metadataLabel and withTime keep their wording', () {
      expect(
        TodoFormat.metadataLabel(DateTime(2026, 10, 24, 8), now: now),
        'Today',
      );
      expect(
        TodoFormat.metadataLabel(DateTime(2026, 10, 25), now: now),
        'Tomorrow',
      );
      expect(
        TodoFormat.metadataLabel(DateTime(2026, 10, 23), now: now),
        'Yesterday',
      );
      expect(
        TodoFormat.metadataLabel(DateTime(2026, 10, 20), now: now),
        'Tue',
      );
      expect(
        TodoFormat.metadataLabel(DateTime(2026, 11, 20), now: now),
        '20 Nov',
      );
      expect(
        TodoFormat.metadataLabel(DateTime(2027, 11, 20), now: now),
        '20 Nov 2027',
      );
      final today = DateTime.now();
      expect(
        TodoFormat.withTime(DateTime(today.year, today.month, today.day, 17, 5)),
        'Today, 17:05',
      );
    });

    test('created and groupHeader keep their wording', () {
      expect(TodoFormat.created(DateTime(2026, 10, 24)), 'Created 24 Oct 2026');
      expect(TodoFormat.created(null), '');
      final today = DateTime.now();
      expect(
        TodoFormat.groupHeader(DateTime(today.year, today.month, today.day)),
        'Today',
      );
      expect(TodoFormat.groupHeader(DateTime(2026, 10, 20)), 'Tuesday 20 Oct');
      expect(TodoFormat.groupHeader(null), 'No due date');
    });
  });
}
