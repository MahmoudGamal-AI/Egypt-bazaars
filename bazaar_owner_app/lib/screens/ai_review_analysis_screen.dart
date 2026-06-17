import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/constants/colors.dart';
import '../providers/auth_provider.dart';
import '../providers/ai_tools_cache_provider.dart';

/// ⭐ شاشة تحليل المراجعات الذكية
/// ✅ UPGRADED: Uses AIToolsCacheProvider — loads once, caches until refresh
class AIReviewAnalysisScreen extends StatefulWidget {
  const AIReviewAnalysisScreen({super.key});

  @override
  State<AIReviewAnalysisScreen> createState() => _AIReviewAnalysisScreenState();
}

class _AIReviewAnalysisScreenState extends State<AIReviewAnalysisScreen> {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;
  bool _initialLoadDone = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadDone) {
      _initialLoadDone = true;
      _autoLoad();
    }
  }

  Future<void> _autoLoad() async {
    final bazaarId = context.read<BazaarAuthProvider>().user?.bazaarId;
    if (bazaarId == null) return;
    final cache = context.read<AIToolsCacheProvider>();

    setState(() { _isLoading = true; _error = null; });
    try {
      final result = await cache.loadReviewAnalysis(bazaarId);
      if (mounted) setState(() { _data = result; _isLoading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  Future<void> _forceRefresh() async {
    final bazaarId = context.read<BazaarAuthProvider>().user?.bazaarId;
    if (bazaarId == null) return;
    final cache = context.read<AIToolsCacheProvider>();

    setState(() { _isLoading = true; _error = null; });
    try {
      final result = await cache.loadReviewAnalysis(bazaarId, force: true);
      if (mounted) setState(() { _data = result; _isLoading = false; });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<AIToolsCacheProvider>();
    final lastRefresh = cache.lastRefreshLabel('reviews');

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('تحليل المراجعات'),
        backgroundColor: Colors.white, elevation: 0, centerTitle: true,
        actions: [
          if (_isLoading)
            const Padding(padding: EdgeInsets.all(16),
              child: SizedBox(width: 20, height: 20,
                child: CircularProgressIndicator(strokeWidth: 2)))
          else
            IconButton(icon: const Icon(Iconsax.refresh), onPressed: _forceRefresh, tooltip: 'تحديث'),
        ],
      ),
      body: _isLoading && _data == null
          ? const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(height: 16),
              Text('جاري تحليل آراء العملاء...', style: TextStyle(color: AppColors.textSecondary)),
            ]))
          : _data == null && _error != null
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Iconsax.warning_2, size: 48, color: AppColors.error),
                  const SizedBox(height: 16),
                  Text(_error!, style: const TextStyle(color: AppColors.error), textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _forceRefresh, child: const Text('إعادة المحاولة')),
                ]))
              : _data == null
                  ? const Center(child: Text('حدث خطأ غير متوقع'))
                  : RefreshIndicator(
                  onRefresh: _forceRefresh,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    physics: const BouncingScrollPhysics(),
                    children: [
                      if (lastRefresh.isNotEmpty) _buildRefreshBadge(lastRefresh),
                      const SizedBox(height: 12),
                      _buildHealthBadge(),
                      const SizedBox(height: 16),
                      _buildSentimentChart(),
                      const SizedBox(height: 16),
                      _buildTopPraised(),
                      const SizedBox(height: 16),
                      _buildTopComplaints(),
                      const SizedBox(height: 16),
                      _buildPriorityActions(),
                      const SizedBox(height: 16),
                      _buildSuggestedResponses(),
                      const SizedBox(height: 80),
                    ],
                  ),
                ),
    );
  }

  Widget _buildRefreshBadge(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
    decoration: BoxDecoration(
      color: AppColors.success.withOpacity(0.08),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: AppColors.success.withOpacity(0.2)),
    ),
    child: Row(children: [
      const Icon(Iconsax.tick_circle, size: 14, color: AppColors.success),
      const SizedBox(width: 8),
      Text('✅ آخر تحديث: $label',
          style: const TextStyle(fontSize: 11, color: AppColors.success, fontWeight: FontWeight.w600)),
      const Spacer(),
      GestureDetector(
        onTap: _forceRefresh,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
          child: const Text('تحديث', style: TextStyle(fontSize: 10, color: AppColors.primary, fontWeight: FontWeight.w700)),
        ),
      ),
    ]),
  );

  Widget _buildHealthBadge() {
    final health = _data?['overall_health'] ?? 'unknown';
    final total = _data?['total_reviews'] ?? 0;
    final color = health == 'excellent' ? AppColors.success
        : health == 'good' ? AppColors.info
        : health == 'needs_attention' ? AppColors.warning : AppColors.error;
    final label = health == 'excellent' ? '⭐ ممتاز'
        : health == 'good' ? '👍 جيد'
        : health == 'needs_attention' ? '⚠️ يحتاج اهتمام'
        : health == 'no_data' ? '📭 لا توجد مراجعات' : '🔴 حرج';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withOpacity(0.12), color.withOpacity(0.04)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Container(
          width: 60, height: 60,
          decoration: BoxDecoration(
            color: color.withOpacity(0.15), shape: BoxShape.circle),
          child: Center(child: Text(label.substring(0, 2), style: const TextStyle(fontSize: 26))),
        ),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text('$total مراجعة', style: const TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        ])),
      ]),
    );
  }

  Widget _buildSentimentChart() {
    final breakdown = Map<String, dynamic>.from(_data?['sentiment_breakdown'] ?? {});
    final pos = (breakdown['positive'] ?? 0).toDouble();
    final neu = (breakdown['neutral'] ?? 0).toDouble();
    final neg = (breakdown['negative'] ?? 0).toDouble();
    final total = pos + neu + neg;
    if (total == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12)],
      ),
      child: Column(children: [
        const Text('توزيع المشاعر', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 20),
        SizedBox(
          height: 180,
          child: PieChart(PieChartData(
            sectionsSpace: 3,
            centerSpaceRadius: 40,
            sections: [
              PieChartSectionData(
                value: pos, color: AppColors.success,
                title: '${(pos / total * 100).toStringAsFixed(0)}%',
                radius: 50, titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              PieChartSectionData(
                value: neu, color: AppColors.warning,
                title: '${(neu / total * 100).toStringAsFixed(0)}%',
                radius: 50, titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
              PieChartSectionData(
                value: neg, color: AppColors.error,
                title: '${(neg / total * 100).toStringAsFixed(0)}%',
                radius: 50, titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white)),
            ],
          )),
        ),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _legendItem('إيجابي', pos.toInt(), AppColors.success),
          _legendItem('محايد', neu.toInt(), AppColors.warning),
          _legendItem('سلبي', neg.toInt(), AppColors.error),
        ]),
      ]),
    );
  }

  Widget _legendItem(String label, int count, Color color) => Row(children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
    const SizedBox(width: 6),
    Text('$label ($count)', style: const TextStyle(fontSize: 12)),
  ]);

  Widget _buildTopPraised() {
    final items = List<String>.from(_data?['top_praised'] ?? []);
    if (items.isEmpty) return const SizedBox.shrink();
    return _listCard('💚 الأكثر مدحاً', items, AppColors.success);
  }

  Widget _buildTopComplaints() {
    final items = List<String>.from(_data?['top_complaints'] ?? []);
    if (items.isEmpty) return const SizedBox.shrink();
    return _listCard('💔 أبرز الشكاوى', items, AppColors.error);
  }

  Widget _listCard(String title, List<String> items, Color color) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12)]),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
      const SizedBox(height: 10),
      ...items.map((item) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(margin: const EdgeInsets.only(top: 6), width: 6, height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 10),
          Expanded(child: Text(item, style: const TextStyle(fontSize: 14, height: 1.5))),
        ]),
      )),
    ]),
  );

  Widget _buildPriorityActions() {
    final actions = List<Map<String, dynamic>>.from(
        (_data?['priority_actions'] as List?)?.map((e) => Map<String, dynamic>.from(e)) ?? []);
    if (actions.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🎯 إجراءات مطلوبة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ...actions.map((a) {
          final urgency = a['urgency'] ?? 'medium';
          final uColor = urgency == 'high' ? AppColors.error : urgency == 'low' ? AppColors.success : AppColors.warning;
          return Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: uColor.withOpacity(0.06), borderRadius: BorderRadius.circular(12),
              border: Border.all(color: uColor.withOpacity(0.2))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(a['action'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
              if (a['reason'] != null) ...[
                const SizedBox(height: 4),
                Text(a['reason'], style: TextStyle(fontSize: 12, color: Colors.grey[600])),
              ],
            ]),
          );
        }),
      ]),
    );
  }

  Widget _buildSuggestedResponses() {
    final responses = List<Map<String, dynamic>>.from(
        (_data?['suggested_responses'] as List?)?.map((e) => Map<String, dynamic>.from(e)) ?? []);
    if (responses.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12)]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('💬 ردود مقترحة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        const SizedBox(height: 12),
        ...responses.map((r) => Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('لـ: ${r['for'] ?? ''}', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
            const SizedBox(height: 6),
            Text(r['response'] ?? '', style: const TextStyle(fontSize: 14, height: 1.5)),
          ]),
        )),
      ]),
    );
  }
}
