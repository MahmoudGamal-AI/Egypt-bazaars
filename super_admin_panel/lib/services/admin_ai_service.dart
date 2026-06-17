import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// 🤖 Admin AI Service — Professional Client for Backend AI APIs
/// ✅ Retry logic, connection health check, response caching, error diagnostics
class AdminAIService {
  static String _baseUrl =
      'https://al5bhgldsf.execute-api.us-east-1.amazonaws.com/prod/api/admin/ai';

  static final Map<String, _CachedResponse> _cache = {};
  static const Duration _cacheTTL = Duration(minutes: 5);
  static const int _maxRetries = 2;
  static const Duration _retryDelay = Duration(seconds: 2);
  static const Duration _timeout = Duration(seconds: 30);

  /// Set API base URL
  static void setBaseUrl(String url) {
    _baseUrl = url;
    _cache.clear(); // Clear cache on URL change
    debugPrint('🔗 AdminAI base URL set to: $url');
  }

  static String get baseUrl => _baseUrl;

  // ═══════════════════════════════════════════════════════════════
  // Connection Health
  // ═══════════════════════════════════════════════════════════════

  /// Check if AI backend is reachable
  static Future<AIHealthStatus> checkHealth() async {
    try {
      // Extract the base server URL (remove /api/admin/ai suffix)
      final serverUrl = _baseUrl.replaceAll('/api/admin/ai', '');
      final response = await http
          .get(Uri.parse('$serverUrl/health'))
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return AIHealthStatus(
          isOnline: true,
          status: data['status'] ?? 'unknown',
          ragReady: data['rag'] == 'ready',
          activeSessions: data['active_sessions'] ?? 0,
        );
      }
      return AIHealthStatus(isOnline: false, status: 'unreachable');
    } catch (e) {
      return AIHealthStatus(
          isOnline: false, status: 'error', error: e.toString());
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Chat
  // ═══════════════════════════════════════════════════════════════

  /// Send message and get full response
  static Future<Map<String, dynamic>> sendMessage(String message,
      {String sessionId = 'admin_default'}) async {
    return _postWithRetry('/chat', {
      'message': message,
      'session_id': sessionId,
    });
  }

  /// Stream chat response via SSE
  static Stream<String> streamMessage(String message,
      {String sessionId = 'admin_default'}) async* {
    final url = Uri.parse('$_baseUrl/chat/stream');
    try {
      final client = http.Client();
      try {
        final request = http.Request('POST', url);
        request.headers['Content-Type'] = 'application/json';
        request.body = json.encode({
          'message': message,
          'session_id': sessionId,
        });

        final streamedResponse =
            await client.send(request).timeout(_timeout);

        if (streamedResponse.statusCode != 200) {
          yield '⚠️ خطأ في الاتصال (${streamedResponse.statusCode})';
          return;
        }

        await for (final chunk
            in streamedResponse.stream.transform(utf8.decoder)) {
          // Parse SSE events
          final lines = chunk.split('\n');
          for (final line in lines) {
            if (line.startsWith('data: ')) {
              final data = line.substring(6).trim();
              if (data == '[DONE]') return;
              try {
                final parsed = json.decode(data);
                if (parsed is Map) {
                  final type = parsed['type'];
                  if (type == 'chunk') {
                    yield parsed['content'] ?? '';
                  } else if (type == 'status') {
                    // Prefix with special indicator for the UI to know it's a status
                    yield '__STATUS__:${parsed['status']}';
                  } else if (type == 'done') {
                    if (parsed.containsKey('quick_actions')) {
                      final actions = json.encode(parsed['quick_actions']);
                      yield '__ACTIONS__:$actions';
                    }
                    return;
                  } else if (type == 'error') {
                    yield '⚠️ ${parsed['content']}';
                    return;
                  }
                } else {
                  // Fallback for unexpected formats
                  yield data;
                }
              } catch (_) {
                if (data.isNotEmpty) yield data;
              }
            }
          }
        }
      } finally {
        client.close();
      }
    } catch (e) {
      yield '⚠️ خطأ في الاتصال: ${e.toString().substring(0, (e.toString().length).clamp(0, 100))}';
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // Dashboard APIs
  // ═══════════════════════════════════════════════════════════════

  /// Get business report with caching
  static Future<Map<String, dynamic>> getBusinessReport(
      {String period = 'month'}) async {
    final cacheKey = 'report_$period';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final result = _postWithRetry('/business-report', {'period': period});
    result.then((data) => _setCache(cacheKey, data));
    return result;
  }

  /// Get platform insights with caching
  static Future<Map<String, dynamic>> getPlatformInsights() async {
    const cacheKey = 'platform_insights';
    final cached = _getFromCache(cacheKey);
    if (cached != null) return cached;

    final result = await _getWithRetry('/platform-insights');
    _setCache(cacheKey, result);
    return result;
  }

  /// Force refresh — clears cache
  static Future<List<Map<String, dynamic>>> refreshDashboard(
      {String period = 'month'}) async {
    _cache.clear();
    final results = await Future.wait([
      getBusinessReport(period: period),
      getPlatformInsights(),
    ]);
    return results;
  }

  // ═══════════════════════════════════════════════════════════════
  // Moderation
  // ═══════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> moderateProduct(
      String productId) async {
    return _postWithRetry('/moderate/$productId', {});
  }

  static Future<Map<String, dynamic>> analyzeApplication(
      String applicationId) async {
    return _postWithRetry('/analyze-application/$applicationId', {});
  }

  static Future<Map<String, dynamic>> generateMessage({
    required String messageType,
    required String bazaarName,
    String? context,
    String? customNotes,
  }) async {
    return _postWithRetry('/generate-message', {
      'message_type': messageType,
      'bazaar_name': bazaarName,
      if (context != null) 'context': context,
      if (customNotes != null) 'custom_notes': customNotes,
    });
  }

  static Future<Map<String, dynamic>> suggestPromotions() async {
    return _getWithRetry('/suggest-promotions');
  }

  // ═══════════════════════════════════════════════════════════════
  // Internal HTTP Helpers with Retry Logic
  // ═══════════════════════════════════════════════════════════════

  static Future<Map<String, dynamic>> _postWithRetry(
      String endpoint, Map<String, dynamic> body) async {
    Exception? lastException;

    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        if (attempt > 0) {
          await Future.delayed(_retryDelay * attempt);
          debugPrint('🔄 Retry attempt $attempt for POST $endpoint');
        }

        final response = await http
            .post(
              Uri.parse('$_baseUrl$endpoint'),
              headers: {'Content-Type': 'application/json'},
              body: json.encode(body),
            )
            .timeout(_timeout);

        if (response.statusCode == 200) {
          return json.decode(response.body) as Map<String, dynamic>;
        } else {
          throw AIServiceException(
            'HTTP ${response.statusCode}',
            statusCode: response.statusCode,
            body: response.body,
          );
        }
      } on TimeoutException {
        lastException = AIServiceException(
            'انتهت مهلة الاتصال. تأكد من اتصال الإنترنت.',
            statusCode: 408);
      } catch (e) {
        lastException = e is AIServiceException
            ? e
            : AIServiceException('خطأ في الشبكة: ${e.toString().substring(0, (e.toString().length).clamp(0, 150))}');
      }
    }

    throw lastException ??
        AIServiceException('فشل الاتصال بعد $_maxRetries محاولات');
  }

