import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── Dark Palette ──────────────────────────────────────────
class DarkColors {
  static const bg          = Color(0xFF0F172A);
  static const surface     = Color(0xFF1E293B);
  static const surfaceHigh = Color(0xFF334155);
  static const border      = Color(0xFF334155);
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecond  = Color(0xFF94A3B8);
  static const textDim     = Color(0xFF475569);
}

// ── Light Palette ─────────────────────────────────────────
class LightColors {
  static const bg          = Color(0xFFF8FAFC);
  static const surface     = Color(0xFFFFFFFF);
  static const surfaceHigh = Color(0xFFF1F5F9);
  static const border      = Color(0xFFE2E8F0);
  static const textPrimary = Color(0xFF0F172A);
  static const textSecond  = Color(0xFF64748B);
  static const textDim     = Color(0xFF94A3B8);
}

// ── Shared Colors ─────────────────────────────────────────
class AppColors {
  // Ana renk — indigo
  static const orange     = Color(0xFF6366F1);   // artık indigo
  static const orangeDim  = Color(0x336366F1);
  static const orangeDeep = Color(0xFF4F46E5);
  // Semantic
  static const success    = Color(0xFF10B981);
  static const successDim = Color(0x2210B981);
  static const warn       = Color(0xFFF59E0B);
  static const warnDim    = Color(0x22F59E0B);
  static const danger     = Color(0xFFEF4444);
  static const dangerDim  = Color(0x22EF4444);
  static const info       = Color(0xFF3B82F6);
  static const infoDim    = Color(0x223B82F6);
  // Öncelik renkleri
  static const prio5      = Color(0xFFEF4444);
  static const prio4      = Color(0xFFF97316);
  static const prio3      = Color(0xFF6366F1);
  static const prio2      = Color(0xFF10B981);
  static const prio1      = Color(0xFF94A3B8);

  static bool _d(BuildContext ctx) =>
      Theme.of(ctx).brightness == Brightness.dark;

  static Color bg(BuildContext ctx)          => _d(ctx) ? DarkColors.bg          : LightColors.bg;
  static Color surface(BuildContext ctx)     => _d(ctx) ? DarkColors.surface     : LightColors.surface;
  static Color surfaceHigh(BuildContext ctx) => _d(ctx) ? DarkColors.surfaceHigh : LightColors.surfaceHigh;
  static Color border(BuildContext ctx)      => _d(ctx) ? DarkColors.border      : LightColors.border;
  static Color textPrimary(BuildContext ctx) => _d(ctx) ? DarkColors.textPrimary : LightColors.textPrimary;
  static Color textSecond(BuildContext ctx)  => _d(ctx) ? DarkColors.textSecond  : LightColors.textSecond;
  static Color textDim(BuildContext ctx)     => _d(ctx) ? DarkColors.textDim     : LightColors.textDim;
}

// ── Theme Builder ─────────────────────────────────────────
class AppTheme {
  static ThemeData get lightTheme => _build(dark: false);
  static ThemeData get darkTheme  => _build(dark: true);

