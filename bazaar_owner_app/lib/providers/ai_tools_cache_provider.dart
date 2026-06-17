import 'package:flutter/material.dart';
import '../services/ai_service.dart';

/// 🧰 AI Tools Cache Provider — Per-tool smart caching
///
/// Caches results of AI tool endpoints (competitor, reviews, inventory)
/// so re-visiting the screen doesn't re-fetch data.
/// Each tool has independent cache with 30-minute TTL.
class AIToolsCacheProvider extends ChangeNotifier {
  // === Cache entries per tool ===
  final Map<String, _ToolCache> _cache = {};

  static const Duration _cacheTTL = Duration(minutes: 30);

  // ============================================================
  // Generic Cache Logic
  // ============================================================

  /// Check if a tool has cached (non-stale) data
  bool hasFreshData(String toolKey) {
    final entry = _cache[toolKey];
    if (entry == null) return false;
    return DateTime.now().difference(entry.timestamp) < _cacheTTL;
  }

  /// Get cached data for a tool
  Map<String, dynamic>? getData(String toolKey) => _cache[toolKey]?.data;

  /// Get last refresh timestamp for a tool
  DateTime? getLastRefresh(String toolKey) => _cache[toolKey]?.timestamp;

  /// Loading state per tool
  final Map<String, bool> _loadingState = {};
  bool isLoading(String toolKey) => _loadingState[toolKey] ?? false;

  /// Human-readable last refresh
  String lastRefreshLabel(String toolKey) {
    final ts = _cache[toolKey]?.timestamp;
    if (ts == null) return '';
    final diff = DateTime.now().difference(ts);
    if (diff.inSeconds < 60) return 'منذ لحظات';
    if (diff.inMinutes < 60) return 'منذ ${diff.inMinutes} دقيقة';
    if (diff.inHours < 24) return 'منذ ${diff.inHours} ساعة';
    return 'منذ ${diff.inDays} يوم';
  }

  // ============================================================
  // Competitor Analysis
  // ============================================================

  Future<Map<String, dynamic>?> loadCompetitorAnalysis(String bazaarId, {bool force = false}) async {
    const key = 'competitor';
    if (!force && hasFreshData(key)) return getData(key);
    if (isLoading(key)) return getData(key);

    _loadingState[key] = true;
    notifyListeners();

    try {
      final result = await OwnerAIService.getCompetitorAnalysis(bazaarId: bazaarId);
      _cache[key] = _ToolCache(data: result, timestamp: DateTime.now());
      _loadingState[key] = false;
      notifyListeners();
      return result;
    } catch (e) {
      _loadingState[key] = false;
      notifyListeners();
      rethrow;
    }
  }

  // ============================================================
  // Review Analysis
  // ============================================================

  Future<Map<String, dynamic>?> loadReviewAnalysis(String bazaarId, {bool force = false}) async {
    const key = 'reviews';
    if (!force && hasFreshData(key)) return getData(key);
    if (isLoading(key)) return getData(key);

    _loadingState[key] = true;
    notifyListeners();

    try {
      final result = await OwnerAIService.getReviewAnalysis(bazaarId);
      _cache[key] = _ToolCache(data: result, timestamp: DateTime.now());
      _loadingState[key] = false;
      notifyListeners();
      return result;
    } catch (e) {
      _loadingState[key] = false;
      notifyListeners();
      rethrow;
    }
  }

  // ============================================================
  // Inventory Alerts
  // ============================================================

  Future<Map<String, dynamic>?> loadInventoryAlerts(String bazaarId, {bool force = false}) async {
    const key = 'inventory';
    if (!force && hasFreshData(key)) return getData(key);
    if (isLoading(key)) return getData(key);

    _loadingState[key] = true;
    notifyListeners();

    try {
      final result = await OwnerAIService.getInventoryAlerts(bazaarId);
      _cache[key] = _ToolCache(data: result, timestamp: DateTime.now());
      _loadingState[key] = false;
      notifyListeners();
      return result;
    } catch (e) {
      _loadingState[key] = false;
      notifyListeners();
      rethrow;
    }
  }

  /// Clear all caches (e.g., on logout)
  void clearAll() {
    _cache.clear();
    _loadingState.clear();
    notifyListeners();
  }
}

class _ToolCache {
  final Map<String, dynamic> data;
  final DateTime timestamp;
  _ToolCache({required this.data, required this.timestamp});
}
