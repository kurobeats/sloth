import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/todo_theme.dart';

/// `buildTodoTheme` runs on every app-shell rebuild and generates a whole M3
/// palette from the seed colour, so the same scheme must reuse one instance.
void main() {
  test('the same scheme reuses the identical ThemeData', () {
    final first = buildTodoTheme(TodoColors.oceanicNext);
    final second = buildTodoTheme(TodoColors.oceanicNext);

    expect(
      identical(first, second),
      isTrue,
      reason: 'rebuilding must not regenerate the tonal palette',
    );
  });

  test('every scheme keeps its own theme', () {
    final themes = {
      for (final scheme in TodoColors.all) scheme.id: buildTodoTheme(scheme),
    };

    expect(themes, hasLength(TodoColors.all.length));
    for (final scheme in TodoColors.all) {
      final theme = themes[scheme.id]!;
      expect(theme.brightness, scheme.brightness, reason: scheme.id);
      expect(
        theme.colorScheme.surface,
        scheme.primaryBackground,
        reason: '${scheme.id} carries its own colours',
      );
      expect(
        theme.extension<TodoThemeExtension>()?.colors.id,
        scheme.id,
        reason: 'the extension survives memoisation',
      );
    }
    expect(
      identical(
        buildTodoTheme(TodoColors.gruvboxLight),
        buildTodoTheme(TodoColors.patinaLight),
      ),
      isFalse,
      reason: 'two light schemes are still two themes',
    );
  });
}
