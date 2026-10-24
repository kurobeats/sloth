import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A named colour scheme, taken from the Gogh terminal theme of the same name.
///
/// One accent, a two-step text ramp, a hairline divider, and a 16sp/14sp type
/// scale for task rows. Every scheme ships both the raw Gogh palette and the
/// app-facing tokens derived from it.
class TodoColors {
  const TodoColors({
    required this.id,
    required this.name,
    required this.author,
    required this.accent,
    required this.primaryText,
    required this.secondaryText,
    required this.primaryBackground,
    required this.secondaryBackground,
    required this.divider,
    required this.starActive,
    required this.overdue,
    required this.hover,
    required this.brightness,
  });

  final String id;
  final String name;

  /// Who made the colour scheme this app borrows, and where from.
  final String author;
  final Color accent;
  final Color primaryText;
  final Color secondaryText;
  final Color primaryBackground;
  final Color secondaryBackground;
  final Color divider;
  final Color starActive;
  final Color overdue;
  final Color hover;
  final Brightness brightness;

  bool get isDark => brightness == Brightness.dark;

  /// Text/icon colour that stays readable on [accent]: whichever of black or
  /// white has more contrast.
  Color get onAccent {
    const ink = Color(0xFF101010);
    return contrast(ink, accent) >= contrast(Colors.white, accent)
        ? ink
        : Colors.white;
  }

