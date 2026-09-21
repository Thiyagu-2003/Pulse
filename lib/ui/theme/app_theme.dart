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

  static ThemeData get darkTheme {
    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: background,
      primaryColor: primary,
      splashFactory: InkSparkle.splashFactory,
      colorScheme: const ColorScheme.dark(
        primary: primary,
        onPrimary: mist,
        secondary: accent,
        onSecondary: background,
        surface: surface,
        onSurface: mist,
        surfaceContainerHighest: lift,
      ),
      textTheme: _textTheme(base.textTheme),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        iconTheme: IconThemeData(color: mist),
      ),
      // One radius family, but not one radius for everything: rows are
      // gentler than sheets, so hierarchy stays readable.
      cardTheme: CardThemeData(
        color: lift,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: surface,
        showDragHandle: true,
        dragHandleColor: Color(0x33F2F1FA),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: lift,
        contentTextStyle: GoogleFonts.inter(color: mist, fontSize: 14),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: primary.withValues(alpha: 0.22),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 24,
            color: states.contains(WidgetState.selected)
                ? primarySoft
                : mist.withValues(alpha: 0.45),
          ),
        ),
        labelTextStyle: WidgetStateProperty.all(
          GoogleFonts.inter(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: primarySoft,
          ),
        ),
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: accent,
        inactiveTrackColor: mist.withValues(alpha: 0.14),
        thumbColor: accent,
        trackHeight: 3,
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 16),
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      tabBarTheme: TabBarThemeData(
        indicatorColor: primarySoft,
        labelColor: mist,
        unselectedLabelColor: mist.withValues(alpha: 0.45),
        dividerColor: Colors.transparent,
        labelStyle: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      listTileTheme: const ListTileThemeData(
        iconColor: mist,
        textColor: mist,
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: accent,
        linearMinHeight: 2,
      ),
    );
  }

  /// Outfit carries headings, Inter carries text. Two families, clearly
  /// distinct: Outfit's geometric caps read as a wordmark, Inter stays quiet
  /// at track-title size where it has to hold up in long lists.
  static TextTheme _textTheme(TextTheme base) {
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
