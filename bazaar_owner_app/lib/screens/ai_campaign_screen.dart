import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import '../core/constants/colors.dart';
import '../providers/auth_provider.dart';
import '../services/ai_service.dart';
import '../widgets/premium_ui/premium_ui.dart';

/// 🚀 شاشة الحملات التسويقية الذكية
class AICampaignScreen extends StatefulWidget {
  const AICampaignScreen({super.key});

  @override
  State<AICampaignScreen> createState() => _AICampaignScreenState();
}

class _AICampaignScreenState extends State<AICampaignScreen> {
  Map<String, dynamic>? _campaign;
  bool _isLoading = false;
  String _selectedGoal = 'sales_boost';
  int _selectedVariant = 1; // balanced by default

  final List<Map<String, dynamic>> _goals = [
    {'key': 'sales_boost', 'label': 'زيادة المبيعات', 'icon': Iconsax.chart_2, 'color': AppColors.success},
    {'key': 'new_customers', 'label': 'عملاء جدد', 'icon': Iconsax.people, 'color': AppColors.info},
    {'key': 'clearance', 'label': 'تصفية مخزون', 'icon': Iconsax.box_remove, 'color': AppColors.warning},
    {'key': 'seasonal', 'label': 'موسمية', 'icon': Iconsax.calendar_1, 'color': const Color(0xFF9B59B6)},
  ];

  Future<void> _generate() async {
    setState(() => _isLoading = true);
    try {
      final auth = context.read<BazaarAuthProvider>();
      final result = await OwnerAIService.generateSmartCampaign(
        campaignGoal: _selectedGoal,
        bazaarId: auth.user?.bazaarId,
        bazaarName: auth.user?.name,
      );
      setState(() { _campaign = result; _isLoading = false; });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('❌ $e'), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('حملات تسويقية ذكية'),
        backgroundColor: Colors.white, elevation: 0,
        centerTitle: true,
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        physics: const BouncingScrollPhysics(),
        children: [
          // Goal Selector
          const Text('🎯 اختر هدف الحملة', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 2,
            mainAxisSpacing: 10, crossAxisSpacing: 10,
            childAspectRatio: 2.2,
            children: _goals.map((g) {
              final isSelected = g['key'] == _selectedGoal;
              final color = g['color'] as Color;
              return GestureDetector(
                onTap: () => setState(() => _selectedGoal = g['key']),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isSelected ? color.withOpacity(0.12) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isSelected ? color : Colors.grey[200]!, width: isSelected ? 2 : 1),
                    boxShadow: isSelected ? [BoxShadow(color: color.withOpacity(0.15), blurRadius: 12)] : [],
                  ),
                  child: Row(children: [
                    Icon(g['icon'] as IconData, color: color, size: 22),
                    const SizedBox(width: 10),
                    Expanded(child: Text(g['label'],
                        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                            color: isSelected ? color : AppColors.textPrimary))),
                  ]),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),

          // Generate Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _generate,
              icon: _isLoading
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Iconsax.magic_star, size: 20),
              label: Text(_isLoading ? 'جاري التوليد...' : '🚀 توليد الحملة'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ),
          const SizedBox(height: 24),

          // Campaign Result
          if (_campaign != null) ...[
            // Campaign Name
            SizedBox(
              width: double.infinity,
              child: PremiumGlassCard(
                color: AppColors.primary.withOpacity(0.9),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('✨ الحملة المقترحة',
                      style: TextStyle(fontSize: 12, color: Colors.white70)),
                  const SizedBox(height: 6),
                  Text(_campaign!['campaign_name'] ?? 'حملة ذكية',
                      style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: Colors.white)),
                  const SizedBox(height: 8),
                  Text(_campaign!['strategy'] ?? '',
                      style: const TextStyle(fontSize: 14, color: Colors.white70, height: 1.5)),
                ]),
              ),
            ),
            const SizedBox(height: 16),

