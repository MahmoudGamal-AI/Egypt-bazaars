import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:iconsax/iconsax.dart';
import '../core/constants/colors.dart';
import '../core/theme/app_theme.dart';
import 'hover_scale_widget.dart';

class AIHeroBanner extends StatelessWidget {
  final VoidCallback onAskAiTap;

  const AIHeroBanner({super.key, required this.onAskAiTap});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.15),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 28),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  AppColors.primary.withOpacity(0.85),
                  AppColors.primaryDark.withOpacity(0.95),
                ],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.15),
                width: 1.5,
              ),
            ),
            child: Row(
              children: [
                // Glowing AI Icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.1),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.secondary.withOpacity(0.3),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Iconsax.magic_star,
                    color: AppColors.secondary,
                    size: 40,
                  ),
                )
                    .animate(onPlay: (controller) => controller.repeat(reverse: true))
                    .scaleXY(begin: 1.0, end: 1.05, duration: 2.seconds)
                    .shimmer(duration: 3.seconds, color: Colors.white30),
                
                const SizedBox(width: 24),
                
                // Content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Text(
                            'الملخص الاستراتيجي للذكاء الاصطناعي',
                            style: TextStyle(
                              color: AppColors.secondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(
                              color: AppColors.success.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.success.withOpacity(0.5)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.circle, size: 8, color: AppColors.success),
                                SizedBox(width: 4),
                                Text(
                                  'متصل ومحلل',
                                  style: TextStyle(color: AppColors.successLight, fontSize: 10, fontWeight: FontWeight.bold),
                                )
                              ],
                            ),
                          ).animate().fadeIn(delay: 500.ms),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        '✨ أداء منصتك اليوم متميز! سجلنا ارتفاعاً في طلبات قسم الحرف اليدوية بنسبة 15%. ننصحك بمراجعة طلبات البازارات الجديدة لدعم هذا النمو المستمر.',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          height: 1.5,
                        ),
                      ).animate().fadeIn(duration: 800.ms, delay: 200.ms).slideX(begin: 0.05),
                    ],
                  ),
                ),
                
                const SizedBox(width: 32),
                
                // Action Button
                HoverScaleWidget(
                  scaleOnHover: 1.05,
                  onTap: onAskAiTap,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    decoration: BoxDecoration(
                      gradient: AppGradients.gold,
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.secondary.withOpacity(0.4),
                          blurRadius: 15,
                          offset: const Offset(0, 5),
                        )
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Iconsax.message_text_1, color: AppColors.primaryDark, size: 20),
                        SizedBox(width: 10),
                        Text(
                          'تحدث مع المساعد',
                          style: TextStyle(
                            color: AppColors.primaryDark,
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ).animate().slideY(begin: 0.2, curve: Curves.easeOut).fadeIn(delay: 600.ms),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 600.ms).slideY(begin: -0.1, curve: Curves.easeOut);
  }
}


