import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../core/constants/colors.dart';
import '../providers/admin_data_provider.dart';
import '../widgets/shimmer_loading.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/bazaar_model.dart';
import '../widgets/premium_data_card.dart';
import 'add_edit_bazaar_screen.dart';

/// شاشة قائمة البازارات
class BazaarsListScreen extends StatefulWidget {
  const BazaarsListScreen({super.key});

  @override
  State<BazaarsListScreen> createState() => _BazaarsListScreenState();
}

class _BazaarsListScreenState extends State<BazaarsListScreen> {
  String _searchQuery = '';
  String _filterStatus = 'all';
  bool _isFetchingMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminDataProvider>().loadBazaars(refresh: true, status: _filterStatus);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.all(24),
            color: AppColors.white,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🏪 إدارة البازارات',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'عرض وإدارة جميع البازارات المسجلة في المنصة',
                  style: TextStyle(
                    fontSize: 14,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 20),

                // Search and filters
                Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: TextField(
                        onChanged: (value) =>
                            setState(() => _searchQuery = value),
                        decoration: InputDecoration(
                          hintText: 'بحث عن بازار...',
                          prefixIcon: const Icon(Iconsax.search_normal),
                          filled: true,
                          fillColor: AppColors.background,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide.none,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppColors.background,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _filterStatus,
                          items: const [
                            DropdownMenuItem(value: 'all', child: Text('الكل')),
                            DropdownMenuItem(
                              value: 'active',
                              child: Text('نشط'),
                            ),
                            DropdownMenuItem(
                              value: 'inactive',
                              child: Text('معطل'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _filterStatus = value);
                              context.read<AdminDataProvider>().loadBazaars(refresh: true, status: _filterStatus);
                            }
                          },
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    ElevatedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const AddEditBazaarScreen(),
                          ),
                        );
                      },
                      icon: const Icon(Iconsax.add, size: 18),
                      label: const Text('إضافة بازار'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Bazaars list
          Expanded(
            child: Consumer<AdminDataProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading && provider.allBazaars.isEmpty) {
                  return const ShimmerProductGrid();
                }

                final filteredBazaars = provider.allBazaars.where((bazaar) {
                  final matchesSearch = _searchQuery.isEmpty || 
                      bazaar.nameAr.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                      bazaar.nameEn.toLowerCase().contains(_searchQuery.toLowerCase());
                  return matchesSearch;
                }).toList();

                if (filteredBazaars.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Iconsax.shop, size: 64, color: AppColors.textHint),
                        const SizedBox(height: 16),
                        const Text(
                          'لا توجد بازارات',
                          style: TextStyle(
                            fontSize: 18,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                return NotificationListener<ScrollNotification>(
                  onNotification: (ScrollNotification scrollInfo) {
                    if (!provider.isLoading && !_isFetchingMore &&
                        scrollInfo.metrics.pixels >=
                            scrollInfo.metrics.maxScrollExtent - 200) {
                      _isFetchingMore = true;
                      provider.loadBazaars(status: _filterStatus).then((_) {
                        if (mounted) setState(() => _isFetchingMore = false);
                      });
                    }
                    return true;
                  },
                  child: GridView.builder(
                    padding: const EdgeInsets.all(24),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 3,
                      childAspectRatio: 0.85,
                      crossAxisSpacing: 16,
                      mainAxisSpacing: 16,
                    ),
                    itemCount: filteredBazaars.length + (provider.hasMoreBazaars ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == filteredBazaars.length) {
                        return const Center(child: CircularProgressIndicator(color: AppColors.primary));
                      }
                      final bazaar = filteredBazaars[index];
                      return AnimatedScale(
                        scale: 1.0,
                        duration: const Duration(milliseconds: 300),
                        child: _buildBazaarCard(bazaar, provider)
                            .animate()
                            .fadeIn(
                              duration: const Duration(milliseconds: 400),
                              delay: Duration(milliseconds: 50 * (index % 12)),
                            )
                            .slideY(begin: 0.1, end: 0),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBazaarCard(Bazaar bazaar, AdminDataProvider provider) {
    return PremiumDataCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Bazaar image
          Center(
            child: Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              clipBehavior: Clip.antiAlias,
              child: bazaar.imageUrl.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: bazaar.imageUrl,
                      fit: BoxFit.cover,
                      placeholder: (context, url) => const Center(
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      errorWidget: (context, url, error) => const Icon(
                        Iconsax.shop,
                        size: 40,
                        color: AppColors.primary,
                      ),
                    )
                  : const Icon(Iconsax.shop, size: 40, color: AppColors.primary),
            ),
          ),
          const SizedBox(height: 20),

          // Bazaar info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        bazaar.nameAr,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: bazaar.isVerified
                            ? AppColors.success.withOpacity(0.1)
                            : AppColors.error.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            bazaar.isVerified
                                ? Iconsax.tick_circle
                                : Iconsax.close_circle,
                            color: bazaar.isVerified
                                ? AppColors.success
                                : AppColors.error,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            bazaar.isVerified ? 'نشط' : 'معطل',
                            style: TextStyle(
                              color: bazaar.isVerified
                                  ? AppColors.success
                                  : AppColors.error,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(Iconsax.location, size: 16, color: AppColors.textHint),
                    const SizedBox(width: 6),
                    Text(
                      '${bazaar.governorate} - ${bazaar.address}',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Icon(Iconsax.call, size: 16, color: AppColors.textHint),
                    const SizedBox(width: 6),
                    Text(
                      bazaar.phone,
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Icon(Icons.star, size: 16, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Text(
                      '${bazaar.rating.toStringAsFixed(1)} (${bazaar.reviewsCount})',
                      style: const TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
                const Spacer(),

                // Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    OutlinedButton.icon(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AddEditBazaarScreen(bazaar: bazaar),
                          ),
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppColors.primary,
                        side: const BorderSide(color: AppColors.primary),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      icon: const Icon(Iconsax.eye, size: 16),
                      label: const Text('عرض', style: TextStyle(fontSize: 12)),
                    ),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final success = await provider.toggleBazaarVerification(
                          bazaar.id,
                          !bazaar.isVerified,
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                success
                                    ? (bazaar.isVerified
                                          ? 'تم إلغاء تفعيل البازار'
                                          : 'تم تفعيل البازار')
                                    : 'حدث خطأ',
                              ),
                              backgroundColor: success
                                  ? AppColors.success
                                  : AppColors.error,
                            ),
                          );
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: bazaar.isVerified
                            ? AppColors.error
                            : AppColors.success,
                        foregroundColor: AppColors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                      ),
                      icon: Icon(
                        bazaar.isVerified
                            ? Iconsax.close_circle
                            : Iconsax.tick_circle,
                        size: 16,
                      ),
                      label: Text(
                        bazaar.isVerified ? 'تعطيل' : 'تفعيل',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
