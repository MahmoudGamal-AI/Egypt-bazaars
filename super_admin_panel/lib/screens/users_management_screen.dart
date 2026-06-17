import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:intl/intl.dart';
import '../core/constants/colors.dart';
import '../providers/admin_data_provider.dart';
import '../widgets/shimmer_loading.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../models/user_model.dart';
import '../widgets/premium_data_card.dart';

/// شاشة إدارة المستخدمين
class UsersManagementScreen extends StatefulWidget {
  const UsersManagementScreen({super.key});

  @override
  State<UsersManagementScreen> createState() => _UsersManagementScreenState();
}

class _UsersManagementScreenState extends State<UsersManagementScreen> {
  String _searchQuery = '';
  String _filterRole = 'all';
  bool _isFetchingMore = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AdminDataProvider>().loadUsers(refresh: true, role: _filterRole);
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
                  '👥 إدارة المستخدمين',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'عرض وإدارة جميع المستخدمين المسجلين في المنصة',
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
                          hintText: 'بحث عن مستخدم...',
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
                          value: _filterRole,
                          items: const [
                            DropdownMenuItem(
                              value: 'all',
                              child: Text('جميع الأدوار'),
                            ),
                            DropdownMenuItem(
                              value: 'customer',
                              child: Text('عملاء'),
                            ),
                            DropdownMenuItem(
                              value: 'bazaarOwner',
                              child: Text('أصحاب بازارات'),
                            ),
                            DropdownMenuItem(
                              value: 'superAdmin',
                              child: Text('مدراء'),
                            ),
                          ],
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _filterRole = value);
                              context.read<AdminDataProvider>().loadUsers(refresh: true, role: _filterRole);
                            }
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Users list
          Expanded(
            child: Consumer<AdminDataProvider>(
              builder: (context, provider, _) {
                if (provider.isLoading && provider.allUsers.isEmpty) {
                  return ListView.builder(
                    padding: const EdgeInsets.all(24),
                    itemCount: 8,
                    itemBuilder: (context, index) => const ShimmerListItem(),
                  );
                }

                final filteredUsers = provider.allUsers.where((user) {
                  final matchesSearch = _searchQuery.isEmpty ||
                      user.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
                      user.email.toLowerCase().contains(_searchQuery.toLowerCase());
                  return matchesSearch;
                }).toList();

                if (filteredUsers.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Iconsax.people,
                          size: 64,
                          color: AppColors.textHint,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'لا توجد مستخدمين',
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
                      provider.loadUsers(role: _filterRole).then((_) {
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
                      crossAxisSpacing: 24,
                      mainAxisSpacing: 24,
                    ),
                    itemCount: filteredUsers.length + (provider.hasMoreUsers ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == filteredUsers.length) {
                        return const ShimmerListItem();
                      }
                      final user = filteredUsers[index];
                      return AnimatedScale(
                        scale: 1.0,
                        duration: const Duration(milliseconds: 300),
                        child: _buildUserCard(user, provider)
                            .animate()
                            .fadeIn(
                              duration: const Duration(milliseconds: 400),
                              delay: Duration(milliseconds: 50 * (index % 12)),
                            )
                            .slideX(begin: 0.1, end: 0),
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

  Widget _buildUserCard(UserModel user, AdminDataProvider provider) {
    final dateFormat = DateFormat('dd/MM/yyyy', 'ar');
    final roleInfo = _getRoleInfo(user.role);

    return PremiumDataCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Avatar
          Center(
            child: CircleAvatar(
            radius: 28,
            backgroundColor: roleInfo['color'].withOpacity(0.1),
            child: user.photoUrl != null && user.photoUrl!.isNotEmpty
                ? ClipOval(
                    child: Image.network(
                      user.photoUrl!,
                      width: 56,
                      height: 56,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Text(
                        user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w600,
                          color: roleInfo['color'],
                        ),
                      ),
                    ),
                  )
                : Text(
                    user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
            ), // closes Center
          ), // closes Avatar's Container / or Center itself? Wait, Center is the child of the outer column.
          const SizedBox(height: 16),

          // User info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                      user.name,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: roleInfo['color'].withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    roleInfo['label'],
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: roleInfo['color'],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Icon(Iconsax.sms, size: 14, color: AppColors.textHint),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        user.email,
                        style: const TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Iconsax.calendar, size: 14, color: AppColors.textHint),
                    const SizedBox(width: 6),
                    Text(
                      'انضم في ${dateFormat.format(user.createdAt)}',
                      style: const TextStyle(
                        color: AppColors.textHint,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              PopupMenuButton<UserRole>(
                icon: const Icon(Iconsax.edit, color: AppColors.primary, size: 20),
                tooltip: 'تغيير الدور',
                itemBuilder: (context) => [
              const PopupMenuItem(
                value: UserRole.customer,
                child: Row(
                  children: [
                    Icon(Iconsax.user, size: 18),
                    SizedBox(width: 8),
                    Text('عميل'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: UserRole.bazaarOwner,
                child: Row(
                  children: [
                    Icon(Iconsax.shop, size: 18),
                    SizedBox(width: 8),
                    Text('صاحب بازار'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: UserRole.superAdmin,
                child: Row(
                  children: [
                    Icon(Iconsax.shield, size: 18),
                    SizedBox(width: 8),
                    Text('مدير النظام'),
                  ],
                ),
              ),
            ],
            onSelected: (role) async {
              if (role == user.role) return;

              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('تغيير دور المستخدم'),
                  content: Text(
                    'هل تريد تغيير دور "${user.name}" إلى "${_getRoleInfo(role)['label']}"؟',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('إلغاء'),
                    ),
                    ElevatedButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      child: const Text('تأكيد'),
                    ),
                  ],
                ),
              );

              if (confirmed == true) {
                final success = await provider.updateUserRole(user.uid, role);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        success ? 'تم تحديث الدور بنجاح' : 'حدث خطأ',
                      ),
                      backgroundColor: success
                          ? AppColors.success
                          : AppColors.error,
                    ),
                  );
                }
              }
            },
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Iconsax.trash, color: AppColors.error, size: 20),
            tooltip: 'حذف المستخدم',
            onPressed: () {
              // TODO: Implement delete user
            },
          ),
        ],
      ),
    ],
  ),
);
  }

  Map<String, dynamic> _getRoleInfo(UserRole role) {
    switch (role) {
      case UserRole.customer:
        return {'label': 'عميل', 'color': AppColors.info};
      case UserRole.bazaarOwner:
        return {'label': 'صاحب بازار', 'color': AppColors.secondary};
      case UserRole.superAdmin:
        return {'label': 'مدير النظام', 'color': AppColors.primary};
    }
  }
}
