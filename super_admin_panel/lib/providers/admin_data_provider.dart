import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/user_model.dart';
import '../models/bazaar_model.dart';
import '../models/product_model.dart';
import '../models/category_model.dart';
import '../services/product_service.dart';
import '../services/notification_service.dart';

/// نموذج طلب بازار جديد
class BazaarApplication {
  final String id;
  final String userId;
  final String ownerName;
  final String ownerEmail;
  final String ownerPhone;
  final String bazaarName;
  final String description;
  final String address;
  final String governorate;
  final String status; // pending, approved, rejected
  final DateTime createdAt;
  final String? rejectionReason;

  const BazaarApplication({
    required this.id,
    required this.userId,
    required this.ownerName,
    required this.ownerEmail,
    required this.ownerPhone,
    required this.bazaarName,
    required this.description,
    required this.address,
    required this.governorate,
    required this.status,
    required this.createdAt,
    this.rejectionReason,
  });

  factory BazaarApplication.fromJson(Map<String, dynamic> json) {
    try {
      return BazaarApplication(
        id: json['id'] as String? ?? '',
        userId: json['userId'] as String? ?? '',
        ownerName: json['ownerName'] as String? ?? 'غير محدد',
        ownerEmail: json['ownerEmail'] as String? ?? '',
        ownerPhone: json['ownerPhone'] as String? ?? '',
        bazaarName: json['bazaarName'] as String? ?? 'بازار غير مسمى',
        description: json['description'] as String? ?? '',
        address: json['address'] as String? ?? '',
        governorate: json['governorate'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
        createdAt: json['createdAt'] != null
            ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
            : DateTime.now(),
        rejectionReason: json['rejectionReason'] as String?,
      );
    } catch (e) {
      debugPrint('❌ Error parsing BazaarApplication: $e');
      debugPrint('📄 JSON data: $json');
      rethrow;
    }
  }
}

/// Provider لإدارة البيانات في لوحة Super Admin
class AdminDataProvider extends ChangeNotifier {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final ProductService _productService = ProductService();

  List<BazaarApplication> _pendingApplications = [];
  List<Bazaar> _allBazaars = [];
  List<UserModel> _allUsers = [];
  List<Product> _allProducts = [];
  List<Category> _categories = [];
  bool _isLoading = false;
  String? _error;

  // Pagination states
  DocumentSnapshot? _lastProductDoc;
  bool _hasMoreProducts = true;
  DocumentSnapshot? _lastBazaarDoc;
  bool _hasMoreBazaars = true;
  DocumentSnapshot? _lastUserDoc;
  bool _hasMoreUsers = true;

  // إحصائيات
  int _totalUsers = 0;
  int _totalBazaars = 0;
  int _pendingApprovals = 0;
  int _totalOrders = 0;
  double _totalRevenue = 0;
  int _totalProducts = 0;
  int _activeProducts = 0;

  List<BazaarApplication> get pendingApplications => _pendingApplications;
  List<Bazaar> get allBazaars => _allBazaars;
  List<UserModel> get allUsers => _allUsers;
  List<Product> get allProducts => _allProducts;
  List<Category> get categories => _categories;
  bool get isLoading => _isLoading;
  String? get error => _error;
  int get totalUsers => _totalUsers;
  int get totalBazaars => _totalBazaars;
  int get pendingApprovals => _pendingApprovals;
  int get totalOrders => _totalOrders;
  double get totalRevenue => _totalRevenue;
  int get totalProducts => _totalProducts;
  int get activeProducts => _activeProducts;

  bool get hasMoreProducts => _hasMoreProducts;
  bool get hasMoreBazaars => _hasMoreBazaars;
  bool get hasMoreUsers => _hasMoreUsers;

