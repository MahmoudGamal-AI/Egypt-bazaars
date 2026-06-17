import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import '../core/constants/colors.dart';
import '../core/theme/app_theme.dart';
import 'glass_container.dart';

/// ✨ الإشعارات العائمة الاحترافية
class ElegantToast {
  ElegantToast._();

  static void showSuccess(BuildContext context, String message, {String title = 'نجاح'}) {
    _showToast(context, title, message, AppColors.success, Iconsax.tick_circle);
  }

  static void showError(BuildContext context, String message, {String title = 'خطأ'}) {
    _showToast(context, title, message, AppColors.error, Iconsax.close_circle);
  }

  static void showInfo(BuildContext context, String message, {String title = 'معلومة'}) {
    _showToast(context, title, message, AppColors.info, Iconsax.info_circle);
  }

  static void _showToast(
    BuildContext context,
    String title,
    String message,
    Color color,
    IconData icon,
  ) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.hideCurrentSnackBar();
    
    scaffoldMessenger.showSnackBar(
      SnackBar(
        elevation: 0,
        behavior: SnackBarBehavior.floating,
        backgroundColor: Colors.transparent,
        padding: EdgeInsets.zero,
        margin: const EdgeInsets.only(bottom: 24, left: 24, right: 24),
        content: GlassContainer(
          padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(16),
          color: AppColors.sidebarBg,
          opacity: 0.85,
          borderColor: color.withOpacity(0.5),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: AppColors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: TextStyle(
                        color: AppColors.white.withOpacity(0.8),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
