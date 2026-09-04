import 'package:flutter/material.dart';

/// Theme tap trung cho toan app - mau sac, typography, bo goc, do bong.
/// Khong dung font tai tu mang (Google Fonts) de app khong phu thuoc
/// internet luc chay thuc dia - chi tinh chinh thang chu he thong.
class AppTheme {
  AppTheme._();

  // Xanh duong-teal sau, hop voi cam giac "nuoc/van xu ly nuoc" hon mau
  // xanh mac dinh phang.
  static const Color _seed = Color(0xFF0E7490); // cyan-800
  static const double radiusSm = 10;
  static const double radiusMd = 14;
  static const double radiusLg = 20;

  static ThemeData light() => _build(Brightness.light, const Color(0xFFF4F7FA));

  static ThemeData dark() => _build(Brightness.dark, const Color(0xFF0B1416));

  static ThemeData _build(Brightness brightness, Color scaffoldBg) {
    final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
    final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: brightness);
    final textTheme = _textTheme(base.textTheme, scheme);

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: scaffoldBg,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        scrolledUnderElevation: 2,
        centerTitle: false,
        // [FIX] Tieu de qua to (thua huong titleLarge 21px chung voi dialog/
        // header khac) chiem qua nhieu dat man hinh - tach rieng 1 style nho
        // gon hon CHI cho AppBar, giam luon toolbarHeight/titleSpacing mac
        // dinh de tan dung them chieu cao man hinh cho noi dung ben duoi.
        toolbarHeight: 50,
        titleSpacing: 16,
        titleTextStyle: TextStyle(fontSize: 16.5, fontWeight: FontWeight.w600, color: scheme.onPrimary),
        iconTheme: IconThemeData(color: scheme.onPrimary, size: 22),
        actionsIconTheme: IconThemeData(color: scheme.onPrimary, size: 22),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        color: scheme.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusMd),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
        ),
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      chipTheme: base.chipTheme.copyWith(
        labelStyle: textTheme.labelMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        side: BorderSide.none,
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
          side: BorderSide(color: scheme.outline),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: scheme.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(radiusSm),
          borderSide: BorderSide(color: scheme.primary, width: 1.6),
        ),
        labelStyle: TextStyle(color: scheme.onSurfaceVariant),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surface,
        elevation: 3,
        height: 66,
        indicatorColor: scheme.primaryContainer,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? scheme.primary : scheme.onSurfaceVariant,
          );
        }),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.primary,
        titleTextStyle: textTheme.titleSmall,
        subtitleTextStyle: textTheme.bodySmall,
      ),
      dividerTheme: DividerThemeData(color: scheme.outlineVariant.withValues(alpha: 0.6), space: 1),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusSm)),
      ),
      dialogTheme: DialogThemeData(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radiusLg)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: scheme.primary),
    );
  }

  // [FIX] Chu qua nho + qua dam (nguoi dung phan anh kho doc khi thao tac
  // ngoai hien truong). Khong dung font tai qua mang (Google Fonts) - chi
  // tang co chu ro rang theo toan bo type scale VA giam bot do dam (chi giu
  // w700 that su cho headline, con lai w500-w600 - vua du noi bat vua de
  // doc, khong "dinh chu" nhu w700/w800 rai khap noi truoc day).
  static TextTheme _textTheme(TextTheme base, ColorScheme scheme) {
    return base.copyWith(
      headlineSmall: base.headlineSmall?.copyWith(fontSize: 26, fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleLarge: base.titleLarge?.copyWith(fontSize: 21, fontWeight: FontWeight.w600, letterSpacing: -0.1),
      titleMedium: base.titleMedium?.copyWith(fontSize: 17.5, fontWeight: FontWeight.w600),
      titleSmall: base.titleSmall?.copyWith(fontSize: 15.5, fontWeight: FontWeight.w600),
      bodyLarge: base.bodyLarge?.copyWith(fontSize: 17, height: 1.45),
      bodyMedium: base.bodyMedium?.copyWith(fontSize: 15.5, height: 1.45, color: scheme.onSurfaceVariant),
      bodySmall: base.bodySmall?.copyWith(fontSize: 13.5, height: 1.4, color: scheme.onSurfaceVariant),
      labelLarge: base.labelLarge?.copyWith(fontSize: 15, fontWeight: FontWeight.w600),
      labelMedium: base.labelMedium?.copyWith(fontSize: 13, fontWeight: FontWeight.w500, letterSpacing: 0.2),
      labelSmall: base.labelSmall?.copyWith(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.3),
    );
  }
}
