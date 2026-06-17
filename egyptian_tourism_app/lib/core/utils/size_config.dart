import 'package:flutter/material.dart';
import 'dart:math' as math;

/// A lightweight utility for responsive sizing across different screen sizes.
/// This mimics the behavior of popular responsive packages but remains dependency-free.
class SizeConfig {
  static late MediaQueryData _mediaQueryData;
  static late double screenWidth;
  static late double screenHeight;
  static late double textScaleFactor;
  static late Orientation orientation;
  static bool _isInitialized = false;

  // Base design size (e.g., iPhone 13/14 base dimensions used by many designers)
  static const double designWidth = 390.0;
  static const double designHeight = 844.0;

  static void init(BuildContext context) {
    _mediaQueryData = MediaQuery.of(context);
    screenWidth = _mediaQueryData.size.width;
    screenHeight = _mediaQueryData.size.height;
    textScaleFactor = _mediaQueryData.textScaler.scale(1);
    orientation = _mediaQueryData.orientation;
    _isInitialized = true;
  }

  static bool get isInitialized => _isInitialized;
}

extension ResponsiveSize on num {
  /// Calculates the proportional height based on screen height.
  /// Prevents extreme scaling on tablets by capping.
  double get h {
    if (!SizeConfig.isInitialized) return toDouble();
    return (this / SizeConfig.designHeight) * SizeConfig.screenHeight;
  }

  /// Calculates the proportional width based on screen width.
  double get w {
    if (!SizeConfig.isInitialized) return toDouble();
    return (this / SizeConfig.designWidth) * SizeConfig.screenWidth;
  }

  /// Calculates proportional font size. 
  /// Uses a scale factor that prevents text from becoming unreadably small or comically large on tablets.
  double get sp {
    if (!SizeConfig.isInitialized) return toDouble();
    final scale = math.min(
      SizeConfig.screenWidth / SizeConfig.designWidth,
      SizeConfig.screenHeight / SizeConfig.designHeight,
    );
    return this * scale;
  }
}