  /// تحميل البيانات الأساسية والإحصائيات للوحة القيادة
  Future<void> loadAllData() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await Future.wait([
        _loadPendingApplications(),
        _loadStatistics(),
      ]);
    } catch (e) {
      debugPrint('❌ Error loading admin data: $e');
      _error = 'خطأ في تحميل البيانات: $e';
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadPendingApplications() async {
    try {
      final snapshot = await _firestore
          .collection('bazaarApplications')
          .where('status', isEqualTo: 'pending')
          .get();

      _pendingApplications = snapshot.docs
          .map((doc) => BazaarApplication.fromJson({...doc.data(), 'id': doc.id}))
          .toList();

      _pendingApplications.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _pendingApprovals = _pendingApplications.length;
    } catch (e) {
      _pendingApplications = [];
      _pendingApprovals = 0;
    }
  }

  Future<void> loadBazaars({
    bool refresh = false,
    int limit = 20,
    String searchQuery = '',
    String status = 'all',
  }) async {
    if (refresh) {
      _allBazaars = [];
      _lastBazaarDoc = null;
      _hasMoreBazaars = true;
      _isLoading = true;
      notifyListeners();
    }

    if (!_hasMoreBazaars) return;

    try {
      Query query = _firestore.collection('bazaars');

      if (status != 'all') {
        bool isVerified = status == 'active';
        query = query.where('isVerified', isEqualTo: isVerified);
      }

      if (status == 'all' && searchQuery.isEmpty) {
        query = query.orderBy(FieldPath.documentId);
      } else {
        query = query.orderBy(FieldPath.documentId);
      }
      
      query = query.limit(limit);

      if (_lastBazaarDoc != null) {
        query = query.startAfterDocument(_lastBazaarDoc!);
      }

      final snapshot = await query.get();

      if (snapshot.docs.length < limit) {
        _hasMoreBazaars = false;
      }

      if (snapshot.docs.isNotEmpty) {
        _lastBazaarDoc = snapshot.docs.last;
      }

      final newBazaars = snapshot.docs
          .map((doc) => Bazaar.fromJson({...doc.data() as Map<String, dynamic>, 'id': doc.id}))
          .toList();

      if (refresh) {
        _allBazaars = newBazaars;
      } else {
        _allBazaars.addAll(newBazaars);
      }
    } catch (e) {
      debugPrint('Error loading bazaars: $e');
    }

    if (refresh) {
      _isLoading = false;
    }
    notifyListeners();
  }

  Future<void> loadUsers({
    bool refresh = false,
    int limit = 20,
    String role = 'all',
    String searchQuery = '',
  }) async {
    if (refresh) {
      _allUsers = [];
      _lastUserDoc = null;
      _hasMoreUsers = true;
      _isLoading = true;
      notifyListeners();
    }

    if (!_hasMoreUsers) return;

    try {
      Query query = _firestore.collection('users');

      if (role != 'all') {
        query = query.where('role', isEqualTo: role);
      }

      if (role == 'all' && searchQuery.isEmpty) {
        query = query.orderBy('createdAt', descending: true);
      } else {
        query = query.orderBy(FieldPath.documentId);
      }

      query = query.limit(limit);

      if (_lastUserDoc != null) {
        query = query.startAfterDocument(_lastUserDoc!);
      }

      final snapshot = await query.get();

      if (snapshot.docs.length < limit) {
        _hasMoreUsers = false;
      }

      if (snapshot.docs.isNotEmpty) {
        _lastUserDoc = snapshot.docs.last;
      }

      final newUsers = snapshot.docs
          .map((doc) => UserModel.fromJson({...doc.data() as Map<String, dynamic>, 'uid': doc.id}))
          .toList();

      if (refresh) {
        _allUsers = newUsers;
      } else {
        _allUsers.addAll(newUsers);
      }
    } catch (e) {
      debugPrint('Error loading users: $e');
    }

    if (refresh) {
      _isLoading = false;
    }
    notifyListeners();
  }

  Future<void> _loadStatistics() async {
    try {
      // count orders
      final ordersSnapshot = await _firestore.collection('orders').count().get();
      _totalOrders = ordersSnapshot.count ?? 0;

      // count products
      final productsSnapshot = await _firestore.collection('products').count().get();
      _totalProducts = productsSnapshot.count ?? 0;

      // count active products (optional: query active ones if needed, or estimate)
      // Since counting active products is an extra query, we just use totalProducts for activeProducts
      // unless we specifically need it. Let's do a fast count for active.
      final activeProductsSnapshot = await _firestore.collection('products').where('isActive', isEqualTo: true).count().get();
      _activeProducts = activeProductsSnapshot.count ?? 0;

      // count bazaars
      final bazaarsSnapshot = await _firestore.collection('bazaars').count().get();
      _totalBazaars = bazaarsSnapshot.count ?? 0;

      // count users
      final usersSnapshot = await _firestore.collection('users').count().get();
      _totalUsers = usersSnapshot.count ?? 0;

      // calculate revenue limit to top recent 100 or keep it as is if it's small,
      // but it could be large. We will aggregate revenue via Cloud Functions normally,
      // but for now we fetch only recently delivered.
      final completedSubOrders = await _firestore
          .collection('subOrders')
          .where('status', isEqualTo: 'delivered')
          .limit(100) // Avoid memory leak, ideally revenue is pre-calculated
          .get();

      _totalRevenue = 0;
      for (final doc in completedSubOrders.docs) {
        _totalRevenue += (doc.data()['subtotal'] as num?)?.toDouble() ?? 0;
      }

    } catch (e) {
      debugPrint('❌ Error loading statistics: $e');
    }
  }

  /// الموافقة على طلب بازار
  Future<bool> approveApplication(BazaarApplication application) async {
    try {
      final bazaarDoc = _firestore.collection('bazaars').doc();
      await bazaarDoc.set({
        'id': bazaarDoc.id,
        'nameAr': application.bazaarName,
        'nameEn': application.bazaarName,
        'descriptionAr': application.description,
        'descriptionEn': application.description,
        'ownerUserId': application.userId,
        'address': application.address,
        'governorate': application.governorate,
        'phone': application.ownerPhone,
        'email': application.ownerEmail,
        'isOpen': true,
        'isVerified': true,
        'rating': 0.0,
        'reviewsCount': 0,
        'productIds': [],
        'createdAt': DateTime.now().toIso8601String(),
      });

      await _firestore.collection('users').doc(application.userId).update({
        'role': 'bazaarOwner',
        'bazaarId': bazaarDoc.id,
        'applicationStatus': 'approved',
      });

      await _firestore
          .collection('bazaarApplications')
          .doc(application.id)
          .update({'status': 'approved'});

      NotificationService().sendNotification(
        targetUserId: application.userId,
        title: 'تهانينا! تمت الموافقة على البازار',
        body: 'تمت الموافقة على طلبك لفتح ${application.bazaarName}.',
        data: {'type': 'bazaar_approval', 'bazaarId': bazaarDoc.id},
      );

      await loadAllData();
      return true;
    } catch (e) {
      debugPrint('Error approving application: $e');
      return false;
    }
  }

  /// رفض طلب بازار
  Future<bool> rejectApplication(
    BazaarApplication application,
    String reason,
  ) async {
    try {
      await _firestore.collection('users').doc(application.userId).update({
        'applicationStatus': 'rejected',
        'applicationRejectionReason': reason,
      });

      await _firestore
          .collection('bazaarApplications')
          .doc(application.id)
          .update({'status': 'rejected', 'rejectionReason': reason});

      NotificationService().sendNotification(
        targetUserId: application.userId,
        title: 'عذراً، تم رفض طلب البازار',
        body: 'تم رفض طلبك لفتح ${application.bazaarName}. السبب: $reason',
        data: {'type': 'bazaar_rejection'},
      );

      await loadAllData();
      return true;
    } catch (e) {
      debugPrint('Error rejecting application: $e');
      return false;
    }
  }

  /// إلغاء تفعيل / تفعيل بازار
  Future<bool> toggleBazaarVerification(
    String bazaarId,
    bool isVerified,
  ) async {
    try {
      await _firestore.collection('bazaars').doc(bazaarId).update({
        'isVerified': isVerified,
      });
      final index = _allBazaars.indexWhere((b) => b.id == bazaarId);
      if (index != -1) {
        _allBazaars[index] = _allBazaars[index].copyWith(isVerified: isVerified);
        notifyListeners();
      }
      return true;
    } catch (e) {
      debugPrint('Error toggling bazaar verification: $e');
      return false;
    }
  }

  /// اضافة بازار جديد
  Future<bool> createBazaar(Bazaar bazaar) async {
    try {
      final docRef = await _firestore.collection('bazaars').add(bazaar.toJson());
      await loadBazaars(refresh: true);
      return true;
    } catch (e) {
      debugPrint('Error creating bazaar: $e');
      return false;
    }
  }

  /// تعديل بازار موجود
  Future<bool> updateBazaar(String bazaarId, Map<String, dynamic> data) async {
    try {
      await _firestore.collection('bazaars').doc(bazaarId).update(data);
      await loadBazaars(refresh: true);
      return true;
    } catch (e) {
      debugPrint('Error updating bazaar: $e');
      return false;
    }
  }

  /// تغيير دور المستخدم
  Future<bool> updateUserRole(String userId, UserRole role) async {
    try {
      await _firestore.collection('users').doc(userId).update({
        'role': role.name,
      });
      final index = _allUsers.indexWhere((u) => u.uid == userId);
      if (index != -1) {
        _allUsers[index] = _allUsers[index].copyWith(role: role);
        notifyListeners();
      }
      return true;
    } catch (e) {
      debugPrint('Error updating user role: $e');
      return false;
    }
  }

  // ============ Products Management ============

  /// تحميل المنتجات مع دعم الفلترة على السيرفر (Server-Side) لتخفيف الرامات
  Future<void> loadProducts({
    bool refresh = false,
    int limit = 20,
    String category = 'الكل',
    String bazaarId = 'الكل',
    String status = 'الكل',
  }) async {
    if (refresh) {
      _allProducts = [];
      _lastProductDoc = null;
      _hasMoreProducts = true;
      _isLoading = true;
      notifyListeners();
    }

    if (!_hasMoreProducts) return;

    try {
      Query query = _firestore.collection('products');

      // Server-side filtering
      if (category != 'الكل') {
        query = query.where('category', isEqualTo: category);
      }
      if (bazaarId != 'الكل') {
        query = query.where('bazaarId', isEqualTo: bazaarId);
      }
      if (status != 'الكل') {
        bool isActive = status == 'نشط';
        query = query.where('isActive', isEqualTo: isActive);
      }

      // Use orderBy for proper pagination with startAfterDocument
      // Note: This requires composite indexes in Firestore if filters are used!
      if (category == 'الكل' && bazaarId == 'الكل' && status == 'الكل') {
        query = query.orderBy('createdAt', descending: true);
      } else {
        // Fallback to order by document ID if we have filters to avoid composite index errors initially
        // Though it's better to just fetch without orderBy if we can't ensure indexes exist.
        // But startAfterDocument REQUIRES an orderBy! Let's order by documentId.
        query = query.orderBy(FieldPath.documentId);
      }

      query = query.limit(limit);

      if (_lastProductDoc != null) {
        query = query.startAfterDocument(_lastProductDoc!);
      }

      final snapshot = await query.get();

      if (snapshot.docs.length < limit) {
        _hasMoreProducts = false;
      }

      if (snapshot.docs.isNotEmpty) {
        _lastProductDoc = snapshot.docs.last;
      }

      final newProducts = snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        return Product.fromJson(data);
      }).toList();

      if (refresh) {
        _allProducts = newProducts;
      } else {
        _allProducts.addAll(newProducts);
      }

    } catch (e) {
      debugPrint('❌ Error loading products: $e');
    }

