import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sloth/todo_theme.dart';

/// The 6-digit hex the app sends to Vikunja for a project or label colour was
/// spelled out at three call sites (and a fourth time in the colour picker).
/// One helper now, with exactly that conversion.
void main() {
  /// The expression the call sites used before.
  String inline(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  test('toHex matches the conversion the call sites used', () {
    for (final scheme in [
      ...TodoColors.lightThemes,
      ...TodoColors.darkThemes,
    ]) {
      for (final color in [
        scheme.accent,
        scheme.primaryText,
        scheme.secondaryText,
        scheme.starActive,
        scheme.overdue,
        scheme.divider,
      ]) {
        expect(TodoColors.toHex(color), inline(color), reason: scheme.id);
      }
    }
  });

  test('the format is lowercase, six digits, zero padded', () {
    expect(TodoColors.toHex(const Color(0xFF0F766E)), '#0f766e');
    expect(TodoColors.toHex(const Color(0xFF0000FF)), '#0000ff');
    expect(TodoColors.toHex(const Color(0xFF000000)), '#000000');
    expect(TodoColors.toHex(const Color(0xFF00000A)), '#00000a');
    expect(TodoColors.toHex(const Color(0xFFFFFFFF)), '#ffffff');
    // Alpha is dropped: Vikunja stores RGB.
    expect(TodoColors.toHex(const Color(0x800F766E)), '#0f766e');
  });
}