  static Future<Map<String, dynamic>> _getWithRetry(String endpoint) async {
    Exception? lastException;

    for (int attempt = 0; attempt <= _maxRetries; attempt++) {
      try {
        if (attempt > 0) {
          await Future.delayed(_retryDelay * attempt);
        }

        final response = await http
            .get(Uri.parse('$_baseUrl$endpoint'))
            .timeout(_timeout);

        if (response.statusCode == 200) {
          return json.decode(response.body) as Map<String, dynamic>;
        } else {
          throw AIServiceException(
            'HTTP ${response.statusCode}',
            statusCode: response.statusCode,
            body: response.body,
          );
        }
      } on TimeoutException {
        lastException = AIServiceException('انتهت مهلة الاتصال',
            statusCode: 408);
      } catch (e) {
        lastException = e is AIServiceException
            ? e
            : AIServiceException('خطأ في الشبكة: ${e.toString().substring(0, (e.toString().length).clamp(0, 150))}');
      }
    }

    throw lastException ??
        AIServiceException('فشل الاتصال بعد $_maxRetries محاولات');
  }

  // ═══════════════════════════════════════════════════════════════
  // Cache Management
  // ═══════════════════════════════════════════════════════════════

  static Map<String, dynamic>? _getFromCache(String key) {
    final cached = _cache[key];
    if (cached != null && DateTime.now().difference(cached.timestamp) < _cacheTTL) {
      debugPrint('📦 Cache hit: $key');
      return cached.data;
    }
    _cache.remove(key);
    return null;
  }

  static void _setCache(String key, Map<String, dynamic> data) {
    _cache[key] = _CachedResponse(data: data, timestamp: DateTime.now());
  }

  static void clearCache() => _cache.clear();
}

// ═══════════════════════════════════════════════════════════════
// Models
// ═══════════════════════════════════════════════════════════════

class AIHealthStatus {
  final bool isOnline;
  final String status;
  final bool ragReady;
  final int activeSessions;
  final String? error;

  AIHealthStatus({
    required this.isOnline,
    required this.status,
    this.ragReady = false,
    this.activeSessions = 0,
    this.error,
  });
}

class AIServiceException implements Exception {
  final String message;
  final int? statusCode;
  final String? body;

  AIServiceException(this.message, {this.statusCode, this.body});

  @override
  String toString() => 'AIServiceException: $message (status: $statusCode)';
}

class _CachedResponse {
  final Map<String, dynamic> data;
  final DateTime timestamp;

  _CachedResponse({required this.data, required this.timestamp});
}
