import 'package:flutter/material.dart';

/// ألوان تطبيق صاحب البازار - الهوية الجديدة (متطابقة مع تطبيق السياح)
class AppColors {
  // ===== الألوان الأساسية (Primary) =====
  static const Color primary = Color(0xFFE87A2B); // برتقالي حيوي
  static const Color primaryDark = Color(0xFFD4651F);
  static const Color primaryLight = Color(0xFFF5A623);
  
  // ===== الألوان الثانوية (Secondary) =====
  static const Color secondary = Color(0xFF1A8B7C); // تركواز منعش
  static const Color secondaryDark = Color(0xFF14665A);
  static const Color secondaryLight = Color(0xFF2AA89A);
  static const Color accent = Color(0xFFE87A2B); 

  // ===== ألوان الهوية الفرعونية =====
  static const Color gold = Color(0xFFC4942B);
  static const Color goldLight = Color(0xFFD4A84B);
  static const Color pharaohBlue = Color(0xFF1E3A5F);
  static const Color sandBeige = Color(0xFFF5E6D3);

  // ===== ألوان الخلفية =====
  static const Color background = Color(0xFFF8F9FA); // فاتح جداً للتباين
  static const Color backgroundDark = Color(0xFF121212);
  static const Color surface = Color(0xFFFFFFFF);
  static const Color surfaceDark = Color(0xFF1E1E1E);
  static const Color cardBackground = Color(0xFFFFFFFF);

  // ===== ألوان النص =====
  static const Color textPrimary = Color(0xFF1A1A1A); // أسود قوي
  static const Color textSecondary = Color(0xFF6B7280); // رمادي مريح
  static const Color textHint = Color(0xFF9CA3AF);
  static const Color textOnPrimary = Color(0xFFFFFFFF);

  // ===== ألوان الحالة =====
  static const Color success = Color(0xFF4CAF50); // أخضر قوي
  static const Color successLight = Color(0xFFD1FAE5);
  static const Color warning = Color(0xFFFFC107);
  static const Color warningLight = Color(0xFFFEF3C7);
  static const Color error = Color(0xFFE53935);
  static const Color errorLight = Color(0xFFFEE2E2);
  static const Color info = Color(0xFF2196F3);
  static const Color infoLight = Color(0xFFDBEAFE);

  // ===== ألوان إضافية =====
  static const Color divider = Color(0xFFE5E7EB);
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);
  static const Color overlay = Color(0x80000000);

  // ===== ألوان حالات الطلبات =====
  static const Color pending = Color(0xFFFFC107);
  static const Color accepted = Color(0xFF2196F3);
  static const Color preparing = Color(0xFF8B5CF6);
  static const Color readyForPickup = Color(0xFFE87A2B); // Orange
  static const Color shipping = Color(0xFF6366F1);
  static const Color delivered = Color(0xFF4CAF50);
  static const Color rejected = Color(0xFFE53935);
  static const Color cancelled = Color(0xFF6B7280);

  // ===== التدرجات الاحترافية =====
  static const LinearGradient primaryGradient = LinearGradient(
    colors: [Color(0xFFE87A2B), Color(0xFFF5A623)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient tealGradient = LinearGradient(
    colors: [Color(0xFF1A8B7C), Color(0xFF2AA89A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient goldGradient = LinearGradient(
    colors: [Color(0xFFD4A84B), Color(0xFFC4942B)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient successGradient = LinearGradient(
    colors: [Color(0xFF4CAF50), Color(0xFF388E3C)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient warningGradient = LinearGradient(
    colors: [Color(0xFFFFC107), Color(0xFFFFA000)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient infoGradient = LinearGradient(
    colors: [Color(0xFF2196F3), Color(0xFF1976D2)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient darkGradient = LinearGradient(
    colors: [Color(0xFF1E3A5F), Color(0xFF11223A)],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  static const LinearGradient headerGradient = LinearGradient(
    colors: [Color(0xFFE87A2B), Color(0xFF1A8B7C)], // دمج البرتقالي والتركواز
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
  );

  // ===== ظلال احترافية =====
  static List<BoxShadow> get softShadow => [
        BoxShadow(
          color: black.withOpacity(0.04),
          blurRadius: 10,
          offset: const Offset(0, 4),
        ),
      ];

  static List<BoxShadow> get mediumShadow => [
        BoxShadow(
          color: black.withOpacity(0.08),
          blurRadius: 15,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get primaryShadow => [
        BoxShadow(
          color: primary.withOpacity(0.25),
          blurRadius: 15,
          offset: const Offset(0, 6),
        ),
      ];

  static List<BoxShadow> get successShadow => [
        BoxShadow(
          color: success.withOpacity(0.25),
          blurRadius: 15,
          offset: const Offset(0, 6),
        ),
      ];

  // ===== تأثيرات Glassmorphism =====
  static BoxDecoration get glassCard => BoxDecoration(
        color: white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: white.withOpacity(0.5), width: 1.5),
        boxShadow: softShadow,
      );

  static BoxDecoration get gradientCard => BoxDecoration(
        gradient: primaryGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: primaryShadow,
      );
}