            // Variant Selector
            const Text('📋 اختر مستوى الحملة', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),
            Row(
              children: List.generate(3, (i) {
                final labels = ['آمنة', 'متوازنة', 'قوية'];
                final icons = ['🛡️', '⚖️', '🔥'];
                final isActive = _selectedVariant == i;
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedVariant = i),
                    child: Container(
                      margin: EdgeInsets.only(left: i > 0 ? 8 : 0),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isActive ? AppColors.primary.withOpacity(0.1) : Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive ? AppColors.primary : Colors.grey[200]!, width: isActive ? 2 : 1),
                      ),
                      child: Column(children: [
                        Text(icons[i], style: const TextStyle(fontSize: 20)),
                        const SizedBox(height: 4),
                        Text(labels[i], style: TextStyle(fontSize: 12,
                            fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                            color: isActive ? AppColors.primary : AppColors.textSecondary)),
                      ]),
                    ),
                  ),
                );
              }),
            ),
            const SizedBox(height: 16),

            // Selected Variant Details
            _buildVariantCard(),
            const SizedBox(height: 16),

            // Hashtags
            if ((_campaign!['hashtags'] as List?)?.isNotEmpty == true)
              _buildHashtags(),
            const SizedBox(height: 80),
          ],
        ],
      ),
    );
  }

  Widget _buildVariantCard() {
    final variants = List<Map<String, dynamic>>.from(
        (_campaign?['variants'] as List?)?.map((e) => Map<String, dynamic>.from(e)) ?? []);
    if (variants.isEmpty || _selectedVariant >= variants.length) {
      return const SizedBox.shrink();
    }
    final v = variants[_selectedVariant];

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 16)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(v['label'] ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.info.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
            child: Text('${v['duration_days'] ?? 7} يوم', style: const TextStyle(fontSize: 12, color: AppColors.info)),
          ),
        ]),
        const SizedBox(height: 14),
        // Social post preview
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA), borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.grey[200]!),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Iconsax.instagram, size: 16, color: Color(0xFFE1306C)),
              SizedBox(width: 6),
              Text('معاينة البوست', style: TextStyle(fontSize: 12, color: AppColors.textHint)),
            ]),
            const SizedBox(height: 10),
            Text(v['social_post'] ?? '', style: const TextStyle(fontSize: 14, height: 1.6)),
          ]),
        ),
        const SizedBox(height: 12),
        if (v['discount_suggestion'] != null)
          _detailRow('🏷️ الخصم', v['discount_suggestion']),
        if (v['estimated_reach'] != null)
          _detailRow('👥 الوصول المتوقع', v['estimated_reach']),
        if (v['budget_hint'] != null)
          _detailRow('💵 الميزانية', v['budget_hint']),
        const SizedBox(height: 14),
        // Copy button
        PremiumAnimatedButton(
          height: 50,
          onPressed: () {
            Clipboard.setData(ClipboardData(text: v['social_post'] ?? ''));
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('✅ تم نسخ البوست'), backgroundColor: AppColors.success));
          },
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Iconsax.copy, size: 18, color: Colors.white),
              SizedBox(width: 8),
              Text('نسخ البوست', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _detailRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(fontSize: 13)),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          value,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          textAlign: TextAlign.end,
        ),
      ),
    ]),
  );

  Widget _buildHashtags() {
    final tags = List<String>.from(_campaign?['hashtags'] ?? []);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white, borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10)],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('# هاشتاقات مقترحة', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
        const SizedBox(height: 10),
        Wrap(spacing: 8, runSpacing: 8, children: tags.map((tag) => GestureDetector(
          onTap: () {
            Clipboard.setData(ClipboardData(text: tag));
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('تم نسخ $tag'), duration: const Duration(seconds: 1)));
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF667eea).withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFF667eea).withOpacity(0.2)),
            ),
            child: Text(tag, style: const TextStyle(fontSize: 13, color: Color(0xFF667eea))),
          ),
        )).toList()),
      ]),
    );
  }
}
