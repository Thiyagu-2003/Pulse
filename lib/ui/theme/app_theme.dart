import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Colours are taken from the Pulse mark itself (`icons/app_icon.svg`) rather
/// than invented: the plate `#13141B`, the violet waveform gradient, and the
/// teal beat-dot. The old theme used a bluer background and a harsher neon
/// cyan than the logo, so the app didn't look like its own icon.
///
/// The one rule that gives the palette meaning: **teal is the pulse.** In the
/// mark it is the dot riding the waveform, so in the UI it marks only what is
/// currently sounding — the playing track, the live progress, the active
/// mode. Violet is for anything you can press. Spraying the accent on every
/// icon is what made the old UI read as decoration rather than signal.
class AppTheme {
  // The constants below are the *dark* palette. Screens that follow the
  // light/dark setting read `context.colors` instead; these stay for the
  // surfaces that are dark in both themes, like Now Playing over its art.

  /// The logo plate. Warm-neutral, not navy.
  static const Color background = Color(0xFF13141B);

  /// Raised surfaces: sheets, dialogs, the nav bar.
  static const Color surface = Color(0xFF1B1D28);

  /// Cards and rows, straight from the mark's inner lift.
  static const Color lift = Color(0xFF232538);

  /// The waveform violet — primary action colour.
  static const Color primary = Color(0xFF7A5CFF);
  static const Color primarySoft = Color(0xFFB57DFF);

  /// The beat dot. Reserved for live playback state.
  static const Color accent = Color(0xFF22D3EE);
  static const Color accentGlow = Color(0xFF8FF3FF);

  /// Wordmark off-white — easier on the eyes than pure white on this plate.
  static const Color mist = Color(0xFFF2F1FA);

  static const Color cardGlass = Color(0x2E232538);

  /// The mark's waveform gradient, for the one or two places that earn it.
  static const LinearGradient waveGradient = LinearGradient(
    colors: [primary, primarySoft],
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  static ThemeData get darkTheme => _build(PulseColors.dark, Brightness.dark);
  static ThemeData get lightTheme =>
      _build(PulseColors.light, Brightness.light);

  static ThemeData _build(PulseColors c, Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final base = isDark
        ? ThemeData.dark(useMaterial3: true)
        : ThemeData.light(useMaterial3: true);
    // On a light plate the soft violet is too pale to mark a selection.
    final selected = isDark ? primarySoft : primary;

    return base.copyWith(
      extensions: [c],
      scaffoldBackgroundColor: c.background,
      primaryColor: primary,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: (isDark ? const ColorScheme.dark() : const ColorScheme.light())
          .copyWith(
        primary: primary,
        onPrimary: Colors.white,
        secondary: c.accent,
        onSecondary: c.background,
        surface: c.surface,
        onSurface: c.mist,
        surfaceContainerHighest: c.lift,
      ),
      textTheme: _textTheme(base.textTheme, c.mist),
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: c.mist),
        foregroundColor: c.mist,
      ),
      // One radius family, but not one radius for everything: rows are
      // gentler than sheets, so hierarchy stays readable.
      cardTheme: CardThemeData(
        color: c.lift,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: c.surface,
        showDragHandle: true,
        dragHandleColor: c.mist.withValues(alpha: 0.2),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: c.lift,
        contentTextStyle: GoogleFonts.inter(color: c.mist, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: c.surface,
        indicatorColor: primary.withValues(alpha: 0.22),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? selected
                : c.mist.withValues(alpha: 0.45),
          ),
        ),
        labelTextStyle: WidgetStateProperty.all(
          GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: selected,
          ),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: c.accent,
        inactiveTrackColor: c.mist.withValues(alpha: 0.14),
        thumbColor: c.accent,
        trackHeight: 3,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: selected,
        labelColor: c.mist,
        unselectedLabelColor: c.mist.withValues(alpha: 0.45),
        dividerColor: Colors.transparent,
        labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: c.mist,
        textColor: c.mist,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: c.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: c.accent,
        linearMinHeight: 2,
      ),
    );
  }

  /// Outfit carries headings, Inter carries text. Two families, clearly
  /// distinct: Outfit's geometric caps read as a wordmark, Inter stays quiet
  /// at track-title size where it has to hold up in long lists.
  static TextTheme _textTheme(TextTheme base, Color mist) {
    return GoogleFonts.outfitTextTheme(base).copyWith(
      displaySmall: GoogleFonts.outfit(
        fontSize: 30,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.6,
        color: mist,
      ),
      headlineSmall: GoogleFonts.outfit(
        fontSize: 22,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        color: mist,
      ),
      titleMedium: GoogleFonts.inter(
        fontSize: 15,
        fontWeight: FontWeight.w600,
        color: mist,
      ),
      titleSmall: GoogleFonts.inter(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: mist,
      ),
      bodyLarge: GoogleFonts.inter(fontSize: 15, color: mist, height: 1.45),
      bodyMedium: GoogleFonts.inter(
        fontSize: 13,
        color: mist.withValues(alpha: 0.62),
        height: 1.45,
      ),
      bodySmall: GoogleFonts.inter(
        fontSize: 11.5,
        color: mist.withValues(alpha: 0.45),
      ),
    );
  }
}

/// The colours that differ between the light and dark themes. Brand violet
/// is the same in both; everything neutral, and the teal (which is too pale
/// to read on white), comes from here.
@immutable
class PulseColors extends ThemeExtension<PulseColors> {
  final Color background;
  final Color surface;
  final Color lift;

  /// Text and icons on [background] / [surface].
  final Color mist;
  final Color accent;

  const PulseColors({
    required this.background,
    required this.surface,
    required this.lift,
    required this.mist,
    required this.accent,
  });

  static const dark = PulseColors(
    background: AppTheme.background,
    surface: AppTheme.surface,
    lift: AppTheme.lift,
    mist: AppTheme.mist,
    accent: AppTheme.accent,
  );

  static const light = PulseColors(
    background: Color(0xFFF6F5FB),
    surface: Color(0xFFFFFFFF),
    lift: Color(0xFFECEAF6),
    mist: Color(0xFF1B1A2E),
    accent: Color(0xFF0891B2),
  );

  @override
  PulseColors copyWith({
    Color? background,
    Color? surface,
    Color? lift,
    Color? mist,
    Color? accent,
  }) =>
      PulseColors(
        background: background ?? this.background,
        surface: surface ?? this.surface,
        lift: lift ?? this.lift,
        mist: mist ?? this.mist,
        accent: accent ?? this.accent,
      );

  @override
  PulseColors lerp(PulseColors? other, double t) {
    if (other == null) return this;
    return PulseColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      lift: Color.lerp(lift, other.lift, t)!,
      mist: Color.lerp(mist, other.mist, t)!,
      accent: Color.lerp(accent, other.accent, t)!,
    );
  }
}

extension PulseThemeContext on BuildContext {
  /// The light- or dark-theme palette in effect here.
  PulseColors get colors => Theme.of(this).extension<PulseColors>()!;
}
