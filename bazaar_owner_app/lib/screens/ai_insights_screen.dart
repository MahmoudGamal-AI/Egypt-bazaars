import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:fl_chart/fl_chart.dart';
import '../core/constants/colors.dart';
import '../providers/auth_provider.dart';
import '../providers/ai_insights_provider.dart';
import 'ai_competitor_screen.dart';
import 'ai_campaign_screen.dart';
import 'ai_review_analysis_screen.dart';
import 'ai_inventory_alerts_screen.dart';
import 'package:flutter_staggered_animations/flutter_staggered_animations.dart';
import '../widgets/premium_ui/premium_ui.dart';

/// 📊 شاشة التحليلات الذكية — AI-Powered Insights Dashboard
/// ✅ UPGRADED: Uses AIInsightsProvider for smart caching
class AIInsightsScreen extends StatefulWidget {
  const AIInsightsScreen({super.key});

  @override
  State<AIInsightsScreen> createState() => _AIInsightsScreenState();
}

class _AIInsightsScreenState extends State<AIInsightsScreen>
    with TickerProviderStateMixin {
  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  bool _initialLoadDone = false;

  final List<Map<String, String>> _periods = [
    {'key': 'day', 'label': 'اليوم'},
    {'key': 'week', 'label': 'أسبوع'},
    {'key': 'month', 'label': 'شهر'},
    {'key': 'quarter', 'label': '3 أشهر'},
  ];

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Auto-load ONCE on first visit — then uses cache
    if (!_initialLoadDone) {
      _initialLoadDone = true;
      _autoLoad();
    }
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  /// Auto-load: uses cache if available, fetches only if needed
  Future<void> _autoLoad() async {
    final auth = context.read<BazaarAuthProvider>();
    final bazaarId = auth.user?.bazaarId;
    if (bazaarId == null) return;

    final provider = context.read<AIInsightsProvider>();
    await provider.loadAnalytics(bazaarId);
    if (provider.hasData && mounted) {
      _fadeController.forward(from: 0);
    }
  }

  /// Manual refresh: force re-fetch from API
  Future<void> _manualRefresh() async {
    final auth = context.read<BazaarAuthProvider>();
    final bazaarId = auth.user?.bazaarId;
    if (bazaarId == null) return;

    final provider = context.read<AIInsightsProvider>();
    await provider.refresh(bazaarId);
    if (provider.hasData && mounted) {
      _fadeController.forward(from: 0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<AIInsightsProvider>(
      builder: (context, provider, _) {
        // Local aliases for cleaner code in helper methods
        _analytics = provider.analytics;
        _selectedPeriod = provider.currentPeriod;

        return Scaffold(
          backgroundColor: AppColors.background,
          body: CustomScrollView(
            physics: const BouncingScrollPhysics(),
            slivers: [
              // === Premium App Bar ===
              SliverAppBar(
                expandedHeight: 120,
                pinned: true,
                backgroundColor: AppColors.pharaohBlue,
                flexibleSpace: FlexibleSpaceBar(
                  title: const Text(
                    'التحليلات الذكية',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                  background: Container(
                    decoration: const BoxDecoration(
                      gradient: AppColors.darkGradient,
                    ),
                    child: Stack(
                      children: [
                        Positioned(
                          right: -30,
                          top: -30,
                          child: Container(
                            width: 150,
                            height: 150,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.05),
                            ),
                          ),
                        ),
                        Positioned(
                          left: -20,
                          bottom: -20,
                          child: Container(
                            width: 100,
                            height: 100,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.white.withOpacity(0.08),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                actions: [
                  if (provider.isLoading)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Iconsax.refresh, color: Colors.white),
                      onPressed: _manualRefresh,
                      tooltip: 'تحديث البيانات',
                    ),
                ],
              ),

              // === Content ===
              if (provider.isLoading && !provider.hasData)
                const SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: AppColors.primary),
                        SizedBox(height: 16),
                        Text(
                          '🤖 جاري تحليل البيانات...',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.all(16),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate([
                      // Last Refresh Indicator
                      if (provider.lastRefresh != null)
                        _buildLastRefreshBadge(provider),
                      const SizedBox(height: 12),

                      // Period Selector
                      _buildPeriodSelector(),
                      const SizedBox(height: 20),

                      // Stat Cards
                      FadeTransition(
                        opacity: _fadeAnimation,
                        child: _buildStatCards(),
                      ),
                      const SizedBox(height: 20),

                      // AI Summary
                      if (_analytics?['ai_summary'] != null)
                        _buildAISummaryCard(),
                      const SizedBox(height: 20),

                      // Revenue Chart
                      _buildRevenueChart(),
                      const SizedBox(height: 20),

                      // AI Insights
                      _buildAIInsightsSection(),
                      const SizedBox(height: 20),

                      // Top Products
                      _buildTopProductsChart(),
                      const SizedBox(height: 20),

                      // Peak Hours Heatmap
                      _buildPeakHoursChart(),
                      const SizedBox(height: 20),

                      // Predictions
                      _buildPredictionsCard(),
                      const SizedBox(height: 24),

                      // === AI Tools Hub ===
                      _buildAIToolsHub(),
                      const SizedBox(height: 40),
                    ]),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  // === Provider-backed local aliases (set in build) ===
  Map<String, dynamic>? _analytics;
  String _selectedPeriod = 'week';

  // ============================================================
  // Last Refresh Badge — shows when data was last fetched
  // ============================================================
  Widget _buildLastRefreshBadge(AIInsightsProvider provider) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: provider.isLoading
            ? AppColors.info.withOpacity(0.08)
            : AppColors.success.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: provider.isLoading
              ? AppColors.info.withOpacity(0.2)
              : AppColors.success.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Icon(
            provider.isLoading ? Iconsax.refresh : Iconsax.tick_circle,
            size: 16,
            color: provider.isLoading ? AppColors.info : AppColors.success,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              provider.isLoading
                  ? 'جاري تحديث البيانات...'
                  : '✅ آخر تحديث: ${provider.lastRefreshLabel}',
              style: TextStyle(
                fontSize: 12,
                color: provider.isLoading ? AppColors.info : AppColors.success,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (!provider.isLoading)
            GestureDetector(
              onTap: _manualRefresh,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'تحديث',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ============================================================
  // Period Selector
  // ============================================================
  Widget _buildPeriodSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: AppColors.softShadow,
      ),
      child: Row(
        children: _periods.map((p) {
          final isSelected = _selectedPeriod == p['key'];
          return Expanded(
            child: GestureDetector(
              onTap: () {
                final bazaarId = context.read<BazaarAuthProvider>().user?.bazaarId;
                if (bazaarId != null) {
                  context.read<AIInsightsProvider>().changePeriod(p['key']!, bazaarId);
                }
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.secondary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  p['label']!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    color:
                        isSelected ? Colors.white : AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ============================================================
  // Stat Cards (animated)
  // ============================================================
  Widget _buildStatCards() {
    final revenue = _analytics?['revenue'] ?? {};
    final orders = _analytics?['orders'] ?? {};
    final rating = _analytics?['rating'] ?? {};
    final products = _analytics?['products'] ?? {};

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 12,
      crossAxisSpacing: 12,
      childAspectRatio: 1.15,
      children: [
        _StatCard(
          icon: Iconsax.money_recive,
          title: 'الإيرادات',
          value: '${_formatNumber(revenue['total'] ?? 0)} ج.م',
          change: (revenue['change_pct'] ?? 0).toDouble(),
          gradient: AppColors.successGradient,
        ),
        _StatCard(
          icon: Iconsax.shopping_bag,
          title: 'الطلبات',
          value: '${orders['total'] ?? 0}',
          change: (orders['change_pct'] ?? 0).toDouble(),
          gradient: AppColors.infoGradient,
        ),
        _StatCard(
          icon: Iconsax.star,
          title: 'التقييم',
          value: '${rating['average'] ?? 0} ⭐',
          change: 0,
          gradient: AppColors.warningGradient,
        ),
        _StatCard(
          icon: Iconsax.box,
          title: 'المنتجات النشطة',
          value: '${products['active'] ?? 0}',
          change: 0,
          gradient: AppColors.primaryGradient,
        ),
      ],
    );
  }

  // ============================================================
  // AI Summary Card
  // ============================================================
  Widget _buildAISummaryCard() {
    return PremiumGlassCard(
      padding: const EdgeInsets.all(16),
      color: AppColors.pharaohBlue,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.tealGradient.colors.first.withOpacity(0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Iconsax.cpu, color: AppColors.tealGradient.colors.first, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              _analytics?['ai_summary'] ?? '',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Revenue Line Chart
  // ============================================================
  Widget _buildRevenueChart() {
    final revenueData =
        (_analytics?['charts_data']?['revenue_line'] as List?) ?? [];
    if (revenueData.isEmpty) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Iconsax.chart_1, color: AppColors.secondary, size: 22),
              SizedBox(width: 8),
              Text(
                'الإيرادات',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          SizedBox(
            height: 200,
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: _getChartInterval(revenueData),
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: Colors.grey.withOpacity(0.15),
                    strokeWidth: 1,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 50,
                      getTitlesWidget: (value, meta) {
                        return Text(
                          _formatCompactNumber(value),
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 10,
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: (revenueData.length / 5).ceilToDouble(),
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= revenueData.length) {
                          return const SizedBox();
                        }
                        final date = revenueData[idx]['date'] ?? '';
                        return Text(
                          date.length >= 10 ? date.substring(5, 10) : '',
                          style: TextStyle(
                            color: Colors.grey[500],
                            fontSize: 9,
                          ),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                lineBarsData: [
                  LineChartBarData(
                    spots: List.generate(revenueData.length, (i) {
                      return FlSpot(
                        i.toDouble(),
                        (revenueData[i]['revenue'] ?? 0).toDouble(),
                      );
                    }),
                    isCurved: true,
                    curveSmoothness: 0.3,
                    color: AppColors.secondary,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: FlDotData(
                      show: true,
                      getDotPainter: (spot, percent, bar, index) {
                        return FlDotCirclePainter(
                          radius: 4,
                          color: Colors.white,
                          strokeWidth: 2,
                          strokeColor: AppColors.secondary,
                        );
                      },
                    ),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        colors: [
                          AppColors.secondary.withOpacity(0.3),
                          AppColors.secondary.withOpacity(0.0),
                        ],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                    ),
                  ),
                ],
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          '${spot.y.toStringAsFixed(0)} ج.م',
                          const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
              ),
              duration: const Duration(milliseconds: 800),
              curve: Curves.easeOutCubic,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // AI Insights Cards
  // ============================================================
  Widget _buildAIInsightsSection() {
    final insights = (_analytics?['ai_insights'] as List?) ?? [];
    if (insights.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.tealGradient.colors.first.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Iconsax.cpu, color: AppColors.tealGradient.colors.first, size: 20),
            ),
            const SizedBox(width: 10),
            const Text(
              'نصائح الذكاء الاصطناعي',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        ...insights.map((insight) {
          final type = insight['type'] ?? 'tip';
          Color borderColor;
          Color bgColor;
          switch (type) {
            case 'success':
              borderColor = AppColors.success;
              bgColor = AppColors.successLight;
              break;
            case 'warning':
              borderColor = AppColors.warning;
              bgColor = AppColors.warningLight;
              break;
            case 'danger':
              borderColor = AppColors.error;
              bgColor = AppColors.errorLight;
              break;
            default:
              borderColor = AppColors.info;
              bgColor = AppColors.infoLight;
          }

          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: BorderRadius.circular(14),
              border: Border(
                right: BorderSide(color: borderColor, width: 4),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  insight['icon'] ?? '💡',
                  style: const TextStyle(fontSize: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (insight['title'] != null &&
                          insight['title'].toString().isNotEmpty)
                        Text(
                          insight['title'],
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                            color: borderColor,
                          ),
                        ),
                      Text(
                        insight['text'] ?? '',
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ============================================================
  // Top Products Bar Chart
  // ============================================================
  Widget _buildTopProductsChart() {
    final topProducts =
        (_analytics?['charts_data']?['products_bar'] as List?) ?? [];
    if (topProducts.isEmpty) return const SizedBox();

    final maxRevenue = topProducts
        .map((p) => (p['revenue'] ?? 0).toDouble())
        .reduce((a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Iconsax.crown, color: AppColors.primary, size: 22),
              SizedBox(width: 8),
              Text(
                'أفضل المنتجات',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...List.generate(topProducts.length, (i) {
            final product = topProducts[i];
            final revenue = (product['revenue'] ?? 0).toDouble();
            final ratio = maxRevenue > 0 ? revenue / maxRevenue : 0.0;

            final colors = [
              AppColors.secondary,
              AppColors.primary,
              AppColors.info,
              AppColors.warning,
              AppColors.error,
            ];

            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          product['name'] ?? 'منتج',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Text(
                        '${_formatNumber(revenue)} ج.م',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colors[i % colors.length],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: ratio),
                    duration: Duration(milliseconds: 800 + (i * 200)),
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) {
                      return Container(
                        height: 8,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(4),
                          color: Colors.grey[100],
                        ),
                        child: FractionallySizedBox(
                          alignment: Alignment.centerRight,
                          widthFactor: value,
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: LinearGradient(
                                colors: [
                                  colors[i % colors.length].withOpacity(0.6),
                                  colors[i % colors.length],
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ============================================================
  // Peak Hours Chart
  // ============================================================
  Widget _buildPeakHoursChart() {
    List peakHours =
        (_analytics?['charts_data']?['hourly_bar'] as List?) ?? [];
        
    // Check if we have any actual data
    final totalOrders = peakHours.isEmpty 
        ? 0 
        : peakHours.map((h) => (h['orders'] ?? 0) as num).reduce((a, b) => a + b);

    // If backend data is missing or completely empty (0 orders), show real empty data (zeros)
    if (peakHours.isEmpty || totalOrders == 0) {
      peakHours = List.generate(24, (i) => {
        'hour': i,
        'label': '${i.toString().padLeft(2, '0')}:00',
        'orders': 0
      });
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Iconsax.clock, color: AppColors.info, size: 22),
              SizedBox(width: 8),
              Text(
                'أوقات الذروة',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary),
              ),
            ],
          ),
          const SizedBox(height: 20),
          SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: () {
                  final maxOrders = peakHours
                      .map((h) => (h['orders'] ?? 0).toDouble())
                      .reduce((a, b) => a > b ? a : b);
                  final calculated = (maxOrders * 1.2).ceilToDouble();
                  return calculated < 5.0 ? 5.0 : calculated;
                }(),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final hour = peakHours[groupIndex]['hour'] ?? 0;
                      return BarTooltipItem(
                        '${rod.toY.toInt()} طلب\n$hour:00',
                        const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    },
                  ),
                ),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= peakHours.length) {
                          return const SizedBox();
                        }
                        // Prevent overlap by showing every 4th hour
                        if (idx % 4 != 0 && idx != peakHours.length - 1) {
                          return const SizedBox();
                        }
                        return Text(
                          '${peakHours[idx]['hour']}:00',
                          style: TextStyle(
                              color: Colors.grey[500], fontSize: 10),
                        );
                      },
                    ),
                  ),
                ),
                borderData: FlBorderData(show: false),
                gridData: const FlGridData(show: false),
                barGroups: List.generate(peakHours.length, (i) {
                  final orders = (peakHours[i]['orders'] ?? 0).toDouble();
                  return BarChartGroupData(
                    x: i,
                    barRods: [
                      BarChartRodData(
                        toY: orders,
                        width: 14,
                        borderRadius: BorderRadius.circular(6),
                        gradient: LinearGradient(
                          colors: [
                            AppColors.info.withOpacity(0.6),
                            AppColors.info,
                          ],
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                        ),
                      ),
                    ],
                  );
                }),
              ),
              swapAnimationDuration: const Duration(milliseconds: 800),
              swapAnimationCurve: Curves.easeOutCubic,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Predictions Card
  // ============================================================
  Widget _buildPredictionsCard() {
    final predictions = _analytics?['predictions'] ?? {};
    final nextWeek = (predictions['next_week_revenue'] ?? 0).toDouble();
    final confidence = (predictions['confidence'] ?? 0).toDouble();

    if (nextWeek == 0) return const SizedBox();

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.darkGradient,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF302b63).withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child:
                    const Icon(Iconsax.magic_star, color: Colors.amber, size: 22),
              ),
              const SizedBox(width: 10),
              const Text(
                'التوقعات',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'الأسبوع القادم',
            style:
                TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 13),
          ),
          const SizedBox(height: 4),
          Text(
            '~${_formatNumber(nextWeek)} ج.م',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text(
                'ثقة التنبؤ',
                style: TextStyle(
                    color: Colors.white.withOpacity(0.6), fontSize: 12),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: confidence),
                  duration: const Duration(milliseconds: 1200),
                  curve: Curves.easeOutCubic,
                  builder: (context, value, _) {
                    return Stack(
                      children: [
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            color: Colors.white.withOpacity(0.1),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: value,
                          child: Container(
                            height: 8,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(4),
                              gradient: const LinearGradient(
                                colors: [Colors.amber, Colors.orange],
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(confidence * 100).toInt()}%',
                style: const TextStyle(
                  color: Colors.amber,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Helpers
  // ============================================================
  String _formatNumber(double num) {
    if (num >= 1000000) return '${(num / 1000000).toStringAsFixed(1)}M';
    if (num >= 1000) return '${(num / 1000).toStringAsFixed(1)}K';
    return num.toStringAsFixed(0);
  }

  String _formatCompactNumber(double num) {
    if (num >= 1000) return '${(num / 1000).toStringAsFixed(0)}K';
    return num.toStringAsFixed(0);
  }

  double _getChartInterval(List data) {
    if (data.isEmpty) return 1;
    final maxVal = data
        .map((d) => (d['revenue'] ?? 0).toDouble())
        .reduce((a, b) => a > b ? a : b);
    if (maxVal <= 0) return 1;
    return (maxVal / 4).ceilToDouble();
  }

  // ============================================================
  // AI Tools Hub — Quick Access to AI Features
  // ============================================================

  Widget _buildAIToolsHub() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Row(children: [
          Icon(Iconsax.cpu, size: 22, color: AppColors.primary),
          SizedBox(width: 8),
          Text('🧰 أدوات الذكاء الاصطناعي',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 4),
        Text('أدوات متقدمة لتحسين أداء بازارك',
            style: TextStyle(fontSize: 13, color: Colors.grey[500])),
        const SizedBox(height: 14),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          childAspectRatio: 1.2,
          children: AnimationConfiguration.toStaggeredList(
            duration: const Duration(milliseconds: 375),
            childAnimationBuilder: (widget) => SlideAnimation(
              verticalOffset: 50.0,
              child: FadeInAnimation(
                child: widget,
              ),
            ),
            children: [
              _aiToolCard(
                title: 'التحليل التنافسي',
                subtitle: 'موقعك في السوق',
                icon: Iconsax.chart_215,
                gradient: AppColors.tealGradient,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AICompetitorScreen())),
              ),
              _aiToolCard(
                title: 'حملات ذكية',
                subtitle: 'تسويق بالذكاء الاصطناعي',
                icon: Iconsax.magic_star,
                gradient: AppColors.primaryGradient,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AICampaignScreen())),
              ),
              _aiToolCard(
                title: 'تحليل المراجعات',
                subtitle: 'آراء العملاء بذكاء',
                icon: Iconsax.star_1,
                gradient: AppColors.infoGradient,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AIReviewAnalysisScreen())),
              ),
              _aiToolCard(
                title: 'تنبيهات المخزون',
                subtitle: 'إدارة مخزون ذكية',
                icon: Iconsax.box_1,
                gradient: AppColors.warningGradient,
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const AIInventoryAlertsScreen())),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _aiToolCard({
    required String title,
    required String subtitle,
    required IconData icon,
    required LinearGradient gradient,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
          border: Border.all(color: Colors.grey.withOpacity(0.1)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                gradient: gradient,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(
                    color: AppColors.textPrimary, fontSize: 14, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(subtitle, style: const TextStyle(
                    color: AppColors.textSecondary, fontSize: 11, fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Stat Card Widget
// ============================================================
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final double change;
  final LinearGradient gradient;

  const _StatCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.change,
    required this.gradient,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: AppColors.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  gradient: gradient,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: Colors.white, size: 20),
              ),
              if (change != 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: change > 0 ? AppColors.successLight : AppColors.errorLight,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${change > 0 ? '↑' : '↓'} ${change.abs().toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: change > 0 ? AppColors.success : AppColors.error,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                style: const TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
