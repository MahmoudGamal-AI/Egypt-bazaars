import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:iconsax/iconsax.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import '../core/constants/colors.dart';
import '../providers/admin_data_provider.dart';
import '../services/product_service.dart';
import '../models/bazaar_model.dart';

class AddEditBazaarScreen extends StatefulWidget {
  final Bazaar? bazaar;

  const AddEditBazaarScreen({super.key, this.bazaar});

  @override
  State<AddEditBazaarScreen> createState() => _AddEditBazaarScreenState();
}

class _AddEditBazaarScreenState extends State<AddEditBazaarScreen> {
  final _formKey = GlobalKey<FormState>();

  bool get isEditing => widget.bazaar != null;

  // Controllers
  final _nameArController = TextEditingController();
  final _nameEnController = TextEditingController();
  final _descriptionArController = TextEditingController();
  final _descriptionEnController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _imageUrlController = TextEditingController();
  final _governorateController = TextEditingController();
  final _ownerUserIdController = TextEditingController();
  final _workingHoursController = TextEditingController();
  final _emailController = TextEditingController();

  bool _isOpen = true;
  bool _isVerified = false;
  bool _isSaving = false;
  bool _isUploading = false;
  Uint8List? _selectedImageBytes;
  String? _selectedFileName;
  final ProductService _productService = ProductService();

  @override
  void initState() {
    super.initState();
    if (isEditing) {
      _populateForm();
    } else {
      _workingHoursController.text = '9:00 - 21:00';
    }
  }

  void _populateForm() {
    final b = widget.bazaar!;
    _nameArController.text = b.nameAr;
    _nameEnController.text = b.nameEn;
    _descriptionArController.text = b.descriptionAr;
    _descriptionEnController.text = b.descriptionEn;
    _addressController.text = b.address;
    _phoneController.text = b.phone;
    _imageUrlController.text = b.imageUrl;
    _governorateController.text = b.governorate;
    _ownerUserIdController.text = b.ownerUserId;
    _workingHoursController.text = b.workingHours;
    _emailController.text = b.email ?? '';
    _isOpen = b.isOpen;
    _isVerified = b.isVerified;
  }