    if (refresh) {
      _isLoading = false;
    }
    notifyListeners();
  }

  // Keep compatibility
  Future<void> loadAllProducts() async {
    await loadProducts(refresh: true, limit: 50);
  }

  Future<bool> createProduct(Product product) async {
    try {
      final productId = await _productService.createProduct(product);
      if (productId != null) {
        await loadProducts(refresh: true);
        return true;
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  Future<bool> updateProduct(String productId, Map<String, dynamic> data) async {
    try {
      final success = await _productService.updateProduct(productId, data);
      if (success) {
        await loadProducts(refresh: true);
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteProduct(String productId) async {
    try {
      final success = await _productService.deleteProduct(productId);
      if (success) {
        await loadProducts(refresh: true);
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  Future<bool> toggleProductStatus(String productId, bool isActive) async {
    try {
      final success = await _productService.toggleProductStatus(productId, isActive);
      if (success) {
        final index = _allProducts.indexWhere((p) => p.id == productId);
        if (index != -1) {
          _allProducts[index] = _allProducts[index].copyWith(isActive: isActive);
          notifyListeners();
        }
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  Future<bool> bulkUpdateProducts(List<String> productIds, Map<String, dynamic> data) async {
    try {
      final success = await _productService.bulkUpdateProducts(productIds, data);
      if (success) {
        await loadProducts(refresh: true);
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  Future<bool> bulkDeleteProducts(List<String> productIds) async {
    try {
      final success = await _productService.bulkDeleteProducts(productIds);
      if (success) {
        await loadProducts(refresh: true);
      }
      return success;
    } catch (e) {
      return false;
    }
  }

  Future<void> loadCategories() async {
    try {
      _categories = await _productService.getAllCategories();
      notifyListeners();
    } catch (e) {
      debugPrint('❌ Error loading categories: $e');
    }
  }
}
