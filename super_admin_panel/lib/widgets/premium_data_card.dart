import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants/colors.dart';
import 'glass_container.dart';

/// بطاقة البيانات المتقدمة مع تأثير الـ 3D وتوهج الماوس (Boss Level 3.5)
class PremiumDataCard extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final bool isSelected;
  final EdgeInsetsGeometry? padding;

  const PremiumDataCard({
    super.key,
    required this.child,
    this.onTap,
    this.isSelected = false,
    this.padding,
  });

  @override
  State<PremiumDataCard> createState() => _PremiumDataCardState();
}

class _PremiumDataCardState extends State<PremiumDataCard> with SingleTickerProviderStateMixin {
  bool _isHovered = false;
  Offset _mousePosition = Offset.zero;
  late AnimationController _tiltController;

  @override
  void initState() {
    super.initState();
    _tiltController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
      lowerBound: -1,
      upperBound: 1,
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

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: MouseRegion(
        onEnter: (_) {
          setState(() => _isHovered = true);
          _tiltController.forward(from: 0);
        },
        onExit: (_) {
          setState(() => _isHovered = false);
          _tiltController.reverse();
        },
        onHover: _onHover,
        cursor: widget.onTap != null ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: GestureDetector(
          onTap: widget.onTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final center = Offset(constraints.maxWidth / 2, constraints.maxHeight / 2);
              
              // حساب الميلان 3D
              double rotateX = 0;
              double rotateY = 0;
              
              if (_isHovered) {
                // تقليل الميلان ليكون أنعم واحترافي جداً
                rotateX = ((_mousePosition.dy - center.dy) / center.dy) * -0.015;
                rotateY = ((_mousePosition.dx - center.dx) / center.dx) * 0.015;
              }

              final transform = Matrix4.identity()
                ..setEntry(3, 2, 0.001) // تأثير المنظور
                ..rotateX(rotateX)
                ..rotateY(rotateY)
                ..scale(_isHovered ? 1.01 : 1.0);

              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutBack,
                transform: transform,
                transformAlignment: FractionalOffset.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: _isHovered
                      ? [
                          BoxShadow(
                            color: AppColors.primary.withOpacity(0.08),
                            blurRadius: 24,
                            offset: const Offset(0, 8),
                          )
                        ]
                      : [
                          BoxShadow(
                            color: AppColors.black.withOpacity(0.02),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: Stack(
                    children: [
                      // الكرت الزجاجي الأساسي (خلفية مقروءة وواضحة)
                      GlassContainer(
                        padding: widget.padding ?? const EdgeInsets.all(20),
                        borderRadius: BorderRadius.circular(20),
                        color: widget.isSelected
                            ? AppColors.primary.withOpacity(0.03)
                            : AppColors.white.withOpacity(0.95),
                        borderColor: widget.isSelected
                            ? AppColors.primary.withOpacity(0.3)
                            : _isHovered
                                ? AppColors.primary.withOpacity(0.1)
                                : AppColors.white.withOpacity(0.8),
                        child: widget.child,
                      ),
                      
                      // تأثير التوهج الضوئي المتبع للماوس (أكثر نعومة واحترافية)
                      if (_isHovered)
                        Positioned(
                          left: _mousePosition.dx - 100,
                          top: _mousePosition.dy - 100,
                          child: IgnorePointer(
                            child: Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary.withOpacity(0.02),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.primary.withOpacity(0.02),
                                    blurRadius: 40,
                                    spreadRadius: 10,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
