import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import '../core/constants/colors.dart';
import '../providers/auth_provider.dart';
import '../providers/ai_tools_cache_provider.dart';

/// 🏆 شاشة التحليل التنافسي — Competitor Intelligence Dashboard
/// ✅ UPGRADED: Uses AIToolsCacheProvider — loads once, caches until refresh
class AICompetitorScreen extends StatefulWidget {
  const AICompetitorScreen({super.key});

  @override
  State<AICompetitorScreen> createState() => _AICompetitorScreenState();
}

class _AICompetitorScreenState extends State<AICompetitorScreen>
    with SingleTickerProviderStateMixin {
  Map<String, dynamic>? _data;
  bool _isLoading = true;
  String? _error;
  late AnimationController _animController;
  bool _initialLoadDone = false;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadDone) {
      _initialLoadDone = true;
      _autoLoad();
    }
  }

  @override
  void dispose() { _animController.dispose(); super.dispose(); }

  Future<void> _autoLoad() async {
    final bazaarId = context.read<BazaarAuthProvider>().user?.bazaarId;
    if (bazaarId == null) return;
    final cache = context.read<AIToolsCacheProvider>();

    setState(() { _isLoading = true; _error = null; });
    try {
      final result = await cache.loadCompetitorAnalysis(bazaarId);
      if (mounted) {
        setState(() { _data = result; _isLoading = false; });
        _animController.forward(from: 0);
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  Future<void> _forceRefresh() async {
    final bazaarId = context.read<BazaarAuthProvider>().user?.bazaarId;
    if (bazaarId == null) return;
    final cache = context.read<AIToolsCacheProvider>();

    setState(() { _isLoading = true; _error = null; });
    try {
      final result = await cache.loadCompetitorAnalysis(bazaarId, force: true);
      if (mounted) {
        setState(() { _data = result; _isLoading = false; });
        _animController.forward(from: 0);
      }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cache = context.watch<AIToolsCacheProvider>();
    final lastRefresh = cache.lastRefreshLabel('competitor');

    return Scaffold(
      backgroundColor: AppColors.background,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverAppBar(
            expandedHeight: 130,
            pinned: true,
            backgroundColor: const Color(0xFF1A1A2E),
            flexibleSpace: FlexibleSpaceBar(
              title: const Text('التحليل التنافسي',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
              background: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [Color(0xFF1A1A2E), Color(0xFF16213E), Color(0xFF0F3460)],
                    begin: Alignment.topLeft, end: Alignment.bottomRight,
                  ),
                ),
                child: const Center(
                  child: Icon(Iconsax.chart_215, size: 60, color: Colors.white24),
                ),
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
              child: Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: AppColors.primary),
                  SizedBox(height: 16),
                  Text('جاري تحليل السوق...', style: TextStyle(color: AppColors.textSecondary)),
                ],
              )),
            )
          else if (_error != null && _data == null)
            SliverFillRemaining(
              child: Center(child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Iconsax.warning_2, size: 48, color: AppColors.error),
                  const SizedBox(height: 12),
                  Text(_error!, style: const TextStyle(color: AppColors.textSecondary)),
                  const SizedBox(height: 16),
                  ElevatedButton(onPressed: _forceRefresh, child: const Text('إعادة المحاولة')),
                ],
              )),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.all(16),
              sliver: SliverList(delegate: SliverChildListDelegate([
                if (lastRefresh.isNotEmpty)
                  _buildRefreshBadge(lastRefresh),
                const SizedBox(height: 12),
                _buildPositionCard(),
                const SizedBox(height: 16),
                _buildSwotSection(),
                const SizedBox(height: 16),
                _buildActionItems(),
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

  Widget _buildPositionCard() {
    final position = _data?['market_position'] ?? 'unknown';
    final priceComp = _data?['price_comparison'] ?? {};
    final posColor = position == 'leader' ? AppColors.success
        : position == 'competitive' ? AppColors.info : AppColors.warning;
    final posLabel = position == 'leader' ? '🏆 رائد السوق'
        : position == 'competitive' ? '⚡ منافس قوي' : '📈 يحتاج تحسين';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [posColor.withOpacity(0.15), posColor.withOpacity(0.05)]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: posColor.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(posLabel, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: posColor)),
        const SizedBox(height: 12),
        if (priceComp.isNotEmpty) ...[
          _infoRow('💰 متوسط سعرك', '${priceComp['owner_avg'] ?? 0} ج.م'),
          _infoRow('📊 متوسط السوق', '${priceComp['market_avg'] ?? 0} ج.م'),
          _infoRow('📍 موقعك', priceComp['position'] ?? '—'),
          if (priceComp['recommendation'] != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: Row(children: [
                  const Icon(Iconsax.lamp_charge, color: AppColors.warning, size: 20),
                  const SizedBox(width: 8),
                  Expanded(child: Text(priceComp['recommendation'],
                      style: const TextStyle(fontSize: 13, height: 1.5))),
                ]),
              ),
            ),
        ],
      ]),
    );
  }

  Widget _infoRow(String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(fontSize: 14)),
      Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
    ]),
  );

  Widget _buildSwotSection() {
    final strengths = List<String>.from(_data?['strengths'] ?? []);
    final weaknesses = List<String>.from(_data?['weaknesses'] ?? []);
    final opportunities = List<String>.from(_data?['opportunities'] ?? []);

    return Column(children: [
      _swotCard('💪 نقاط القوة', strengths, AppColors.success),
      const SizedBox(height: 12),
      _swotCard('⚠️ نقاط الضعف', weaknesses, AppColors.error),
      const SizedBox(height: 12),
      _swotCard('🚀 الفرص', opportunities, AppColors.info),
    ]);
  }

  Widget _swotCard(String title, List<String> items, Color color) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(16),
      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12)],
    ),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
      const SizedBox(height: 10),
      if (items.isEmpty)
        const Text('لا توجد بيانات', style: TextStyle(color: AppColors.textHint, fontSize: 13))
      else
        ...items.map((item) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              margin: const EdgeInsets.only(top: 6),
              width: 6, height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(child: Text(item, style: const TextStyle(fontSize: 14, height: 1.5))),
          ]),
        )),
    ]),
  );

  Widget _buildActionItems() {
    final actions = List<Map<String, dynamic>>.from(
        (_data?['action_items'] as List?)?.map((e) => Map<String, dynamic>.from(e)) ?? []);
    if (actions.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 12)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('🎯 خطة العمل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        ...actions.asMap().entries.map((entry) {
          final action = entry.value;
          final priority = action['priority'] ?? 'medium';
          final pColor = priority == 'high' ? AppColors.error : AppColors.warning;
          final pLabel = priority == 'high' ? 'عاجل' : 'متوسط';

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: pColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: pColor.withOpacity(0.2)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: pColor.withOpacity(0.15), borderRadius: BorderRadius.circular(6)),
                  child: Text(pLabel, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: pColor)),
                ),
                const Spacer(),
                Text('#${entry.key + 1}', style: TextStyle(fontSize: 12, color: Colors.grey[400])),
              ]),
              const SizedBox(height: 8),
              Text(action['action'] ?? '', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, height: 1.4)),
              if (action['expected_impact'] != null) ...[
                const SizedBox(height: 6),
                Text('📈 ${action['expected_impact']}',
                    style: TextStyle(fontSize: 12, color: Colors.grey[600], height: 1.4)),
              ],
            ]),
          );
        }),
      ]),
    );
  }
}
