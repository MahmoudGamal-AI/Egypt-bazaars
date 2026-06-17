import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

/// 🤖 Owner AI Service — التواصل مع API الـ AI
/// ✅ Production-ready: Auth, retry, configurable URL, error handling
class OwnerAIService {
  // ✅ FIX C1: Configurable base URL — يتغير فعلاً عند استدعاء setBaseUrl
  static String _baseUrl =
      'https://yzva78jty2.execute-api.us-east-1.amazonaws.com/prod/api/owner/ai';

  /// تعيين URL الخاص بالـ Backend (للإنتاج أو التطوير)
  static void setBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
    debugPrint('🔗 AI Base URL updated: $_baseUrl');
  }

  static String get baseUrl => _baseUrl;

  // ✅ FIX C2: Firebase Auth token لكل request
  static Future<Map<String, String>> _getHeaders() async {
    final headers = <String, String>{
      'Content-Type': 'application/json',
      'Accept': 'application/json',
    };

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final token = await user.getIdToken();
        if (token != null) {
          headers['Authorization'] = 'Bearer $token';
        }
      }
    } catch (e) {
      debugPrint('⚠️ Failed to get auth token: $e');
    }

    return headers;
  }

  // ============================================================
  // 🔄 Smart HTTP with retry + error handling
  // ============================================================

  static Future<Map<String, dynamic>> _postWithRetry(
    String endpoint,
    Map<String, dynamic> body, {
    Duration timeout = const Duration(seconds: 45),
    int maxRetries = 1,
  }) async {
    Exception? lastError;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final headers = await _getHeaders();
        final response = await http
            .post(
              Uri.parse('$_baseUrl/$endpoint'),
              headers: headers,
              body: jsonEncode(body),
            )
            .timeout(timeout);

        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        } else if (response.statusCode == 401) {
          throw AIServiceException('غير مصرح — سجل دخول مرة أخرى', 401);
        } else if (response.statusCode == 429) {
          throw AIServiceException(
              'طلبات كثيرة — حاول بعد لحظات', 429);
        } else if (response.statusCode >= 500) {
          lastError = AIServiceException(
              'خطأ في الخادم — حاول لاحقاً', response.statusCode);
          if (attempt < maxRetries) {
            await Future.delayed(
                Duration(milliseconds: 500 * (attempt + 1)));
            continue;
          }
        } else {
          throw AIServiceException(
              'خطأ: ${response.statusCode}', response.statusCode);
        }
      } on TimeoutException {
        lastError = AIServiceException('انتهت المهلة — حاول مرة أخرى', 0);
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        }
      } catch (e) {
        if (e is AIServiceException) rethrow;
        lastError = AIServiceException('فشل الاتصال بالخادم', 0);
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        }
      }
    }

    throw lastError ?? AIServiceException('خطأ غير متوقع', 0);
  }

  static Future<Map<String, dynamic>> _getWithRetry(
    String endpoint, {
    Duration timeout = const Duration(seconds: 45),
    int maxRetries = 1,
  }) async {
    Exception? lastError;

    for (int attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        final headers = await _getHeaders();
        final response = await http
            .get(Uri.parse('$_baseUrl/$endpoint'), headers: headers)
            .timeout(timeout);

        if (response.statusCode == 200) {
          return jsonDecode(response.body);
        } else if (response.statusCode == 401) {
          throw AIServiceException('غير مصرح — سجل دخول مرة أخرى', 401);
        } else if (response.statusCode >= 500) {
          lastError = AIServiceException(
              'خطأ في الخادم — حاول لاحقاً', response.statusCode);
          if (attempt < maxRetries) {
            await Future.delayed(
                Duration(milliseconds: 500 * (attempt + 1)));
            continue;
          }
        } else {
          throw AIServiceException(
              'خطأ: ${response.statusCode}', response.statusCode);
        }
      } on TimeoutException {
        lastError = AIServiceException('انتهت المهلة — حاول مرة أخرى', 0);
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        }
      } catch (e) {
        if (e is AIServiceException) rethrow;
        lastError = AIServiceException('فشل الاتصال بالخادم', 0);
        if (attempt < maxRetries) {
          await Future.delayed(Duration(milliseconds: 500 * (attempt + 1)));
          continue;
        }
      }
    }

    throw lastError ?? AIServiceException('خطأ غير متوقع', 0);
  }

  // ============================================================
  // 1. Generate Product Description
  // ============================================================

  static Future<Map<String, dynamic>> generateDescription({
    required String productName,
    String? category,
    String? material,
    String? imageUrl,
    String? bazaarId,
    String? extraDetails,
  }) async {
    return _postWithRetry('generate-description', {
      'product_name': productName,
      'category': category,
      'material': material,
      'image_url': imageUrl,
      'bazaar_id': bazaarId,
      'extra_details': extraDetails,
    });
  }

  // ============================================================
  // 2. Suggest Price
  // ============================================================

  static Future<Map<String, dynamic>> suggestPrice({
    required String productName,
    required String category,
    String? material,
    String? bazaarId,
  }) async {
    return _postWithRetry(
      'suggest-price',
      {
        'product_name': productName,
        'category': category,
        'material': material,
        'bazaar_id': bazaarId,
      },
      timeout: const Duration(seconds: 30),
    );
  }

  // ============================================================
  // 3. Suggest Replies
  // ============================================================

  static Future<Map<String, dynamic>> suggestReplies({
    required String customerMessage,
    String? customerName,
    String? context,
    String? bazaarId,
  }) async {
    return _postWithRetry(
      'suggest-replies',
      {
        'customer_message': customerMessage,
        'customer_name': customerName,
        'context': context,
        'bazaar_id': bazaarId,
      },
      timeout: const Duration(seconds: 30),
    );
  }

  // ============================================================
  // 4. Daily Digest
  // ============================================================

  static Future<Map<String, dynamic>> getDailyDigest(String bazaarId) async {
    return _getWithRetry('daily-digest/$bazaarId');
  }

  // ============================================================
  // 5. Analytics
  // ============================================================

  static Future<Map<String, dynamic>> getAnalytics(
    String bazaarId, {
    String period = 'week',
  }) async {
    return _getWithRetry('analytics/$bazaarId?period=$period');
  }

  // ============================================================
  // 6. Generate Content
  // ============================================================

  static Future<Map<String, dynamic>> generateContent({
    required String contentType,
    String? productName,
    String? offerDetails,
    String? bazaarName,
    String targetAudience = 'tourists',
    String language = 'ar',
  }) async {
    return _postWithRetry(
      'generate-content',
      {
        'content_type': contentType,
        'product_name': productName,
        'offer_details': offerDetails,
        'bazaar_name': bazaarName,
        'target_audience': targetAudience,
        'language': language,
      },
      timeout: const Duration(seconds: 30),
    );
  }

  // ============================================================
  // 7. Product Suggestions
  // ============================================================

  static Future<Map<String, dynamic>> getProductSuggestions(
      String bazaarId) async {
    return _getWithRetry('product-suggestions/$bazaarId');
  }

  // ============================================================
  // 8. Translate
  // ============================================================

  static Future<String> translate({
    required String text,
    String sourceLang = 'ar',
    String targetLang = 'en',
  }) async {
    final result = await _postWithRetry(
      'translate',
      {
        'text': text,
        'source_lang': sourceLang,
        'target_lang': targetLang,
      },
      timeout: const Duration(seconds: 20),
    );
    return result['translated_text'] ?? '';
  }

  // ============================================================
  // 9. Competitor Analysis
  // ============================================================

  static Future<Map<String, dynamic>> getCompetitorAnalysis({
    required String bazaarId,
    String? category,
  }) async {
    return _postWithRetry(
      'competitor-analysis',
      {
        'bazaar_id': bazaarId,
        'category': category,
      },
      timeout: const Duration(seconds: 45),
    );
  }

  // ============================================================
  // 10. Smart Campaign
  // ============================================================

  static Future<Map<String, dynamic>> generateSmartCampaign({
    required String campaignGoal,
    String? bazaarId,
    String? bazaarName,
    String? productName,
  }) async {
    return _postWithRetry(
      'smart-campaign',
      {
        'campaign_goal': campaignGoal,
        'bazaar_id': bazaarId,
        'bazaar_name': bazaarName,
        'product_name': productName,
      },
      timeout: const Duration(seconds: 45),
    );
  }

  // ============================================================
  // 11. Review Analyzer
  // ============================================================

  static Future<Map<String, dynamic>> getReviewAnalysis(
      String bazaarId) async {
    return _getWithRetry(
      'review-analyzer/$bazaarId',
      timeout: const Duration(seconds: 45),
    );
  }

  // ============================================================
  // 12. Inventory Alerts
  // ============================================================

  static Future<Map<String, dynamic>> getInventoryAlerts(
      String bazaarId) async {
    return _getWithRetry(
      'inventory-alerts/$bazaarId',
      timeout: const Duration(seconds: 40),
    );
  }
}

/// Custom exception for AI service errors
class AIServiceException implements Exception {
  final String message;
  final int statusCode;

  AIServiceException(this.message, this.statusCode);

  @override
  String toString() => message;
}
