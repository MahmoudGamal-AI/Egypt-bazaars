import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:iconsax/iconsax.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/colors.dart';
import '../../../providers/auth_provider.dart';
import '../../../app/app_shell.dart';
import 'onboarding_screen.dart';
import 'login_screen.dart';

/// Ultra-Premium Cinematic Splash Screen
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _mainController;
  late AnimationController _shimmerController;
  late AnimationController _bgController;

  late Animation<double> _logoScale;
  late Animation<double> _logoOpacity;
  late Animation<double> _textOpacity;
  late Animation<Offset> _textSlide;

  @override
  void initState() {
    super.initState();
    
    // Main Entry Animation (2 seconds for a luxurious reveal)
    _mainController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    // Continuous Shimmer Animation for the metallic sweep effect
    _shimmerController = AnimationController(
      duration: const Duration(milliseconds: 2500),
      vsync: this,
    )..repeat();

    // Very slow background rotation for cinematic parallax feel
    _bgController = AnimationController(
      duration: const Duration(seconds: 15),
      vsync: this,
    )..repeat();

    // Staggered luxury animations
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainController, curve: const Interval(0.0, 0.4, curve: Curves.easeOut)),
    );
    _logoScale = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(parent: _mainController, curve: const Interval(0.0, 0.6, curve: Curves.elasticOut)),
    );
    
    _textOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _mainController, curve: const Interval(0.3, 0.8, curve: Curves.easeOut)),
    );
    _textSlide = Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
      CurvedAnimation(parent: _mainController, curve: const Interval(0.3, 0.8, curve: Curves.easeOutCubic)),
    );

    _mainController.forward();
    
    // Navigate immediately when the main reveal animation finishes
    _mainController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _navigateToNextScreen();
      }
    });
  }

  Future<void> _navigateToNextScreen() async {
    if (!mounted) return;
    
    // Fast background auth check
    final authProvider = context.read<AuthProvider>();
    final prefs = await SharedPreferences.getInstance();
    final bool onboardingSeen = prefs.getBool('onboarding_seen') ?? false;
    final isLoggedIn = authProvider.isAuthenticated;

    Widget nextScreen;
    if (isLoggedIn) {
      nextScreen = const AppShell();
    } else if (onboardingSeen) {
      nextScreen = const LoginScreen();
    } else {
      nextScreen = const OnboardingScreen();
    }

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => nextScreen,
        transitionDuration: const Duration(milliseconds: 1000), // Cinematic crossfade transition
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(
            opacity: CurvedAnimation(parent: animation, curve: Curves.easeInOut),
            child: child,
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    _mainController.dispose();
    _shimmerController.dispose();
    _bgController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF080808), // True obsidian black for maximum contrast
      body: Stack(
        children: [
          // 1. Premium Cinematic Geometric Background Effect (Highly Performant Canvas)
          AnimatedBuilder(
            animation: _bgController,
            builder: (context, child) {
              return Transform.rotate(
                angle: _bgController.value * 2 * math.pi,
                child: Transform.scale(
                  scale: 1.5,
                  child: CustomPaint(
                    painter: _PremiumBackgroundPainter(
                      color: AppColors.gold.withOpacity(0.04),
                    ),
                    size: Size.infinite,
                  ),
                ),
              );
            },
          ),
          
          // 2. Glowing Ambient Corner Orbs
          Positioned(
            top: MediaQuery.of(context).size.height * 0.1,
            left: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: AppColors.primaryOrange.withOpacity(0.12), blurRadius: 150, spreadRadius: 50),
                ],
              ),
            ),
          ),
          Positioned(
            bottom: MediaQuery.of(context).size.height * 0.1,
            right: -100,
            child: Container(
              width: 300,
              height: 300,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: AppColors.gold.withOpacity(0.08), blurRadius: 150, spreadRadius: 50),
                ],
              ),
            ),
          ),

          // 3. Central Content Reveal
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Metallic Shimmering Logo
                ScaleTransition(
                  scale: _logoScale,
                  child: FadeTransition(
                    opacity: _logoOpacity,
                    child: _buildShimmer(
                      child: Container(
                        padding: const EdgeInsets.all(28),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 1.5),
                        ),
                        child: const Icon(
                          Iconsax.shop, 
                          color: Colors.white,
                          size: 60,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 50),
                
                // Elegant Luxury Typography
                SlideTransition(
                  position: _textSlide,
                  child: FadeTransition(
                    opacity: _textOpacity,
                    child: Column(
                      children: [
                        _buildShimmer(
                          child: const Text(
                            'B A Z A R',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w300,
                              color: Colors.white,
                              letterSpacing: 16.0, // Extreme letter spacing for luxury feel
                              height: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          'بـــــازار',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: AppColors.gold.withOpacity(0.8),
                            letterSpacing: 8.0,
                            height: 1.0,
                          ),
                        ),
                        const SizedBox(height: 60),
                        
                        // Ultra-minimal loading line
                        SizedBox(
                          width: 120,
                          height: 1.5,
                          child: LinearProgressIndicator(
                            backgroundColor: Colors.white.withOpacity(0.05),
                            valueColor: AlwaysStoppedAnimation<Color>(AppColors.gold.withOpacity(0.6)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // High-performance Metallic Shimmer Shader
  Widget _buildShimmer({required Widget child}) {
    return AnimatedBuilder(
      animation: _shimmerController,
      builder: (context, _) {
        return ShaderMask(
          blendMode: BlendMode.srcIn,
          shaderCallback: (bounds) {
            return LinearGradient(
              colors: [
                AppColors.gold.withOpacity(0.8),
                const Color(0xFFFFF7D6), // Brilliant gold/white shine
                AppColors.gold.withOpacity(0.8),
              ],
              stops: const [0.0, 0.5, 1.0],
              begin: Alignment(-1.0 + (_shimmerController.value * 3), -0.5),
              end: Alignment(0.0 + (_shimmerController.value * 3), 0.5),
            ).createShader(bounds);
          },
          child: child,
        );
      },
      child: child,
    );
  }
}

// Ultra-lightweight Custom Painter for Premium Geometric Background
class _PremiumBackgroundPainter extends CustomPainter {
  final Color color;

  _PremiumBackgroundPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) * 0.8;

    // Draw an intricate luxury mandala/geometric pattern (Zero performance overhead)
    for (int i = 0; i < 12; i++) {
      final angle = (i * math.pi) / 6;
      final path = Path();
      
      // Draw intersecting elegant curves mimicking Egyptian geometry
      path.moveTo(center.dx, center.dy);
      path.quadraticBezierTo(
        center.dx + math.cos(angle + math.pi / 4) * radius * 0.5,
        center.dy + math.sin(angle + math.pi / 4) * radius * 0.5,
        center.dx + math.cos(angle) * radius,
        center.dy + math.sin(angle) * radius,
      );
      
      canvas.drawPath(path, paint);
      
      // Draw subtle concentric circles
      canvas.drawCircle(center, radius * (i / 12), paint..strokeWidth = 0.5);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

