import 'package:material_ui/material_ui.dart';

/// Black and white.
class C {
  static const bg = Color(0xFF000000);
  static const surface = Color(0xFF121212);
  static const raised = Color(0xFF1C1C1C);
  static const hover = Color(0xFF2A2A2A);
  static const line = Color(0xFF2A2A2A);
  static const text = Color(0xFFFFFFFF);
  static const sub = Color(0xFFA7A7A7);
  static const faint = Color(0xFF6E6E6E);
}

ThemeData buildTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    scaffoldBackgroundColor: C.bg,
    canvasColor: C.bg,
    colorScheme: const ColorScheme.dark(
      primary: Colors.white,
      onPrimary: Colors.black,
      secondary: Colors.white,
      onSecondary: Colors.black,
      surface: C.surface,
      onSurface: C.text,
      surfaceContainerHighest: C.raised,
      outline: C.line,
      error: Color(0xFFFF6B6B),
    ),
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text),
    iconTheme: const IconThemeData(color: C.text),
    dividerColor: C.line,
    dividerTheme: const DividerThemeData(color: C.line, space: 1, thickness: 1),
    sliderTheme: const SliderThemeData(
      trackHeight: 4,
      activeTrackColor: Colors.white,
      inactiveTrackColor: Color(0xFF4D4D4D),
      thumbColor: Colors.white,
      overlayColor: Color(0x22FFFFFF),
      thumbShape: RoundSliderThumbShape(enabledThumbRadius: 6),
      overlayShape: RoundSliderOverlayShape(overlayRadius: 14),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Colors.white,
      contentTextStyle: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: C.raised,
      modalBackgroundColor: C.raised,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      showDragHandle: true,
      dragHandleColor: Color(0xFF5A5A5A),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: C.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
      textStyle: const TextStyle(color: C.text, fontSize: 14),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: C.raised,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.hover,
      hintStyle: const TextStyle(color: C.sub),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: const BorderSide(color: Colors.white, width: 1.5)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
    textSelectionTheme: const TextSelectionThemeData(cursorColor: Colors.white, selectionColor: Color(0x55FFFFFF), selectionHandleColor: Colors.white),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Colors.white, linearTrackColor: Color(0xFF4D4D4D)),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.black : C.sub),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? Colors.white : C.hover),
      trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
    ),
    scrollbarTheme: ScrollbarThemeData(thumbColor: WidgetStateProperty.all(const Color(0x66FFFFFF)), radius: const Radius.circular(4)),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(color: C.hover, borderRadius: BorderRadius.circular(4)),
      textStyle: const TextStyle(color: C.text, fontSize: 12),
      waitDuration: const Duration(milliseconds: 600),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
      TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
    }),
  );
}

const titleXL = TextStyle(fontSize: 30, fontWeight: FontWeight.w800, letterSpacing: -.6, height: 1.1);
const titleL = TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -.3);
const titleM = TextStyle(fontSize: 16, fontWeight: FontWeight.w700);
const body = TextStyle(fontSize: 14, color: C.text);
const subtle = TextStyle(fontSize: 13, color: C.sub);