  /// WCAG contrast ratio between two opaque colours.
  static double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    final hi = la > lb ? la : lb, lo = la > lb ? lb : la;
    return (hi + 0.05) / (lo + 0.05);
  }

  /// Nudges [color] towards black (on light backgrounds) or white (on dark
  /// ones) until it clears [min] contrast against [background]. Gogh palettes
  /// are tuned for terminal text, not for 15px icons, so a few hues need this.
  static Color legible(Color color, Color background, double min) {
    if (contrast(color, background) >= min) return color;
    final towards = background.computeLuminance() > 0.5
        ? const Color(0xFF000000)
        : const Color(0xFFFFFFFF);
    var result = color;
    for (var i = 0; i < 40 && contrast(result, background) < min; i++) {
      result = Color.lerp(result, towards, 0.05)!;
    }
    return result;
  }

  /// A colour supplied by the server (project or label), made visible against
  /// the current background. Falls back to the accent when unset.
  static Color serverColor(String? hex, TodoColors scheme, {double min = 3.0}) {
    if (hex == null || hex.isEmpty) return scheme.accent;
    final value = int.tryParse(hex.replaceAll('#', ''), radix: 16);
    if (value == null) return scheme.accent;
    final raw = Color(
      hex.replaceAll('#', '').length == 8 ? value : 0xFF000000 | value,
    );
    return legible(raw, scheme.primaryBackground, min);
  }

  /// Project colour choices for the colour picker: the scheme's accent and
  /// hue rotations of it, so nothing outside the active theme is offered.
  /// (Labels are the one exception -- their colours come from the server.)
  static List<Color> swatches(TodoColors scheme) {
    final hsl = HSLColor.fromColor(scheme.accent);
    final colors = <Color>[
      scheme.accent,
      for (final delta in [38.0, 76.0, 140.0, 196.0, 262.0, 316.0])
        hsl.withHue((hsl.hue + delta) % 360).toColor(),
    ];
    // Keep every swatch visible against the background.
    return colors
        .map((c) => legible(c, scheme.primaryBackground, 3.0))
        .toSet()
        .toList();
  }

  /// Builds a scheme from raw Gogh colours, enforcing legibility minimums.
  factory TodoColors.derive({
    required String id,
    required String name,
    required String author,
    required Brightness brightness,
    required Color background,
    required Color surface,
    required Color foreground,
    required Color mutedForeground,
    required Color accent,
    required Color star,
    required Color danger,
  }) {
    final text = legible(foreground, background, 4.5);
    final secondary = legible(mutedForeground, background, 4.5);
    final primary = legible(accent, background, 4.5);
    final overdue = legible(danger, background, 4.5);
    final starActive = legible(star, background, 3.0);
    return TodoColors(
      id: id,
      name: name,
      author: author,
      brightness: brightness,
      accent: primary,
      primaryText: text,
      secondaryText: secondary,
      primaryBackground: background,
      secondaryBackground: surface,
      divider: text.withValues(alpha: 0.20),
      starActive: starActive,
      overdue: overdue,
      hover: Color.lerp(background, text, 0.06)!,
    );
  }

  // ---------------------------------------------------------------- dark ----

  /// Gogh "Oceanic Next" — the default dark scheme.
  static final oceanicNext = TodoColors.derive(
    id: 'oceanic-next',
    author: 'mhartington — github.com/mhartington/oceanic-next-iterm',
    name: 'Oceanic Next',
    brightness: Brightness.dark,
    background: const Color(0xFF1B2B34),
    surface: const Color(0xFF22333D),
    foreground: const Color(0xFFC1C5CD),
    mutedForeground: const Color(0xFF8A949E),
    accent: const Color(0xFF7198C8),
    star: const Color(0xFFF2CA73),
    danger: const Color(0xFFDB686B),
  );

  /// Gogh "Panda".
  static final panda = TodoColors.derive(
    id: 'panda',
    author: 'Siamak Mokhtari — Panda Syntax',
    name: 'Panda',
    brightness: Brightness.dark,
    background: const Color(0xFF1D1E20),
    surface: const Color(0xFF26282B),
    foreground: const Color(0xFFF0F0F0),
    mutedForeground: const Color(0xFF9BA3B0),
    accent: const Color(0xFF5C9FFF),
    star: const Color(0xFFFDAA5A),
    danger: const Color(0xFFFB055A),
  );

  /// Gogh "Catppuccin Mocha".
  static final catppuccinMocha = TodoColors.derive(
    id: 'catppuccin-mocha',
    author: 'Catppuccin — github.com/catppuccin',
    name: 'Catppuccin Mocha',
    brightness: Brightness.dark,
    background: const Color(0xFF1E1E2E),
    surface: const Color(0xFF292A3C),
    foreground: const Color(0xFFCDD6F4),
    mutedForeground: const Color(0xFFA6ADC8),
    accent: const Color(0xFF89B4FA),
    star: const Color(0xFFF9E2AF),
    danger: const Color(0xFFF38BA8),
  );

  // --------------------------------------------------------------- light ----

  /// Gogh "Gruvbox Light" — the default light scheme.
  static final gruvboxLight = TodoColors.derive(
    id: 'gruvbox-light',
    author: 'morhetz — github.com/morhetz/gruvbox',
    name: 'Gruvbox Light',
    brightness: Brightness.light,
    background: const Color(0xFFFBF1C7),
    surface: const Color(0xFFF2E5BC),
    foreground: const Color(0xFF3C3836),
    mutedForeground: const Color(0xFF7C6F64),
    accent: const Color(0xFF076678),
    star: const Color(0xFFB57614),
    danger: const Color(0xFF9D0006),
  );

  /// Gogh "Everforest Light".
  static final everforestLight = TodoColors.derive(
    id: 'everforest-light',
    author: 'sainnhe — github.com/sainnhe/everforest',
    name: 'Everforest Light',
    brightness: Brightness.light,
    background: const Color(0xFFFDF6E3),
    surface: const Color(0xFFF4EEDB),
    foreground: const Color(0xFF5C6A72),
    mutedForeground: const Color(0xFF829181),
    accent: const Color(0xFF3A94C5),
    star: const Color(0xFFDFA000),
    danger: const Color(0xFFF85552),
  );

  /// Gogh "Patina Light".
  static final patinaLight = TodoColors.derive(
    id: 'patina-light',
    author: 'PoshPalette — github.com/livlign/posh-palette',
    name: 'Patina Light',
    brightness: Brightness.light,
    background: const Color(0xFFDDD7C4),
    surface: const Color(0xFFD4CDB8),
    foreground: const Color(0xFF2E2A24),
    mutedForeground: const Color(0xFF5A5248),
    accent: const Color(0xFF2F626F),
    star: const Color(0xFF6E5817),
    danger: const Color(0xFF833333),
  );

  static final darkThemes = [oceanicNext, panda, catppuccinMocha];
  static final lightThemes = [gruvboxLight, everforestLight, patinaLight];
  static final all = [...darkThemes, ...lightThemes];

  static final defaultDark = oceanicNext;
  static final defaultLight = gruvboxLight;

  static TodoColors byId(String? id, Brightness brightness) {
    final fallback = brightness == Brightness.dark ? defaultDark : defaultLight;
    if (id == null) return fallback;
    for (final theme in all) {
      if (theme.id == id) return theme;
    }
    return fallback;
  }

  static TodoColors of(BuildContext context) {
    final extension = Theme.of(context).extension<TodoThemeExtension>();
    if (extension != null) return extension.colors;
    return Theme.of(context).brightness == Brightness.dark
        ? defaultDark
        : defaultLight;
  }
}

/// Carries the active scheme through [ThemeData] so widgets can read it with
/// `TodoColors.of(context)`.
class TodoThemeExtension extends ThemeExtension<TodoThemeExtension> {
  const TodoThemeExtension(this.colors);

  final TodoColors colors;

  @override
  TodoThemeExtension copyWith({TodoColors? colors}) =>
      TodoThemeExtension(colors ?? this.colors);

