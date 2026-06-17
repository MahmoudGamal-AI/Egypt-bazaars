import 'package:flutter/material.dart';
import '../services/ai_service.dart';

/// 🧠 AI Insights Provider — Smart Caching & State Management
///
/// Professional-grade provider that:
/// - Auto-loads analytics ONCE on first access
/// - Caches data in memory across screen navigations
/// - Only re-fetches when user manually taps "refresh"
/// - Supports per-period caching (day/week/month/quarter)
/// - Auto-refreshes after 30 minutes TTL
/// - Tracks loading/error states cleanly
class AIInsightsProvider extends ChangeNotifier {
  // === Cache Storage (per period) ===
  final Map<String, _CachedData> _cache = {};

  // === State ===
  Map<String, dynamic>? _analytics;
  bool _isLoading = false;
  bool _hasError = false;
  String? _errorMessage;
  String _currentPeriod = 'week';
  DateTime? _lastRefresh;

  // === Cache TTL: 30 minutes ===
  static const Duration _cacheTTL = Duration(minutes: 30);

  // === Getters ===
  Map<String, dynamic>? get analytics => _analytics;
  bool get isLoading => _isLoading;
  bool get hasError => _hasError;
  String? get errorMessage => _errorMessage;
  String get currentPeriod => _currentPeriod;
  DateTime? get lastRefresh => _lastRefresh;
  bool get hasData => _analytics != null;

  /// How long ago was the last refresh (human-readable)
  String get lastRefreshLabel {
    if (_lastRefresh == null) return '';
    final diff = DateTime.now().difference(_lastRefresh!);
    if (diff.inSeconds < 60) return 'منذ لحظات';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    return 'منذ ${diff.inDays} يوم';
  }

  /// Is the cache stale (older than TTL)?
  bool get _isCacheStale {
    final cached = _cache[_currentPeriod];
    if (cached == null) return true;
    return DateTime.now().difference(cached.timestamp) > _cacheTTL;
  }

  /// Load analytics — uses cache if available, otherwise fetches
  /// Called automatically on first screen visit
  Future<void> loadAnalytics(String bazaarId, {bool forceRefresh = false}) async {
    // If we have fresh cache and not forcing refresh, use it
    if (!forceRefresh && !_isCacheStale) {
      final cached = _cache[_currentPeriod];
      if (cached != null) {
        _analytics = cached.data;
        _hasError = false;
        _errorMessage = null;
        _lastRefresh = cached.timestamp;
        notifyListeners();
        return;
      }
    }

    // Don't double-load
    if (_isLoading) return;

    _isLoading = true;
    _hasError = false;
    _errorMessage = null;
    notifyListeners();

    try {
      final data = await OwnerAIService.getAnalytics(
        bazaarId,
        period: _currentPeriod,
      );

      // Store in cache
      _cache[_currentPeriod] = _CachedData(
        data: data,
        timestamp: DateTime.now(),
      );

      _analytics = data;
      _lastRefresh = DateTime.now();
      _isLoading = false;
      _hasError = false;
    } catch (e) {
      debugPrint('AIInsightsProvider: Error loading analytics: $e');
      _isLoading = false;
      _hasError = true;
      _errorMessage = e.toString();

      // If we have old cache, still show it
      final oldCache = _cache[_currentPeriod];
      if (oldCache != null) {
        _analytics = oldCache.data;
        _lastRefresh = oldCache.timestamp;
      }
    }

    notifyListeners();
  }

  /// Change period and load new data (only fetches if no cache for this period)
  Future<void> changePeriod(String period, String bazaarId) async {
    if (period == _currentPeriod && !_isCacheStale) return;
    _currentPeriod = period;
    await loadAnalytics(bazaarId);
  }

  /// Force refresh — user manually taps refresh button
  Future<void> refresh(String bazaarId) async {
    await loadAnalytics(bazaarId, forceRefresh: true);
  }

  /// Clear all cache (e.g., on logout)
  void clearCache() {
    _cache.clear();
    _analytics = null;
    _lastRefresh = null;
    _hasError = false;
    _errorMessage = null;
    notifyListeners();
  }
}

/// Internal cache entry
class _CachedData {
  final Map<String, dynamic> data;
  final DateTime timestamp;

  _CachedData({required this.data, required this.timestamp});
}
