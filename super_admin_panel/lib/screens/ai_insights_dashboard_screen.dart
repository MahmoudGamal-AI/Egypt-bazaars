import 'dart:async';
import 'dart:math';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../core/constants/colors.dart';
import '../core/theme/app_theme.dart';
import '../services/admin_ai_service.dart';
import '../widgets/shimmer_loading.dart';

/// 🧠 AI Insights Dashboard — Premium Executive View
class AIInsightsDashboardScreen extends StatefulWidget {
  const AIInsightsDashboardScreen({super.key});
  @override
  State<AIInsightsDashboardScreen> createState() => _AIInsightsDashboardScreenState();
}

class _AIInsightsDashboardScreenState extends State<AIInsightsDashboardScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _report;
  Map<String, dynamic>? _insights;
  bool _isLoading = true;
  String? _error;
  String _selectedPeriod = 'month';
  late AnimationController _fadeCtrl;
  late AnimationController _pulseCtrl;
  final _fmt = NumberFormat('#,###', 'ar');

  String _formatShortNumber(double num) {
    if (num >= 1000000) return '${(num / 1000000).toStringAsFixed(1)}M';
    if (num >= 1000) return '${(num / 1000).toStringAsFixed(1)}K';
    return num.toInt().toString();
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 1000))..forward();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 3))..repeat(reverse: true);
    _loadData();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() { _isLoading = true; _error = null; });
    try {
      final results = await AdminAIService.refreshDashboard(period: _selectedPeriod);
      if (mounted) {
        setState(() { _report = results[0]; _insights = results[1]; _isLoading = false; });
        _fadeCtrl.forward(from: 0);
      }
    } catch (e) {
      if (mounted) {
        setState(() { _error = e.toString(); _isLoading = false; });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Container(
        color: AppColors.background,
        child: RefreshIndicator(
        onRefresh: _loadData,
        color: AppColors.primary,
        child: SingleChildScrollView(
          padding: AppSpacing.pagePadding,
          physics: const AlwaysScrollableScrollPhysics(),
          child: FadeTransition(
            opacity: _fadeCtrl,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeader(),
                const SizedBox(height: 32),
                if (_isLoading) _buildLoadingState()
                else if (_error != null) _buildErrorState()
                else ...[
                  _buildMetricsRow(),
                  const SizedBox(height: 32),
                  _buildHealthAndSummary(),
                  const SizedBox(height: 32),
                  _buildChartsRow(),
                  const SizedBox(height: 32),
                  _buildInsightsAndRankings(),
                ],
                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    ));
  }

  Widget _buildHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Row(children: [
          AnimatedBuilder(
            animation: _pulseCtrl,
            builder: (c, _) => Container(
              width: 56, height: 56,
              decoration: BoxDecoration(
                gradient: AppGradients.emerald,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: AppColors.primary.withOpacity(0.2 + _pulseCtrl.value * 0.2), blurRadius: 16 + _pulseCtrl.value * 8, offset: const Offset(0, 4))
                ],
              ),
              child: const Center(child: Text('🧠', style: TextStyle(fontSize: 26))),
            ),
          ),
          const SizedBox(width: 18),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('لوحة التحكم الذكية', style: GoogleFonts.cairo(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary, letterSpacing: -0.5)),
            Text('رؤى مدعومة بالذكاء الاصطناعي لتحسين الأداء', style: GoogleFonts.cairo(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w500)),
          ]),
        ]),
        Row(children: [
          Container(
            height: 42,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: AppColors.divider.withOpacity(0.4))),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _selectedPeriod,
                icon: const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Iconsax.arrow_down_1, size: 16, color: AppColors.primary)),
                style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                dropdownColor: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                items: const [
                  DropdownMenuItem(value: 'week', child: Text('آخر أسبوع')),
                  DropdownMenuItem(value: 'month', child: Text('آخر شهر')),
                  DropdownMenuItem(value: 'quarter', child: Text('آخر ربع سنة')),
                  DropdownMenuItem(value: 'year', child: Text('آخر سنة')),
                ],
                onChanged: (val) {
                  if (val != null && val != _selectedPeriod) {
                    setState(() => _selectedPeriod = val);
                    _loadData();
                  }
                },
              ),
            ),
          ),
          const SizedBox(width: 12),
          _actionChip(Iconsax.document_download, 'تصدير', () {}),
          const SizedBox(width: 12),
          _actionChip(Iconsax.refresh, 'تحديث', _loadData, isPrimary: true),
        ]),
      ],
    );
  }

  Widget _actionChip(IconData icon, String label, VoidCallback onTap, {bool isPrimary = false}) {
    return Material(
      color: isPrimary ? AppColors.primary : AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      elevation: isPrimary ? 4 : 0,
      shadowColor: isPrimary ? AppColors.primary.withOpacity(0.4) : Colors.transparent,
      child: InkWell(
        onTap: onTap, borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 42,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), border: Border.all(color: isPrimary ? Colors.transparent : AppColors.divider.withOpacity(0.4))),
          child: Row(children: [
            Icon(icon, size: 18, color: isPrimary ? Colors.white : AppColors.primary),
            const SizedBox(width: 8),
            Text(label, style: GoogleFonts.cairo(fontSize: 13, fontWeight: FontWeight.w700, color: isPrimary ? Colors.white : AppColors.primary)),
          ]),
        ),
      ),
    );
  }

  // ═══════════════════ Loading & Error ═══════════════════
  Widget _buildLoadingState() {
    return Column(children: [
      const ShimmerStatsRow(count: 4),
      const SizedBox(height: 32),
      Row(children: [
        Expanded(child: _shimmerCard(240)),
        const SizedBox(width: 24),
        Expanded(flex: 2, child: _shimmerCard(240)),
      ]),
      const SizedBox(height: 32),
      _shimmerCard(320),
    ]);
  }

  Widget _shimmerCard(double h) => Container(
    height: h,
    decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(20), boxShadow: AppShadows.card),
    child: ShimmerLoading(
      child: Container(decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(20))),
    ),
  );

  Widget _buildErrorState() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 80),
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(24),
          boxShadow: AppShadows.elevated, border: Border.all(color: AppColors.error.withOpacity(0.1)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 80, height: 80,
            decoration: BoxDecoration(color: AppColors.error.withOpacity(0.08), shape: BoxShape.circle),
            child: const Icon(Iconsax.warning_2, size: 40, color: AppColors.error),
          ),
          const SizedBox(height: 24),
          Text('تعذر تحميل البيانات', style: GoogleFonts.cairo(fontSize: 20, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
          const SizedBox(height: 8),
          Text(_error ?? 'يرجى التحقق من الاتصال والمحاولة مرة أخرى', style: GoogleFonts.cairo(fontSize: 14, color: AppColors.textSecondary), textAlign: TextAlign.center),
          const SizedBox(height: 32),
          ElevatedButton.icon(
            onPressed: _loadData, icon: const Icon(Iconsax.refresh), label: const Text('إعادة المحاولة'),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.primary, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16)),
          ),
        ]),
      ),
    );
  }

  // ═══════════════════ Metrics Row ═══════════════════
  Widget _buildMetricsRow() {
    final m = _report?['key_metrics'] ?? {};
    return Row(children: [
      _metricCard('الإيرادات الإجمالية', '${_fmt.format(m['total_revenue'] ?? 0)} ج.م', Iconsax.wallet_2, AppGradients.revenue, trend: null, isUp: null),
      const SizedBox(width: 20),
      _metricCard('الطلبات المكتملة', _fmt.format(m['delivered_orders'] ?? 0), Iconsax.bag, AppGradients.orders, trend: null, isUp: null),
      const SizedBox(width: 20),
      _metricCard('البازارات النشطة', '${m['active_bazaars'] ?? 0} / ${m['total_bazaars'] ?? 0}', Iconsax.shop, AppGradients.users, trend: null, isUp: null),
      const SizedBox(width: 20),
      _metricCard('إجمالي المنتجات', _fmt.format(m['total_products'] ?? 0), Iconsax.box, AppGradients.products, trend: null, isUp: null),
    ].map((w) => w is SizedBox ? w : Expanded(child: w)).toList());
  }

  Widget _metricCard(String title, String value, IconData icon, LinearGradient gradient, {String? trend, bool? isUp}) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1), duration: const Duration(milliseconds: 800), curve: Curves.easeOutBack,
      builder: (c, v, child) => Transform.translate(offset: Offset(0, 20 * (1 - v)), child: Opacity(opacity: v, child: child)),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppColors.surface, borderRadius: BorderRadius.circular(20),
          boxShadow: AppShadows.card, border: Border.all(color: AppColors.divider.withOpacity(0.4)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(gradient: gradient, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: gradient.colors.first.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 4))]),
              child: Icon(icon, color: Colors.white, size: 22),
            ),
            if (trend != null && isUp != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: (isUp ? AppColors.success : AppColors.error).withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
                child: Row(children: [
                  Icon(isUp ? Iconsax.arrow_up_2 : Iconsax.arrow_down, size: 12, color: isUp ? AppColors.success : AppColors.error),
                  const SizedBox(width: 4),
                  Text(trend, style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w700, color: isUp ? AppColors.success : AppColors.error)),
                ]),
              ),
          ]),
          const SizedBox(height: 20),
          Text(title, style: GoogleFonts.cairo(fontSize: 14, color: AppColors.textSecondary, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(value, style: GoogleFonts.cairo(fontSize: 26, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ]),
      ),
    );
  }

  // ═══════════════════ Health + Summary ═══════════════════
  Widget _buildHealthAndSummary() {
    final healthScore = _insights?['health_score'] ?? 0;
    final summary = _report?['executive_summary'] ?? 'جاري تحليل أداء المنصة...';
    return IntrinsicHeight(
      child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Health Score
      Expanded(child: _premiumCard(
        title: 'صحة المنصة', icon: Iconsax.heart,
        child: Center(child: SizedBox(
          width: 180, height: 180,
          child: Stack(alignment: Alignment.center, children: [
            SizedBox(width: 180, height: 180,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: healthScore / 100), duration: const Duration(milliseconds: 1500), curve: Curves.easeOutCirc,
                builder: (c, v, _) => CircularProgressIndicator(
                  value: v, strokeWidth: 14, strokeCap: StrokeCap.round,
                  backgroundColor: AppColors.divider.withOpacity(0.3),
                  color: healthScore >= 80 ? AppColors.success : healthScore >= 50 ? AppColors.warning : AppColors.error,
                ),
              ),
            ),
            Column(mainAxisSize: MainAxisSize.min, children: [
              TweenAnimationBuilder<int>(
                tween: IntTween(begin: 0, end: healthScore), duration: const Duration(milliseconds: 1500), curve: Curves.easeOutCirc,
                builder: (c, v, _) => Text('$v%', style: GoogleFonts.cairo(fontSize: 42, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                decoration: BoxDecoration(color: (healthScore >= 80 ? AppColors.success : AppColors.warning).withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                child: Text(healthScore >= 80 ? 'أداء ممتاز' : healthScore >= 50 ? 'أداء مستقر' : 'يحتاج انتباه',
                  style: GoogleFonts.cairo(fontSize: 12, fontWeight: FontWeight.w700, color: healthScore >= 80 ? AppColors.success : AppColors.warning)),
              ),
            ]),
          ]),
        )),
      )),
      const SizedBox(width: 24),
      // Executive Summary
      Expanded(flex: 2, child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          gradient: const LinearGradient(colors: [Color(0xFF0F1419), Color(0xFF1A2332)], begin: Alignment.topLeft, end: Alignment.bottomRight),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.15), blurRadius: 20, offset: const Offset(0, 10))],
        ),
        child: Stack(
          children: [
            Positioned(right: -30, top: -30, child: Icon(Iconsax.star_1, size: 140, color: Colors.white.withOpacity(0.03))),
            Padding(
              padding: const EdgeInsets.all(30),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: Colors.white.withOpacity(0.1), borderRadius: BorderRadius.circular(10)), child: const Icon(Iconsax.document_text_1, color: Colors.white, size: 20)),
                  const SizedBox(width: 12),
                  Text('الملخص التنفيذي الذكي', style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w700, color: Colors.white)),
                ]),
                const SizedBox(height: 24),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(summary.toString(), style: GoogleFonts.cairo(fontSize: 15, height: 1.8, color: Colors.white.withOpacity(0.85))),
                  ),
                ),
              ]),
            ),
          ],
        ),
      )),
    ]),
    );
  }

  // ═══════════════════ Charts ═══════════════════
  Widget _buildChartsRow() {
    final charts = _report?['charts_data'] ?? {};
    final revLine = (charts['revenue_line'] as List?) ?? [];
    final catPie = (charts['categories_pie'] as List?) ?? [];

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 2, child: _premiumCard(
        title: 'الإيرادات خلال الفترة', icon: Iconsax.graph,
        child: SizedBox(height: 280, child: revLine.isEmpty
          ? _emptyState('لا توجد بيانات للإيرادات حالياً')
          : LineChart(LineChartData(
              gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) => FlLine(color: AppColors.divider.withOpacity(0.4), strokeWidth: 1, dashArray: [5, 5])),
              titlesData: FlTitlesData(
                leftTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 56, getTitlesWidget: (v, _) => Text('${_fmt.format(v.toInt())}', style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w600)))),
                bottomTitles: AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 36, interval: max(1, (revLine.length / 7).ceil().toDouble()),
                  getTitlesWidget: (v, _) {
                    final i = v.toInt();
                    if (i < 0 || i >= revLine.length) return const SizedBox.shrink();
                    final d = revLine[i]['date']?.toString() ?? '';
                    return Padding(padding: const EdgeInsets.only(top: 10), child: Text(d.length >= 10 ? d.substring(5) : d, style: GoogleFonts.cairo(fontSize: 11, color: AppColors.textTertiary, fontWeight: FontWeight.w600)));
                  })),
                topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              borderData: FlBorderData(show: false),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  tooltipBgColor: AppColors.surface,
                  tooltipRoundedRadius: 8,
                  getTooltipItems: (touchedSpots) {
                    return touchedSpots.map((spot) {
                      return LineTooltipItem(
                        '${_fmt.format(spot.y)} ج.م',
                        GoogleFonts.cairo(color: AppColors.primary, fontWeight: FontWeight.w800, fontSize: 12),
                      );
                    }).toList();
                  },
                ),
              ),
              lineBarsData: [LineChartBarData(
                spots: revLine.asMap().entries.map((e) => FlSpot(e.key.toDouble(), (e.value['revenue'] ?? 0).toDouble())).toList(),
                isCurved: true, curveSmoothness: 0.35, color: AppColors.primary, barWidth: 4, isStrokeCapRound: true,
                dotData: FlDotData(show: true, getDotPainter: (spot, percent, barData, index) => FlDotCirclePainter(radius: 4, color: AppColors.surface, strokeWidth: 2, strokeColor: AppColors.primary)),
                belowBarData: BarAreaData(show: true, gradient: LinearGradient(colors: [AppColors.primary.withOpacity(0.3), AppColors.primary.withOpacity(0.0)], begin: Alignment.topCenter, end: Alignment.bottomCenter)),
              )],
            )),
        ),
      )),
      const SizedBox(width: 24),
      Expanded(child: _premiumCard(
        title: 'المبيعات حسب الفئة', icon: Iconsax.chart_2,
        child: SizedBox(height: 280, child: catPie.isEmpty
          ? _emptyState('لا توجد بيانات للفئات')
          : Column(
              children: [
                Expanded(child: PieChart(PieChartData(
                  sectionsSpace: 4, centerSpaceRadius: 40,
                  sections: catPie.asMap().entries.map((e) {
                    final colors = [AppColors.primary, AppColors.secondary, const Color(0xFF8B5CF6), const Color(0xFFF59E0B), AppColors.info, AppColors.error];
                    final color = colors[e.key % colors.length];
                    return PieChartSectionData(
                      value: (e.value['revenue'] ?? 0).toDouble(), title: '', radius: 60,
                      color: color,
                      badgeWidget: Container(
                        padding: const EdgeInsets.all(6), decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, boxShadow: AppShadows.card),
                        child: Text(_formatShortNumber((e.value['revenue'] ?? 0).toDouble()), style: GoogleFonts.cairo(fontSize: 9, fontWeight: FontWeight.w800, color: color)),
                      ),
                      badgePositionPercentageOffset: 1.1,
                    );
                  }).toList(),
                ))),
                const SizedBox(height: 20),
                Wrap(spacing: 12, runSpacing: 8, alignment: WrapAlignment.center, children: catPie.asMap().entries.map((e) {
                  final colors = [AppColors.primary, AppColors.secondary, const Color(0xFF8B5CF6), const Color(0xFFF59E0B), AppColors.info, AppColors.error];
                  return Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 10, height: 10, decoration: BoxDecoration(color: colors[e.key % colors.length], shape: BoxShape.circle)),
                    const SizedBox(width: 6),
                    Text(e.value['category']?.toString() ?? 'أخرى', style: GoogleFonts.cairo(fontSize: 11, fontWeight: FontWeight.w600, color: AppColors.textSecondary)),
                  ]);
                }).toList()),
              ],
            ),
        ),
      )),
    ]);
  }

  // ═══════════════════ Insights + Rankings ═══════════════════
  Widget _buildInsightsAndRankings() {
    final insightsList = (_report?['insights'] as List?) ?? (_insights?['insights'] as List?) ?? [];
    final rankings = (_report?['bazaar_rankings'] as List?) ?? [];

    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // AI Insights
      Expanded(flex: 2, child: _premiumCard(
        title: 'رؤى وتوصيات الذكاء الاصطناعي', icon: Iconsax.lamp,
        child: insightsList.isEmpty
          ? _emptyState('لا توجد رؤى حالياً. النظام يقوم بجمع المزيد من البيانات.')
          : Column(children: insightsList.take(6).map<Widget>((ins) {
              final type = ins['type']?.toString() ?? 'tip';
              final iconMap = {'success': Iconsax.tick_circle, 'warning': Iconsax.warning_2, 'danger': Iconsax.danger, 'tip': Iconsax.lamp};
              final colorMap = {'success': AppColors.success, 'warning': AppColors.warning, 'danger': AppColors.error, 'tip': AppColors.info};
              final color = colorMap[type] ?? AppColors.info;
              return Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: color.withOpacity(0.04), borderRadius: BorderRadius.circular(16), border: Border.all(color: color.withOpacity(0.15))),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle), child: Icon(iconMap[type] ?? Iconsax.lamp, color: color, size: 20)),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    if (ins['title'] != null && ins['title'].toString().isNotEmpty)
                      Text(ins['title'].toString(), style: GoogleFonts.cairo(fontSize: 15, fontWeight: FontWeight.w700, color: AppColors.textPrimary)),
                    const SizedBox(height: 4),
                    Text(ins['text']?.toString() ?? '', style: GoogleFonts.cairo(fontSize: 13, height: 1.6, color: AppColors.textSecondary)),
                  ])),
                ]),
              );
            }).toList()),
      )),
      const SizedBox(width: 24),
      // Bazaar Rankings
      Expanded(child: _premiumCard(
        title: 'أفضل البازارات أداءً', icon: Iconsax.award,
        child: rankings.isEmpty
          ? _emptyState('لا توجد بيانات لترتيب البازارات')
          : Column(children: rankings.take(6).toList().asMap().entries.map<Widget>((e) {
              final r = e.value;
              final rev = (r['revenue'] ?? 0).toDouble();
              final maxRev = rankings.isNotEmpty ? (rankings.first['revenue'] ?? 1).toDouble() : 1;
              final tierColor = e.key == 0 ? const Color(0xFFFFD700) : e.key == 1 ? const Color(0xFFC0C0C0) : e.key == 2 ? const Color(0xFFCD7F32) : AppColors.primary.withOpacity(0.5);
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(color: tierColor.withOpacity(0.15), borderRadius: BorderRadius.circular(10), border: Border.all(color: tierColor.withOpacity(0.3))),
                    child: Center(child: Text('${e.key + 1}', style: GoogleFonts.cairo(fontSize: 16, fontWeight: FontWeight.w800, color: tierColor.withOpacity(1.0)))),
                  ),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(r['name']?.toString() ?? 'بازار', style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textPrimary), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    TweenAnimationBuilder<double>(
                      tween: Tween(begin: 0, end: maxRev > 0 ? rev / maxRev : 0),
                      duration: Duration(milliseconds: 1000 + e.key * 200), curve: Curves.easeOutCirc,
                      builder: (c, v, _) => ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: LinearProgressIndicator(value: v, minHeight: 8, backgroundColor: AppColors.divider.withOpacity(0.3), color: tierColor),
                      ),
                    ),
                  ])),
                  const SizedBox(width: 16),
                  Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('${_fmt.format(rev.toInt())}', style: GoogleFonts.cairo(fontSize: 14, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
                    Text('ج.م', style: GoogleFonts.cairo(fontSize: 10, fontWeight: FontWeight.w600, color: AppColors.textTertiary)),
                  ]),
                ]),
              );
            }).toList()),
      )),
    ]);
  }

  // ═══════════════════ Widgets ═══════════════════
  Widget _premiumCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        color: AppColors.surface, borderRadius: BorderRadius.circular(24),
        boxShadow: AppShadows.card, border: Border.all(color: AppColors.divider.withOpacity(0.3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: AppColors.primary.withOpacity(0.08), borderRadius: BorderRadius.circular(10)), child: Icon(icon, size: 20, color: AppColors.primary)),
          const SizedBox(width: 12),
          Text(title, style: GoogleFonts.cairo(fontSize: 18, fontWeight: FontWeight.w800, color: AppColors.textPrimary)),
        ]),
        const SizedBox(height: 24),
        child,
      ]),
    );
  }

  Widget _emptyState(String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Iconsax.chart_2, size: 50, color: AppColors.textTertiary.withOpacity(0.3)),
        const SizedBox(height: 16),
        Text(msg, style: GoogleFonts.cairo(fontSize: 13, color: AppColors.textTertiary, fontWeight: FontWeight.w600)),
      ]),
    ),
  );
}
