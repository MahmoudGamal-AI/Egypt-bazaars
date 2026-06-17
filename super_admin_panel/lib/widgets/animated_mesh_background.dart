import 'dart:math';
import 'package:flutter/material.dart';
import 'dart:ui';
import '../core/constants/colors.dart';

/// خلفية ديناميكية متحركة (Animated Mesh / Glowing Orbs)
/// توفر تأثيراً بصرياً مبهراً (مثل تصميمات Web3 و Apple) للحفاظ على الشعور بالحياة داخل التطبيق.
class AnimatedMeshBackground extends StatefulWidget {
  const AnimatedMeshBackground({super.key});

  @override
  State<AnimatedMeshBackground> createState() => _AnimatedMeshBackgroundState();
}

class _AnimatedMeshBackgroundState extends State<AnimatedMeshBackground>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final Random random = Random();

  // Orbs properties
  late List<_Orb> _orbs;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();

    _initializeOrbs();
  }

  void _initializeOrbs() {
    _orbs = [
      _Orb(color: AppColors.primary.withOpacity(0.4), size: 400, radius: 1.0, speed: 1.5, angle: 0.0),
      _Orb(color: const Color(0xFF6366F1).withOpacity(0.3), size: 500, radius: 1.5, speed: -1.0, angle: 2.0),
      _Orb(color: AppColors.secondary.withOpacity(0.3), size: 300, radius: 0.8, speed: 2.0, angle: 4.0),
      _Orb(color: const Color(0xFFEC4899).withOpacity(0.25), size: 450, radius: 1.2, speed: -1.5, angle: 5.5),
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // استخدم RepaintBoundary لضمان ألا يتم إعادة رسم باقي الواجهة إذا لم تتغير
    return RepaintBoundary(
      child: Stack(
        children: [
          // خلفية أساسية
          Container(
            color: AppColors.background,
          ),
          
          // الكرات المتحركة
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Stack(
                children: _orbs.map((orb) {
                  // تحريك دائري (Lissajous curves) لتبدو الحركة طبيعية
                  final x = sin(_controller.value * 2 * pi * orb.speed + orb.angle) * orb.radius;
                  final y = cos(_controller.value * 2 * pi * orb.speed * 0.8 + orb.angle) * orb.radius;
                  
                  return Align(
                    alignment: Alignment(x, y),
                    child: Container(
                      width: orb.size,
                      height: orb.size,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: orb.color,
                      ),
                    ),
                  );
                }).toList(),
              );
            },
          ),

          // فلتر زجاجي لتنعيم الكرات وجعلها تبدو كأنها شبكة متدرجة (Mesh)
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 100.0, sigmaY: 100.0),
              child: Container(
                color: AppColors.background.withOpacity(0.6), // لدمج الألوان بهدوء
              ),
            ),
          ),
          
          // طبقة ضوضاء خفيفة جداً (Noise) للإحساس المتميز
          Positioned.fill(
            child: Opacity(
              opacity: 0.03, // شفافية خفيفة جداً
              child: Image.network(
                'https://www.transparenttextures.com/patterns/stardust.png',
                repeat: ImageRepeat.repeat,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Orb {
  final Color color;
  final double size;
  final double radius;
  final double speed;
  final double angle;

  _Orb({
    required this.color,
    required this.size,
    required this.radius,
    required this.speed,
    required this.angle,
  });
}
