import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'dart:ui';
import '../core/constants/colors.dart';

/// كرت زجاجي أسطوري (Boss Level 3.0)
/// يتفاعل مع حركة الماوس، يقوم بإنشاء توهج ضوئي يتتبع الماوس، ويميل بـ 3D (Parallax).
class LegendaryGlassCard extends StatefulWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final bool isSelected;

  const LegendaryGlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
    this.onTap,
    this.isSelected = false,
  });

  @override
  State<LegendaryGlassCard> createState() => _LegendaryGlassCardState();
}

class _LegendaryGlassCardState extends State<LegendaryGlassCard>
    with SingleTickerProviderStateMixin {
  Offset _mousePosition = Offset.zero;
  bool _isHovered = false;
  late AnimationController _tiltController;

  @override
  void initState() {
    super.initState();
    _tiltController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
  }

  @override
  void dispose() {
    _tiltController.dispose();
    super.dispose();
  }

  void _onHover(PointerHoverEvent event) {
    if (!mounted) return;
    setState(() {
      _mousePosition = event.localPosition;
    });
  }

  void _onEnter(PointerEnterEvent event) {
    if (!mounted) return;
    setState(() {
      _isHovered = true;
      _mousePosition = event.localPosition;
    });
    _tiltController.forward();
  }

  void _onExit(PointerExitEvent event) {
    if (!mounted) return;
    setState(() {
      _isHovered = false;
    });
    _tiltController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: _onEnter,
      onHover: _onHover,
      onExit: _onExit,
      cursor: widget.onTap != null ? SystemMouseCursors.click : MouseCursor.defer,
      child: GestureDetector(
        onTap: widget.onTap,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // حساب الميلان (Tilt) بناءً على مكان الماوس بالنسبة للكرت
            double tiltX = 0.0;
            double tiltY = 0.0;

            if (_isHovered && constraints.maxWidth > 0 && constraints.maxHeight > 0) {
              final x = (_mousePosition.dx / constraints.maxWidth) - 0.5;
              final y = (_mousePosition.dy / constraints.maxHeight) - 0.5;
              tiltX = y * 0.05; // أقصى ميلان للأسفل/الأعلى
              tiltY = -x * 0.05; // أقصى ميلان لليمين/اليسار
            }

            return AnimatedBuilder(
              animation: _tiltController,
              builder: (context, child) {
                // دمج الميلان مع الأنيميشن للحصول على حركة سلسة عند الدخول والخروج
                final currentTiltX = tiltX * _tiltController.value;
                final currentTiltY = tiltY * _tiltController.value;

                return Transform(
                  transform: Matrix4.identity()
                    ..setEntry(3, 2, 0.001) // Perspective
                    ..rotateX(currentTiltX)
                    ..rotateY(currentTiltY),
                  alignment: Alignment.center,
                  child: child,
                );
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(24),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                  child: Stack(
                    children: [
                      // طبقة الزجاج الأساسية
                      Container(
                        decoration: BoxDecoration(
                          color: widget.isSelected 
                              ? AppColors.primary.withOpacity(0.15)
                              : AppColors.white.withOpacity(0.4),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: widget.isSelected 
                                ? AppColors.primary.withOpacity(0.5)
                                : AppColors.white.withOpacity(0.5),
                            width: 1.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.black.withOpacity(0.05),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                      ),

                      // طبقة التوهج التي تتبع الماوس
                      if (_isHovered)
                        Positioned(
                          left: _mousePosition.dx - 150,
                          top: _mousePosition.dy - 150,
                          child: AnimatedOpacity(
                            duration: const Duration(milliseconds: 200),
                            opacity: _isHovered ? 1.0 : 0.0,
                            child: Container(
                              width: 300,
                              height: 300,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: RadialGradient(
                                  colors: [
                                    AppColors.primary.withOpacity(0.15),
                                    AppColors.primary.withOpacity(0.0),
                                  ],
                                  stops: const [0.0, 1.0],
                                ),
                              ),
                            ),
                          ),
                        ),

                      // المحتوى
                      Padding(
                        padding: widget.padding,
                        child: widget.child,
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
