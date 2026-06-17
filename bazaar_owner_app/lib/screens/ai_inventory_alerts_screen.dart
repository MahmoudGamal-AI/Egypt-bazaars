import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import '../core/constants/colors.dart';
import '../providers/auth_provider.dart';
import '../providers/ai_tools_cache_provider.dart';

/// 📦 شاشة تنبيهات المخزون الذكية
/// ✅ UPGRADED: Uses AIToolsCacheProvider — loads once, caches until refresh
class AIInventoryAlertsScreen extends StatefulWidget {
  const AIInventoryAlertsScreen({super.key});

  @override
  State<AIInventoryAlertsScreen> createState() => _AIInventoryAlertsScreenState();
}

class _AIInventoryAlertsScreenState extends State<AIInventoryAlertsScreen> {
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
      final result = await cache.loadInventoryAlerts(bazaarId);
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
      final result = await cache.loadInventoryAlerts(bazaarId, force: true);
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
    final lastRefresh = cache.lastRefreshLabel('inventory');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 130,
            pinned: true,
            backgroundColor: const Color(0xFF2D3436),
            flexibleSpace: FlexibleSpaceBar(
              title: const Text('تنبيهات المخزون',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF2D3436), Color(0xFF636E72)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight)),
                child: const Center(
                  child: Icon(Iconsax.box_1, size: 60, color: Colors.white24)),
              ),
            ),
            actions: [
              if (_isLoading)
                const Padding(padding: EdgeInsets.all(16),
                  child: SizedBox(width: 20, height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
              else
                IconButton(
                  icon: const Icon(Iconsax.refresh, color: Colors.white),
                  onPressed: _forceRefresh, tooltip: 'تحديث'),
            ],
          ),
          if (_isLoading && _data == null)
            const SliverFillRemaining(
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                CircularProgressIndicator(color: AppColors.primary),
                SizedBox(height: 16),
                Text('جاري تحليل المخزون...', style: TextStyle(color: AppColors.textSecondary)),
              ])),
            )
          else if (_data == null && _error != null)
            SliverFillRemaining(
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Iconsax.warning_2, size: 48, color: AppColors.error),
                const SizedBox(height: 16),
                Text(_error!, style: const TextStyle(color: AppColors.error), textAlign: TextAlign.center),
                const SizedBox(height: 16),
                ElevatedButton(onPressed: _forceRefresh, child: const Text('إعادة المحاولة')),
              ])),
            )
          else if (_data == null)
            const SliverFillRemaining(
              child: Center(child: Text('حدث خطأ غير متوقع')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(delegate: SliverChildListDelegate([
                if (lastRefresh.isNotEmpty) _buildRefreshBadge(lastRefresh),
                const SizedBox(height: 12),
                _buildHealthBanner(),
                const SizedBox(height: 16),
                if (_data?['summary'] != null && (_data!['summary'] as String).isNotEmpty)
                  _buildSummary(),
                _buildSection('🔴 يحتاج إعادة تخزين عاجل', _data?['restock_urgent'], _buildRestockCard),
                _buildSection('🟡 مخزون زائد', _data?['overstock_warnings'], _buildOverstockCard),
                _buildSection('🟢 مخزون صحي', _data?['healthy_stock'], _buildHealthyCard),
                const SizedBox(height: 80),
              ])),
            ),
        ],
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

  Widget _buildHealthBanner() {
    final health = _data?['overall_health'] ?? 'unknown';
    final color = health == 'good' ? AppColors.success
        : health == 'warning' ? AppColors.warning : AppColors.error;
    final icon = health == 'good' ? '✅' : health == 'warning' ? '⚠️' : '🚨';
    final label = health == 'good' ? 'المخزون بحالة جيدة'
        : health == 'warning' ? 'المخزون يحتاج انتباه' : 'حالة حرجة!';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [color.withOpacity(0.15), color.withOpacity(0.05)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(children: [
        Text(icon, style: const TextStyle(fontSize: 36)),
        const SizedBox(width: 16),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: color)),
          Text('آخر تحديث: الآن', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
        ])),
      ]),
    );
  }

  Widget _buildSummary() => Container(
    margin: const EdgeInsets.only(bottom: 16),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)]),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Icon(Iconsax.info_circle, size: 20, color: AppColors.info),
      const SizedBox(width: 10),
      Expanded(child: Text(_data!['summary'], style: const TextStyle(fontSize: 14, height: 1.5))),
    ]),
  );

  Widget _buildSection(String title, List<dynamic>? items, Widget Function(Map<String, dynamic>) builder) {
    if (items == null || items.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      ),
      ...items.map((item) => builder(Map<String, dynamic>.from(item))),
    ]);
  }

  Widget _buildRestockCard(Map<String, dynamic> item) {
    final urgency = item['urgency'] ?? 'critical';
    final color = urgency == 'critical' ? AppColors.error : AppColors.warning;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        border: Border(right: BorderSide(color: color, width: 4)),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(item['product_name'] ?? '',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700))),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(6)),
            child: Text(urgency == 'critical' ? 'حرج' : 'تحذير',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: color)),
          ),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _miniStat('المخزون', '${item['current_stock'] ?? 0}', color),
          _miniStat('يومي', '${(item['daily_sales_rate'] ?? 0).toStringAsFixed(1)}', AppColors.info),
          _miniStat('ينفذ خلال', '${item['days_until_stockout'] ?? 0} يوم', AppColors.error),
          _miniStat('اطلب', '${item['suggested_reorder'] ?? 0}', AppColors.success),
        ]),
      ]),
    );
  }

  Widget _buildOverstockCard(Map<String, dynamic> item) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(16),
      border: const Border(right: BorderSide(color: AppColors.warning, width: 4)),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(item['product_name'] ?? '', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      const SizedBox(height: 8),
      Row(children: [
        _miniStat('مخزون', '${item['current_stock'] ?? 0}', AppColors.warning),
        _miniStat('يكفي', '${item['days_of_supply'] ?? 0} يوم', AppColors.warning),
      ]),
      if (item['suggested_discount'] != null) ...[
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: AppColors.warning.withOpacity(0.06), borderRadius: BorderRadius.circular(10)),
          child: Row(children: [
            const Icon(Iconsax.discount_shape, size: 16, color: AppColors.warning),
            const SizedBox(width: 8),
            Text('خصم مقترح: ${item['suggested_discount']}',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
          ]),
        ),
      ],
    ]),
  );

  Widget _buildHealthyCard(Map<String, dynamic> item) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(14),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
    child: Row(children: [
      const Icon(Iconsax.tick_circle, size: 20, color: AppColors.success),
      const SizedBox(width: 12),
      Expanded(child: Text(item['product_name'] ?? '',
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
      Text('${item['current_stock'] ?? 0} وحدة',
          style: TextStyle(fontSize: 12, color: Colors.grey[500])),
    ]),
  );

  Widget _miniStat(String label, String value, Color color) => Expanded(
    child: Column(children: [
      Text(value, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
      Text(label, style: TextStyle(fontSize: 10, color: Colors.grey[500])),
    ]),
  );
}