  @override
  void dispose() {
    _nameArController.dispose();
    _nameEnController.dispose();
    _descriptionArController.dispose();
    _descriptionEnController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _imageUrlController.dispose();
    _governorateController.dispose();
    _ownerUserIdController.dispose();
    _workingHoursController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _saveBazaar() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final provider = context.read<AdminDataProvider>();
      final newBazaar = Bazaar(
        id: isEditing ? widget.bazaar!.id : '',
        nameAr: _nameArController.text.trim(),
        nameEn: _nameEnController.text.trim(),
        descriptionAr: _descriptionArController.text.trim(),
        descriptionEn: _descriptionEnController.text.trim(),
        address: _addressController.text.trim(),
        phone: _phoneController.text.trim(),
        imageUrl: _imageUrlController.text.trim(),
        governorate: _governorateController.text.trim(),
        ownerUserId: _ownerUserIdController.text.trim(),
        workingHours: _workingHoursController.text.trim(),
        email: _emailController.text.trim().isEmpty ? null : _emailController.text.trim(),
        isOpen: _isOpen,
        isVerified: _isVerified,
        createdAt: isEditing ? widget.bazaar!.createdAt : DateTime.now(),
        latitude: isEditing ? widget.bazaar!.latitude : 0.0,
        longitude: isEditing ? widget.bazaar!.longitude : 0.0,
        rating: isEditing ? widget.bazaar!.rating : 0.0,
        reviewCount: isEditing ? widget.bazaar!.reviewCount : 0,
        galleryImages: isEditing ? widget.bazaar!.galleryImages : const [],
        productIds: isEditing ? widget.bazaar!.productIds : const [],
      );

      bool success;
      if (isEditing) {
        success = await provider.updateBazaar(newBazaar.id, newBazaar.toJson());
      } else {
        success = await provider.createBazaar(newBazaar);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(success ? 'تم الحفظ بنجاح' : 'حدث خطأ أثناء الحفظ'),
            backgroundColor: success ? AppColors.success : AppColors.error,
          ),
        );
        if (success) {
          Navigator.pop(context);
        }
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _pickImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );

      if (result != null && result.files.single.bytes != null) {
        setState(() {
          _selectedImageBytes = result.files.single.bytes;
          _selectedFileName = result.files.single.name;
        });

        await _uploadToCloudinary();
      }
    } catch (e) {
      debugPrint('Error picking image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في اختيار الصورة: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    }
  }

  Future<void> _uploadToCloudinary() async {
    if (_selectedImageBytes == null) return;

    setState(() => _isUploading = true);

    try {
      final imageUrl = await _productService.uploadImageToCloudinary(
        _selectedImageBytes!,
        _selectedFileName ?? 'bazaar_image.jpg',
      );

      if (imageUrl != null) {
        setState(() {
          _imageUrlController.text = imageUrl;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('تم رفع الصورة بنجاح'),
              backgroundColor: AppColors.success,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('فشل رفع الصورة - تأكد من إعدادات Cloudinary'),
              backgroundColor: AppColors.error,
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Error uploading to Cloudinary: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('خطأ في رفع الصورة: $e'),
            backgroundColor: AppColors.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          isEditing ? 'تعديل البازار' : 'إضافة بازار جديد',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.white,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionTitle('المعلومات الأساسية'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _nameArController,
                      label: 'الاسم (عربي)',
                      icon: Iconsax.shop,
                      validator: (v) => v!.isEmpty ? 'مطلوب' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      controller: _nameEnController,
                      label: 'الاسم (إنجليزي)',
                      icon: Iconsax.shop,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _descriptionArController,
                      label: 'الوصف (عربي)',
                      icon: Iconsax.document_text,
                      maxLines: 3,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      controller: _descriptionEnController,
                      label: 'الوصف (إنجليزي)',
                      icon: Iconsax.document_text,
                      maxLines: 3,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _buildSectionTitle('معلومات التواصل والموقع'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _phoneController,
                      label: 'رقم الهاتف',
                      icon: Iconsax.call,
                      validator: (v) => v!.isEmpty ? 'مطلوب' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      controller: _emailController,
                      label: 'البريد الإلكتروني',
                      icon: Iconsax.sms,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _addressController,
                      label: 'العنوان التفصيلي',
                      icon: Iconsax.location,
                      validator: (v) => v!.isEmpty ? 'مطلوب' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      controller: _governorateController,
                      label: 'المحافظة',
                      icon: Iconsax.map,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              _buildSectionTitle('معلومات الإدارة'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _ownerUserIdController,
                      label: 'معرف صاحب البازار (User ID)',
                      icon: Iconsax.user,
                      validator: (v) => v!.isEmpty ? 'مطلوب' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _buildTextField(
                      controller: _workingHoursController,
                      label: 'ساعات العمل',
                      icon: Iconsax.clock,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildImageUploader(),
              const SizedBox(height: 32),
              _buildSectionTitle('الحالة'),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SwitchListTile(
                      title: const Text('البازار مفتوح الآن'),
                      value: _isOpen,
                      onChanged: (v) => setState(() => _isOpen = v),
                      activeColor: AppColors.success,
                    ),
                  ),
                  Expanded(
                    child: SwitchListTile(
                      title: const Text('حساب موثق'),
                      value: _isVerified,
                      onChanged: (v) => setState(() => _isVerified = v),
                      activeColor: AppColors.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveBazaar,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: _isSaving
                      ? const CircularProgressIndicator(color: Colors.white)
                      : Text(
                          isEditing ? 'حفظ التعديلات' : 'إضافة البازار',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: maxLines == 1 ? Icon(icon, color: AppColors.primary) : null,
        filled: true,
        fillColor: AppColors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppColors.divider),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.primary, width: 2),
        ),
      ),
    );
  }

  Widget _buildImageUploader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'صورة البازار الرئيسية',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.textPrimary,
          ),
        ),
        const SizedBox(height: 12),
        InkWell(
          onTap: _isUploading ? null : _pickImage,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 200,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: AppColors.divider,
                width: 2,
                style: BorderStyle.solid,
              ),
            ),
            child: _isUploading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(color: AppColors.primary),
                        SizedBox(height: 16),
                        Text(
                          'جاري رفع الصورة...',
                          style: TextStyle(color: AppColors.textSecondary),
                        ),
                      ],
                    ),
                  )
                : _imageUrlController.text.isNotEmpty
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: CachedNetworkImage(
                              imageUrl: _imageUrlController.text,
                              fit: BoxFit.cover,
                              placeholder: (context, url) => const Center(
                                child: CircularProgressIndicator(),
                              ),
                              errorWidget: (context, url, error) => const Icon(
                                Iconsax.image,
                                size: 48,
                                color: AppColors.textHint,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: CircleAvatar(
                              backgroundColor: AppColors.black.withOpacity(0.5),
                              child: IconButton(
                                icon: const Icon(Iconsax.edit, color: AppColors.white, size: 18),
                                onPressed: _pickImage,
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Iconsax.document_upload,
                            size: 48,
                            color: AppColors.primary.withOpacity(0.5),
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'اضغط لاختيار صورة',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          const Text(
                            'PNG, JPG, JPEG (الحد الأقصى 2 ميجابايت)',
                            style: TextStyle(
                              color: AppColors.textHint,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
          ),
        ),
      ],
    );
  }
}
