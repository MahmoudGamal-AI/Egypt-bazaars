import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;

/// Service for managing images with Cloudinary
class MediaService {
  final ImagePicker _picker = ImagePicker();

  // Cloudinary Configuration
  static const String cloudinaryCloudName = 'dlkpme30u';
  static const String cloudinaryUploadPreset = 'tourism';

  /// Storage folder structure
  static const String _bazaarImagesFolder = 'bazaars';
  static const String _productImagesFolder = 'products';
  static const String _userAvatarsFolder = 'avatars';
  static const String _galleryFolder = 'gallery';

  /// Pick image from gallery
  Future<XFile?> pickImageFromGallery({int quality = 70}) async {
    return await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: quality,
    );
  }

  /// Pick image from camera
  Future<XFile?> pickImageFromCamera({int quality = 70}) async {
    return await _picker.pickImage(
      source: ImageSource.camera,
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: quality,
    );
  }

  /// Pick multiple images from gallery
  Future<List<XFile>> pickMultipleImages({int quality = 70}) async {
    return await _picker.pickMultiImage(
      maxWidth: 1920,
      maxHeight: 1920,
      imageQuality: quality,
    );
  }

  /// Upload bazaar image
  Future<String> uploadBazaarImage({
    required String bazaarId,
    required XFile imageFile,
    bool isMain = false,
  }) async {
    final folderPath = '$_bazaarImagesFolder/$bazaarId';
    return await _uploadFile(imageFile, folderPath);
  }

  /// Upload product image
  Future<String> uploadProductImage({
    required String bazaarId,
    required String productId,
    required XFile imageFile,
    bool isMain = false,
  }) async {
    final folderPath = '$_productImagesFolder/$bazaarId/$productId';
    return await _uploadFile(imageFile, folderPath);
  }

  /// Upload multiple product gallery images
  Future<List<String>> uploadProductGallery({
    required String bazaarId,
    required String productId,
    required List<XFile> images,
  }) async {
    final urls = <String>[];
    final folderPath = '$_productImagesFolder/$bazaarId/$productId/$_galleryFolder';

    for (var i = 0; i < images.length; i++) {
      final url = await _uploadFile(images[i], folderPath);
      urls.add(url);
    }

    return urls;
  }

  /// Upload user avatar
  Future<String> uploadUserAvatar({
    required String userId,
    required XFile imageFile,
  }) async {
    final folderPath = '$_userAvatarsFolder/$userId';
    return await _uploadFile(imageFile, folderPath);
  }

  /// Generic file upload to Cloudinary
  Future<String> _uploadFile(XFile imageFile, String folderPath,
      {ValueChanged<double>? onProgress}) async {
    try {
      final bytes = await imageFile.readAsBytes();
      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudinaryCloudName/image/upload',
      );

      final fileName = path.basename(imageFile.path);

      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = cloudinaryUploadPreset
        ..fields['folder'] = folderPath
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ));

      if (onProgress != null) {
        onProgress(0.1);
      }

      final response = await request.send();

      if (response.statusCode == 200) {
        if (onProgress != null) {
          onProgress(1.0);
        }
        final responseData = await response.stream.bytesToString();
        final jsonData = json.decode(responseData);
        return jsonData['secure_url'] as String;
      } else {
        throw Exception('Upload failed with status: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Error uploading file to Cloudinary: $e');
      rethrow;
    }
  }

  /// Upload with progress callback
  Future<String> uploadWithProgress({
    required String folder,
    required String subfolder,
    required XFile imageFile,
    required ValueChanged<double> onProgress,
  }) async {
    final folderPath = '$folder/$subfolder';
    return await _uploadFile(imageFile, folderPath, onProgress: onProgress);
  }

  /// Delete image by URL (Bypassed for Cloudinary frontend)
  Future<void> deleteImageByUrl(String imageUrl) async {
    debugPrint('Note: Image deletion bypassed for Cloudinary secure storage.');
  }

  /// Delete multiple images (Bypassed for Cloudinary frontend)
  Future<void> deleteMultipleImages(List<String> imageUrls) async {
    debugPrint('Note: Multiple image deletion bypassed for Cloudinary secure storage.');
  }

  /// Delete all images in a folder (Bypassed for Cloudinary frontend)
  Future<void> deleteFolder(String folderPath) async {
    debugPrint('Note: Folder deletion bypassed for Cloudinary secure storage.');
  }

  /// Delete all product images (Bypassed for Cloudinary frontend)
  Future<void> deleteProductImages(String bazaarId, String productId) async {
    debugPrint('Note: Product images deletion bypassed for Cloudinary secure storage.');
  }

  /// Delete all bazaar images (Bypassed for Cloudinary frontend)
  Future<void> deleteBazaarImages(String bazaarId) async {
    debugPrint('Note: Bazaar images deletion bypassed for Cloudinary secure storage.');
  }

  /// Get all images in a folder (Bypassed for Cloudinary frontend)
  Future<List<String>> getImagesInFolder(String folderPath) async {
    debugPrint('Note: Folder listing bypassed for Cloudinary secure storage.');
    return [];
  }

  /// Get product gallery images (Bypassed for Cloudinary frontend)
  Future<List<String>> getProductGallery(
      String bazaarId, String productId) async {
    return [];
  }

  /// Get bazaar gallery images (Bypassed for Cloudinary frontend)
  Future<List<String>> getBazaarGallery(String bazaarId) async {
    return [];
  }

  /// Get storage space usage (approximate) (Bypassed for Cloudinary frontend)
  Future<int> getStorageUsage(String bazaarId) async {
    return 0;
  }

  /// Format bytes to human readable
  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}