  @override
  TodoThemeExtension lerp(TodoThemeExtension? other, double t) =>
      t < 0.5 ? this : (other ?? this);
}

/// Text sizes and row metrics.
class TodoText {
  static const xs = 8.0;
  static const s = 12.0;
  static const small = 13.0;
  static const medium = 14.0;
  static const big = 16.0;
  static const xl = 18.0;
  static const xxl = 20.0;
  static const xxxl = 24.0;
  static const xxxxl = 28.0;

  /// Task rows: min 52dp tall, 8dp vertical padding.
  static const taskMinHeight = 52.0;
  static const dividerHeight = 1.0;
  static const headerMinHeight = 56.0;
  static const tilePadding = 8.0;
}

ThemeData buildTodoTheme(TodoColors c) {
  // M3 surfaces are split into containers; map every one of them onto the
  // scheme's two backgrounds so sheets, dialogs and menus stop falling back to
  // the generated near-white default.
  final scheme =
      ColorScheme.fromSeed(
        seedColor: c.accent,
        brightness: c.brightness,
      ).copyWith(
        primary: c.accent,
        onPrimary: c.onAccent,
        secondary: c.accent,
        surface: c.primaryBackground,
        onSurface: c.primaryText,
        onSurfaceVariant: c.secondaryText,
        surfaceTint: Colors.transparent,
        surfaceContainerLowest: c.primaryBackground,
        surfaceContainerLow: c.secondaryBackground,
        surfaceContainer: c.secondaryBackground,
        surfaceContainerHigh: c.secondaryBackground,
        surfaceContainerHighest: c.secondaryBackground,
        outline: c.divider,
        outlineVariant: c.divider,
      );
  return ThemeData(
    useMaterial3: true,
    brightness: c.brightness,
    colorScheme: scheme,
    iconTheme: IconThemeData(color: c.primaryText),
    scaffoldBackgroundColor: c.primaryBackground,
    canvasColor: c.primaryBackground,
    dividerColor: c.divider,
    dividerTheme: DividerThemeData(color: c.divider, space: 1, thickness: 1),
    splashFactory: InkSparkle.splashFactory,
    extensions: [TodoThemeExtension(c)],
    appBarTheme: AppBarTheme(
      backgroundColor: c.primaryBackground,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      foregroundColor: c.primaryText,
      iconTheme: IconThemeData(color: c.primaryText, size: 24),
      actionsIconTheme: IconThemeData(color: c.primaryText, size: 24),
      systemOverlayStyle: c.isDark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: c.primaryText,
        fontSize: 22,
        fontWeight: FontWeight.w600,
      ),
    ),
    drawerTheme: DrawerThemeData(
      backgroundColor: c.primaryBackground,
      surfaceTintColor: Colors.transparent,
      scrimColor: Colors.black.withValues(alpha: 0.4),
    ),
    textTheme: ThemeData(brightness: c.brightness).textTheme
        .apply(bodyColor: c.primaryText, displayColor: c.primaryText),
    listTileTheme: ListTileThemeData(
      textColor: c.primaryText,
      iconColor: c.accent,
      selectedColor: c.accent,
    ),
    inputDecorationTheme: InputDecorationTheme(
      hintStyle: TextStyle(color: c.secondaryText, fontSize: TodoText.big),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.accent,
        foregroundColor: c.onAccent,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: c.primaryText),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.secondaryBackground,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(
        color: c.primaryText,
        fontSize: 20,
        fontWeight: FontWeight.w600,
      ),
      contentTextStyle: TextStyle(
        color: c.primaryText,
        fontSize: TodoText.medium,
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.secondaryBackground,
      modalBackgroundColor: c.secondaryBackground,
      surfaceTintColor: Colors.transparent,
      dragHandleColor: c.secondaryText.withValues(alpha: 0.5),
      showDragHandle: true,
    ),
    cardTheme: CardThemeData(
      color: c.secondaryBackground,
      surfaceTintColor: Colors.transparent,
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.primaryText,
      contentTextStyle: TextStyle(color: c.primaryBackground),
      actionTextColor: c.accent,
      behavior: SnackBarBehavior.floating,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.secondaryBackground,
      selectedColor: c.accent.withValues(alpha: 0.16),
      labelStyle: TextStyle(color: c.primaryText, fontSize: 13),
      side: BorderSide(color: c.divider),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.secondaryBackground,
      surfaceTintColor: Colors.transparent,
      textStyle: TextStyle(color: c.primaryText, fontSize: TodoText.medium),
      iconColor: c.primaryText,
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? c.accent : null,
      ),
      checkColor: WidgetStatePropertyAll(c.onAccent),
    ),
  );
}
