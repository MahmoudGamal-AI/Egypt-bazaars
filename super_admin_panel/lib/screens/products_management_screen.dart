import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../widgets/premium_data_card.dart';
import '../core/constants/colors.dart';
import '../providers/admin_data_provider.dart';
import '../widgets/shimmer_loading.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/product_model.dart';
import '../models/bazaar_model.dart';
import 'add_edit_product_screen.dart';

/// شاشة إدارة المنتجات للـ Super Admin
class ProductsManagementScreen extends StatefulWidget {
  const ProductsManagementScreen({super.key});

  @override
  State<ProductsManagementScreen> createState() =>
      _ProductsManagementScreenState();
}

class _ProductsManagementScreenState extends State<ProductsManagementScreen> {
  final TextEditingController _searchController = TextEditingController();

  String _selectedCategory = 'الكل';
  String _selectedBazaar = 'الكل';
  String _selectedStatus = 'الكل';
  bool _isGridView = true;
  bool _isFetchingMore = false;
  Set<String> _selectedProductIds = {};

  final List<String> _categories = [
    'الكل',
    'تماثيل',
    'مجوهرات',
    'ملابس تقليدية',
    'أواني',
    'لوحات',
    'هدايا تذكارية',
    'بردي',
    'أخرى',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<AdminDataProvider>();
      if (provider.totalProducts == 0) provider.loadAllData();
      provider.loadProducts(
        refresh: true,
        category: _selectedCategory,
        bazaarId: _selectedBazaar,
        status: _selectedStatus,
      );
    });
  }

  List<Product> _getFilteredProducts(AdminDataProvider provider) {
    final query = _searchController.text.toLowerCase();

    return provider.allProducts.where((product) {
      // Local Search filter only (since category/bazaar are server-side)
      final matchesSearch = query.isEmpty ||
          product.nameAr.toLowerCase().contains(query) ||
          product.nameEn.toLowerCase().contains(query) ||
          product.bazaarName.toLowerCase().contains(query);

      return matchesSearch;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        children: [
          _buildUnifiedHeader(),
          Expanded(child: _buildProductsList()),
        ],
      ),
    );
  }

  Widget _buildUnifiedHeader() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(bottom: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'إدارة المنتجات',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildStatsRow(),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(Iconsax.menu_1, color: !_isGridView ? AppColors.primary : AppColors.textHint),
                      onPressed: () => setState(() => _isGridView = false),
                    ),
                    IconButton(
                      icon: Icon(Iconsax.grid_2, color: _isGridView ? AppColors.primary : AppColors.textHint),
                      onPressed: () => setState(() => _isGridView = true),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Consumer<AdminDataProvider>(
                builder: (context, provider, _) => IconButton(
                  onPressed: provider.isLoading
                      ? null
                      : () => provider.loadProducts(
                            refresh: true,
                            category: _selectedCategory,
                            bazaarId: _selectedBazaar,
                            status: _selectedStatus,
                          ),
                  icon: const Icon(Iconsax.refresh),
                  style: IconButton.styleFrom(
                    backgroundColor: AppColors.background,
                    foregroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: _navigateToAddProduct,
                icon: const Icon(Iconsax.add, size: 20),
                label: const Text('إضافة منتج'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (_selectedProductIds.isNotEmpty)
            _buildBulkActionsBar()
          else
            _buildFiltersRow(),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    return Consumer<AdminDataProvider>(
      builder: (context, provider, _) {
        final products = _getFilteredProducts(provider);
        final activeCount = products.where((p) => p.isActive).length;
        return Row(
          children: [
            _buildMiniStat(Iconsax.box, '${products.length} منتج', AppColors.textSecondary),
            const SizedBox(width: 16),
            _buildMiniStat(Iconsax.verify, '$activeCount نشط', AppColors.success),
            const SizedBox(width: 16),
            _buildMiniStat(Iconsax.close_circle, '${products.length - activeCount} معطل', AppColors.error),
          ],
        );
      },
    );
  }

  Widget _buildMiniStat(IconData icon, String text, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(text, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }

  Widget _buildFiltersRow() {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: _searchController,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'بحث باسم المنتج أو البازار...',
              prefixIcon: const Icon(Iconsax.search_normal_1, color: AppColors.textHint, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear, color: AppColors.textHint, size: 20),
                      onPressed: () {
                        _searchController.clear();
                        setState(() {});
                      },
                    )
                  : null,
              filled: true,
              fillColor: AppColors.background,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: _buildCompactDropdown(
            value: _selectedCategory,
            hint: 'الفئة',
            items: _categories.map((c) => DropdownMenuItem(value: c, child: Text(c))).toList(),
            onChanged: (value) {
              setState(() => _selectedCategory = value!);
              context.read<AdminDataProvider>().loadProducts(
                    refresh: true,
                    category: _selectedCategory,
                    bazaarId: _selectedBazaar,
                    status: _selectedStatus,
                  );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: Consumer<AdminDataProvider>(
            builder: (context, provider, _) {
              final bazaarItems = [
                const DropdownMenuItem(value: 'الكل', child: Text('كل البازارات')),
                ...provider.allBazaars.map((b) => DropdownMenuItem(
                      value: b.id,
                      child: Text(b.nameAr, maxLines: 1, overflow: TextOverflow.ellipsis),
                    )),
              ];
              String currentValue = _selectedBazaar;
              if (currentValue != 'الكل' && !provider.allBazaars.any((b) => b.id == currentValue)) {
                currentValue = 'الكل';
              }
              return _buildCompactDropdown(
                value: currentValue,
                hint: 'البازار',
                items: bazaarItems,
                onChanged: (value) {
                  setState(() => _selectedBazaar = value!);
                  context.read<AdminDataProvider>().loadProducts(
                        refresh: true,
                        category: _selectedCategory,
                        bazaarId: _selectedBazaar,
                        status: _selectedStatus,
                      );
                },
              );
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 1,
          child: _buildCompactDropdown(
            value: _selectedStatus,
            hint: 'الحالة',
            items: const ['الكل', 'نشط', 'معطل'].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (value) {
              setState(() => _selectedStatus = value!);
              context.read<AdminDataProvider>().loadProducts(
                    refresh: true,
                    category: _selectedCategory,
                    bazaarId: _selectedBazaar,
                    status: _selectedStatus,
                  );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCompactDropdown({
    required String value,
    required String hint,
    required List<DropdownMenuItem<String>> items,
    required void Function(String?) onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          hint: Text(hint),
          isExpanded: true,
          icon: const Icon(Iconsax.arrow_down_1, size: 16, color: AppColors.textHint),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildBulkActionsBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      height: 48,
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          const Icon(Iconsax.tick_square, color: AppColors.primary, size: 20),
          const SizedBox(width: 8),
          Text(
            'تم تحديد ${_selectedProductIds.length} منتج',
            style: const TextStyle(fontWeight: FontWeight.bold, color: AppColors.primary),
          ),
          const Spacer(),
          TextButton.icon(
            onPressed: () => _bulkToggleStatus(true),
            icon: const Icon(Iconsax.verify, color: AppColors.success, size: 16),
            label: const Text('تفعيل', style: TextStyle(color: AppColors.success)),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: () => _bulkToggleStatus(false),
            icon: const Icon(Iconsax.close_circle, color: AppColors.warning, size: 16),
            label: const Text('إيقاف', style: TextStyle(color: AppColors.warning)),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _bulkDelete,
            icon: const Icon(Iconsax.trash, color: AppColors.error, size: 16),
            label: const Text('حذف', style: TextStyle(color: AppColors.error)),
          ),
          const SizedBox(width: 8),
          Container(width: 1, height: 24, color: AppColors.divider),
          const SizedBox(width: 8),
          IconButton(
            onPressed: () => setState(() => _selectedProductIds.clear()),
            icon: const Icon(Icons.close, color: AppColors.textHint, size: 20),
            tooltip: 'إلغاء التحديد',
          ),
        ],
      ),
    );
  }

  Widget _buildProductsList() {
    return Consumer<AdminDataProvider>(
      builder: (context, provider, _) {
        if (provider.isLoading && provider.allProducts.isEmpty) {
          if (_isGridView) {
            return const ShimmerProductGrid();
          } else {
            return ListView.builder(
              padding: const EdgeInsets.all(24),
              itemCount: 8,
              itemBuilder: (context, index) => const ShimmerListItem(),
            );
          }
        }

        final products = _getFilteredProducts(provider);

        if (products.isEmpty) {
          return _buildEmptyState();
        }

        if (_isGridView) {
          return _buildProductsGrid(products);
        } else {
          return _buildProductsTable(products);
        }
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Iconsax.box_remove,
              size: 64,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'لا توجد منتجات',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _searchController.text.isNotEmpty
                ? 'لم يتم العثور على نتائج للبحث'
                : 'ابدأ بإضافة منتج جديد',
            style: const TextStyle(color: AppColors.textSecondary),
          ),
          const SizedBox(height: 24),
          if (_searchController.text.isEmpty)
            ElevatedButton.icon(
              onPressed: _navigateToAddProduct,
              icon: const Icon(Iconsax.add),
              label: const Text('إضافة منتج'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildProductsTable(List<Product> products) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          children: [
            // Table Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(16),
                ),
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 40,
                    child: Checkbox(
                      value: _selectedProductIds.length == products.length &&
                          products.isNotEmpty,
                      onChanged: (value) {
                        setState(() {
                          if (value == true) {
                            _selectedProductIds =
                                products.map((p) => p.id).toSet();
                          } else {
                            _selectedProductIds.clear();
                          }
                        });
                      },
                      activeColor: AppColors.primary,
                    ),
                  ),
                  const SizedBox(width: 60), // Image
                  const Expanded(
                    flex: 2,
                    child: Text(
                      'المنتج',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'البازار',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const Expanded(
                    child: Text(
                      'الفئة',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(
                    width: 100,
                    child: Text(
                      'السعر',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(
                    width: 80,
                    child: Text(
                      'المخزون',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(
                    width: 80,
                    child: Text(
                      'الحالة',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                  const SizedBox(width: 120), // Actions
                ],
              ),
            ),
            const Divider(height: 1),
            // Table Rows
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: products.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final product = products[index];
                return _buildProductRow(product);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductRow(Product product) {
    final isSelected = _selectedProductIds.contains(product.id);

    return InkWell(
      onTap: () => _navigateToEditProduct(product),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        color: isSelected ? AppColors.primary.withOpacity(0.05) : null,
        child: Row(
          children: [
            // Checkbox
            SizedBox(
              width: 40,
              child: Checkbox(
                value: isSelected,
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _selectedProductIds.add(product.id);
                    } else {
                      _selectedProductIds.remove(product.id);
                    }
                  });
                },
                activeColor: AppColors.primary,
              ),
            ),
            // Image
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: CachedNetworkImage(
                imageUrl: product.imageUrl,
                width: 50,
                height: 50,
                fit: BoxFit.cover,
                placeholder: (_, __) => Container(
                  color: AppColors.background,
                  child: const Icon(Iconsax.image, color: AppColors.textHint),
                ),
                errorWidget: (_, __, ___) => Container(
                  color: AppColors.background,
                  child: const Icon(Iconsax.image, color: AppColors.textHint),
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Name
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.nameAr,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (product.nameEn.isNotEmpty)
                    Text(
                      product.nameEn,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                ],
              ),
            ),
            // Bazaar
            Expanded(
              child: Text(
                product.bazaarName,
                style: const TextStyle(color: AppColors.textSecondary),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            // Category
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  product.category,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            // Price
            SizedBox(
              width: 100,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${product.price.toStringAsFixed(0)} ج.م',
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.primary,
                    ),
                  ),
                  if (product.hasDiscount)
                    Text(
                      '${product.oldPrice!.toStringAsFixed(0)} ج.م',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textHint,
                        decoration: TextDecoration.lineThrough,
                      ),
                    ),
                ],
              ),
            ),
            // Stock
            SizedBox(
              width: 80,
              child: Text(
                product.isInStock ? '${product.stockQuantity}' : 'نفذ',
                style: TextStyle(
                  color:
                      product.isInStock ? AppColors.success : AppColors.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            // Status
            SizedBox(
              width: 80,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: product.isActive
                      ? AppColors.success.withOpacity(0.1)
                      : AppColors.error.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  product.isActive ? 'نشط' : 'معطل',
                  style: TextStyle(
                    fontSize: 12,
                    color:
                        product.isActive ? AppColors.success : AppColors.error,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            // Actions
            SizedBox(
              width: 120,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    icon: const Icon(Iconsax.edit_2, size: 18),
                    onPressed: () => _navigateToEditProduct(product),
                    color: AppColors.primary,
                    tooltip: 'تعديل',
                  ),
                  IconButton(
                    icon: Icon(
                      product.isActive ? Iconsax.eye_slash : Iconsax.eye,
                      size: 18,
                    ),
                    onPressed: () => _toggleProductStatus(product),
                    color: AppColors.warning,
                    tooltip: product.isActive ? 'إيقاف' : 'تفعيل',
                  ),
                  IconButton(
                    icon: const Icon(Iconsax.trash, size: 18),
                    onPressed: () => _deleteProduct(product),
                    color: AppColors.error,
                    tooltip: 'حذف',
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductsGrid(List<Product> products) {
    return Consumer<AdminDataProvider>(
      builder: (context, provider, _) {
        return NotificationListener<ScrollNotification>(
          onNotification: (ScrollNotification scrollInfo) {
            if (!provider.isLoading && !_isFetchingMore &&
                scrollInfo.metrics.pixels >=
                    scrollInfo.metrics.maxScrollExtent - 200) {
              _isFetchingMore = true;
              provider.loadProducts(
                limit: 50,
                category: _selectedCategory,
                bazaarId: _selectedBazaar,
                status: _selectedStatus,
              ).then((_) {
                if (mounted) setState(() => _isFetchingMore = false);
              });
            }
            return true;
          },
          child: GridView.builder(
            padding: const EdgeInsets.all(24),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 4,
              childAspectRatio: 0.75,
              crossAxisSpacing: 16,
              mainAxisSpacing: 16,
            ),
            itemCount: products.length + (provider.hasMoreProducts ? 1 : 0),
            itemBuilder: (context, index) {

              if (index == products.length) {
                return const Center(child: CircularProgressIndicator(color: AppColors.primary));
              }
              final product = products[index];
              return AnimatedScale(
                scale: 1.0,
                duration: const Duration(milliseconds: 300),
                child: _buildProductCard(product),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildProductCard(Product product) {
    final isSelected = _selectedProductIds.contains(product.id);

    return PremiumDataCard(
      padding: EdgeInsets.zero,
      onTap: () => _navigateToEditProduct(product),
      isSelected: isSelected,
      child: Column(

          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(16),
                    ),
                    child: CachedNetworkImage(
                      imageUrl: product.imageUrl,
                      width: double.infinity,
                      fit: BoxFit.cover,
                      placeholder: (_, __) => Container(
                        color: AppColors.background,
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                      errorWidget: (_, __, ___) => Container(
                        color: AppColors.background,
                        child: const Icon(
                          Iconsax.image,
                          size: 40,
                          color: AppColors.textHint,
                        ),
                      ),
                    ),
                  ),
                  // Checkbox
                  Positioned(
                    top: 8,
                    right: 8,
                    child: GestureDetector(
                      onTap: () {
                        setState(() {
                          if (isSelected) {
                            _selectedProductIds.remove(product.id);
                          } else {
                            _selectedProductIds.add(product.id);
                          }
                        });
                      },
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.primary : AppColors.white,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: isSelected
                                ? AppColors.primary
                                : AppColors.divider,
                          ),
                        ),
                        child: isSelected
                            ? const Icon(
                                Icons.check,
                                size: 16,
                                color: AppColors.white,
                              )
                            : null,
                      ),
                    ),
                  ),
                  // Status Badge
                  if (!product.isActive)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.black.withOpacity(0.5),
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                        ),
                        child: const Center(
                          child: Text(
                            'معطل',
                            style: TextStyle(
                              color: AppColors.white,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Info
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    product.nameAr,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.bazaarName,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Text(
                        '${product.price.toStringAsFixed(0)} ج.م',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.primary,
                          ),
                        ),
                        const Spacer(),
                        // Quick Actions
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_vert, size: 18),
                          onSelected: (value) {
                            if (value == 'edit') {
                              _navigateToEditProduct(product);
                            } else if (value == 'toggle') {
                              _toggleProductStatus(product);
                            } else if (value == 'delete') {
                              _deleteProduct(product);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Row(
                                children: [
                                  Icon(Iconsax.edit_2, size: 18),
                                  SizedBox(width: 8),
                                  Text('تعديل'),
                                ],
                              ),
                            ),
                            PopupMenuItem(
                              value: 'toggle',
                              child: Row(
                                children: [
                                  Icon(
                                    product.isActive
                                        ? Iconsax.eye_slash
                                        : Iconsax.eye,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Text(product.isActive ? 'إيقاف' : 'تفعيل'),
                                ],
                              ),
                            ),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Row(
                                children: [
                                  Icon(Iconsax.trash,
                                      size: 18, color: Colors.red),
                                  SizedBox(width: 8),
                                  Text('حذف',
                                      style: TextStyle(color: Colors.red)),
                                ],
                              ),
                            ),
                          ],
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

  // ============ Actions ============

  void _navigateToAddProduct() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => const AddEditProductScreen(),
      ),
    );
    if (result == true && mounted) {
      context.read<AdminDataProvider>().loadAllProducts();
    }
  }

  void _navigateToEditProduct(Product product) async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => AddEditProductScreen(product: product),
      ),
    );
    if (result == true && mounted) {
      context.read<AdminDataProvider>().loadAllProducts();
    }
  }

  Future<void> _toggleProductStatus(Product product) async {
    final provider = context.read<AdminDataProvider>();
    final success = await provider.toggleProductStatus(
      product.id,
      !product.isActive,
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? (product.isActive ? 'تم إيقاف المنتج' : 'تم تفعيل المنتج')
                : 'حدث خطأ',
          ),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  Future<void> _deleteProduct(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المنتج'),
        content: Text(
            'هل أنت متأكد من حذف "${product.nameAr}"؟\nلا يمكن التراجع عن هذا الإجراء.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: const Text('حذف'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final provider = context.read<AdminDataProvider>();
      final success = await provider.deleteProduct(product.id);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'تم حذف المنتج' : 'حدث خطأ'),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
    }
  }

  Future<void> _bulkToggleStatus(bool isActive) async {
    final provider = context.read<AdminDataProvider>();
    final success = await provider.bulkUpdateProducts(
      _selectedProductIds.toList(),
      {'isActive': isActive},
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success ? 'تم تحديث ${_selectedProductIds.length} منتج' : 'حدث خطأ',
          ),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
      if (success) {
        setState(() => _selectedProductIds.clear());
      }
    }
  }

  Future<void> _bulkDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المنتجات'),
        content: Text(
          'هل أنت متأكد من حذف ${_selectedProductIds.length} منتج؟\nلا يمكن التراجع عن هذا الإجراء.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: const Text('حذف الكل'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final provider = context.read<AdminDataProvider>();
      final success =
          await provider.bulkDeleteProducts(_selectedProductIds.toList());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(success ? 'تم حذف المنتجات' : 'حدث خطأ'),
          backgroundColor: success ? AppColors.success : AppColors.error,
        ),
      );
      if (success) {
        setState(() => _selectedProductIds.clear());
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }
}
