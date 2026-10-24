import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/todo_theme.dart';

double contrast(Color a, Color b) => TodoColors.contrast(a, b);

void main() {
  test('every scheme keeps text and icons readable', () {
    for (final theme in TodoColors.all) {
      final bg = theme.primaryBackground;
      expect(contrast(theme.primaryText, bg), greaterThanOrEqualTo(4.5),
          reason: '${theme.name}: primary text');
      // Secondary text also draws the 15px metadata icons and the star outline,
      // so it has to clear the small-text bar, not the 3:1 UI bar.
      expect(contrast(theme.secondaryText, bg), greaterThanOrEqualTo(4.5),
          reason: '${theme.name}: secondary text and icons');
      expect(contrast(theme.accent, bg), greaterThanOrEqualTo(4.5),
          reason: '${theme.name}: accent icons (checkbox, drawer, entry bar)');
      expect(contrast(theme.overdue, bg), greaterThanOrEqualTo(4.5),
          reason: '${theme.name}: overdue date');
      expect(contrast(theme.starActive, bg), greaterThanOrEqualTo(3.0),
          reason: '${theme.name}: active star');
      expect(contrast(theme.onAccent, theme.accent),
          greaterThanOrEqualTo(4.5),
          reason: '${theme.name}: text on the accent fill');
      // Surfaces must stay distinguishable from the background.
      expect(contrast(theme.secondaryBackground, bg), greaterThan(1.02),
          reason: '${theme.name}: secondary surface');
    }
  });

  test('legible() only escalates until the bar is met', () {
    final lightBg = Colors.white;
    final weak = const Color(0xFFAABBCC); // low contrast on white
    expect(contrast(weak, lightBg), lessThan(4.5));
    final fixed = TodoColors.legible(weak, lightBg, 4.5);
    expect(contrast(fixed, lightBg), greaterThanOrEqualTo(4.5));
    final strong = const Color(0xFF000000);
    expect(TodoColors.legible(strong, lightBg, 4.5), strong);
  });

  test('both defaults resolve and ids are unique', () {
    expect(TodoColors.byId(null, Brightness.dark), TodoColors.oceanicNext);
    expect(TodoColors.byId(null, Brightness.light), TodoColors.gruvboxLight);
    final ids = TodoColors.all.map((t) => t.id).toSet();
    expect(ids.length, TodoColors.all.length);
    expect(TodoColors.darkThemes.every((t) => t.isDark), isTrue);
    expect(TodoColors.lightThemes.every((t) => !t.isDark), isTrue);
    expect(TodoColors.all.length, 6);
  });
}