  static ThemeData _build({required bool dark}) {
    final bg          = dark ? DarkColors.bg          : LightColors.bg;
    final surface     = dark ? DarkColors.surface     : LightColors.surface;
    final surfaceHigh = dark ? DarkColors.surfaceHigh : LightColors.surfaceHigh;
    final border      = dark ? DarkColors.border      : LightColors.border;
    final textPrimary = dark ? DarkColors.textPrimary : LightColors.textPrimary;
    final textSecond  = dark ? DarkColors.textSecond  : LightColors.textSecond;
    final textDim     = dark ? DarkColors.textDim     : LightColors.textDim;
    final brightness  = dark ? Brightness.dark : Brightness.light;

    return ThemeData(
      useMaterial3:            true,
      brightness:              brightness,
      scaffoldBackgroundColor: bg,
      colorScheme: ColorScheme(
        brightness: brightness,
        primary:    const Color(0xFF6366F1),
        onPrimary:  Colors.white,
        secondary:  const Color(0xFF8B5CF6),
        onSecondary:Colors.white,
        surface:    surface,
        onSurface:  textPrimary,
        error:      AppColors.danger,
        onError:    Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor:        bg,
        elevation:              0,
        scrolledUnderElevation: 0,
        iconTheme:  IconThemeData(color: textPrimary),
        titleTextStyle: TextStyle(
          color: textPrimary, fontSize: 18,
          fontWeight: FontWeight.w700, letterSpacing: -0.3,
        ),
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor:          Colors.transparent,
          statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
          statusBarBrightness:     dark ? Brightness.dark  : Brightness.light,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface, elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: border),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange,
          foregroundColor: Colors.white,
          elevation: 0,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.orange,
          textStyle: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true, fillColor: surface,
        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: border)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.5)),
        labelStyle: TextStyle(color: textSecond),
        hintStyle:  TextStyle(color: textDim),
      ),
      dividerTheme:  DividerThemeData(color: border, thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor:  surfaceHigh,
        contentTextStyle: TextStyle(color: textPrimary),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: surfaceHigh,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: TextStyle(color: textPrimary, fontSize: 14),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        titleTextStyle:   TextStyle(color: textPrimary, fontSize: 18, fontWeight: FontWeight.w700),
        contentTextStyle: TextStyle(color: textSecond),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.selected) ? AppColors.orange : textDim),
        trackColor: WidgetStateProperty.resolveWith(
                (s) => s.contains(WidgetState.selected) ? AppColors.orangeDim : surfaceHigh),
      ),
      listTileTheme: ListTileThemeData(
        textColor: textPrimary,
        iconColor: textSecond,
        tileColor: Colors.transparent,
      ),
      textTheme: TextTheme(
        bodyLarge:   TextStyle(color: textPrimary),
        bodyMedium:  TextStyle(color: textPrimary),
        bodySmall:   TextStyle(color: textSecond),
        titleLarge:  TextStyle(color: textPrimary, fontWeight: FontWeight.w700),
        titleMedium: TextStyle(color: textPrimary, fontWeight: FontWeight.w600),
        titleSmall:  TextStyle(color: textSecond),
        labelLarge:  TextStyle(color: textPrimary),
        labelMedium: TextStyle(color: textSecond),
        labelSmall:  TextStyle(color: textDim),
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        backgroundColor:     surface,
        selectedItemColor:   AppColors.orange,
        unselectedItemColor: textDim,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
      ),
    );
  }
}

// ── Reusable Widgets ──────────────────────────────────────
class AppCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final Color? color;
  final bool  highlight;
  const AppCard({super.key, required this.child, this.padding, this.onTap, this.color, this.highlight = false});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg     = color ?? (isDark ? DarkColors.surface : LightColors.surface);
    final bd     = highlight ? AppColors.orange : (isDark ? DarkColors.border : LightColors.border);
    return Container(
      decoration: BoxDecoration(
        color: bg, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: bd, width: highlight ? 1.5 : 1),
      ),
      child: Material(
        color: Colors.transparent, borderRadius: BorderRadius.circular(16),
        child: onTap != null
            ? InkWell(onTap: onTap, borderRadius: BorderRadius.circular(16),
            child: Padding(padding: padding ?? const EdgeInsets.all(16), child: child))
            : Padding(padding: padding ?? const EdgeInsets.all(16), child: child),
      ),
    );
  }
}

class AppChip extends StatelessWidget {
  final String label; final Color color; final IconData? icon;
  const AppChip({super.key, required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15), borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, color: color, size: 10), const SizedBox(width: 3)],
        Text(label, style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────
Color priorityColor(int p) {
  switch (p) {
    case 5: return AppColors.prio5; case 4: return AppColors.prio4;
    case 3: return AppColors.prio3; case 2: return AppColors.prio2;
    default: return AppColors.prio1;
  }
}

String priorityLabel(int p) {
  switch (p) {
    case 5: return 'Çok Yüksek'; case 4: return 'Yüksek';
    case 3: return 'Orta';       case 2: return 'Düşük';
    default: return 'Çok Düşük';
  }
}

String algoLabel(String k) {
  switch (k) {
    case 'genetic':             return 'Genetik';
    case 'simulated_annealing': return 'Simüle Tavlama';
    case 'ant_colony':          return 'Karınca Kolonisi';
    case 'tabu_search':         return 'Tabu Arama';
    case 'lin_kernighan':       return 'Lin-Kernighan';
    default:                    return k;
  }
}

IconData algoIcon(String k) {
  switch (k) {
    case 'genetic':             return Icons.auto_awesome;
    case 'simulated_annealing': return Icons.thermostat;
    case 'ant_colony':          return Icons.hive;
    case 'tabu_search':         return Icons.search;
    case 'lin_kernighan':       return Icons.route;
    default:                    return Icons.bolt;
  }
}

Color algoColor(String k) {
  switch (k) {
    case 'genetic':             return const Color(0xFF3D9CF5);
    case 'simulated_annealing': return const Color(0xFFFFB020);
    case 'ant_colony':          return const Color(0xFFFF6B35);
    case 'tabu_search':         return const Color(0xFFB47FFF);
    case 'lin_kernighan':       return const Color(0xFF00C896);
    default:                    return const Color(0xFF888888);
  }
}