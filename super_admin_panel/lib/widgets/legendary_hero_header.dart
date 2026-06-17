import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../core/constants/colors.dart';

/// ترويسة الصفحة الأسطورية (Boss Level 3.0)
/// تحتوي على نصوص متوهجة وأيقونات شفافة في الخلفية وتأثيرات ظهور مبهرة.
class LegendaryHeroHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? action;
  final Widget? bottom;

  const LegendaryHeroHeader({
    super.key,
    required this.title,
    required this.subtitle,
    required this.icon,
    this.action,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppColors.white.withOpacity(0.3),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(
          color: AppColors.white.withOpacity(0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.05),
            blurRadius: 30,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // أيقونة خلفية كبيرة وشفافة للزينة
          Positioned(
            left: -20,
            top: -40,
            child: Icon(
              icon,
              size: 150,
              color: AppColors.primary.withOpacity(0.03),
            )
                .animate(onPlay: (controller) => controller.repeat())
                .shimmer(duration: 3000.ms, color: AppColors.primary.withOpacity(0.1)),
          ),
          
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الأيقونة الرئيسية
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.primary.withOpacity(0.2),
                      AppColors.primary.withOpacity(0.05),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: AppColors.primary.withOpacity(0.2),
                    width: 1,
                  ),
                ),
                child: Icon(
                  icon,
                  size: 32,
                  color: AppColors.primary,
                ),
              )
                  .animate()
                  .scale(duration: 600.ms, curve: Curves.easeOutBack)
                  .fadeIn(duration: 600.ms),
              
              const SizedBox(width: 24),
              
              // النصوص
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                        letterSpacing: -0.5,
                      ),
                    ).animate().slideX(duration: 500.ms, begin: 0.1).fadeIn(duration: 500.ms),
                    const SizedBox(height: 8),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 16,
                        color: AppColors.textSecondary.withOpacity(0.8),
                        fontWeight: FontWeight.w500,
                      ),
                    ).animate().slideX(duration: 500.ms, begin: 0.1, delay: 100.ms).fadeIn(duration: 500.ms, delay: 100.ms),
                  ],
                ),
              ),
              
              // الإجراءات (Actions)
              if (action != null)
                action!.animate().scale(duration: 500.ms, delay: 200.ms, curve: Curves.easeOutBack).fadeIn(duration: 500.ms, delay: 200.ms),
            ],
          ),
          
          if (bottom != null) ...[
            const SizedBox(height: 24),
            bottom!.animate().slideY(duration: 500.ms, begin: 0.2, curve: Curves.easeOutBack).fadeIn(duration: 500.ms),
          ],
        ],
      ),
    );
  }
}
