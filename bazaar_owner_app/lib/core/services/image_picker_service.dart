import 'dart:typed_data';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class ImagePickerService {
  final ImagePicker _picker = ImagePicker();

  // Cloudinary Configuration
  static const String cloudinaryCloudName = 'dlkpme30u';
  static const String cloudinaryUploadPreset = 'tourism';

  /// Pick a single image
  Future<Uint8List?> pickImage({ImageSource source = ImageSource.gallery}) async {
    try {
      final XFile? image = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      if (image != null) {
        return await image.readAsBytes();
      }
      return null;
    } catch (e) {
      debugPrint('Error picking image: $e');
      return null;
    }
  }

  /// Pick multiple images
  Future<List<Uint8List>> pickMultiImage() async {
    try {
      final List<XFile> images = await _picker.pickMultiImage(
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 85,
      );
      List<Uint8List> bytesList = [];
      for (var img in images) {
        bytesList.add(await img.readAsBytes());
      }
      return bytesList;
    } catch (e) {
      debugPrint('Error picking multiple images: $e');
      return [];
    }
  }

  /// Upload image to Cloudinary and return URL
  Future<String?> uploadImage(Uint8List bytes, String path) async {
    try {
      debugPrint('📤 Uploading image to Cloudinary...');

      final uri = Uri.parse(
        'https://api.cloudinary.com/v1_1/$cloudinaryCloudName/image/upload',
      );

      final fileName = 'img_${DateTime.now().millisecondsSinceEpoch}.jpg';

      final request = http.MultipartRequest('POST', uri)
        ..fields['upload_preset'] = cloudinaryUploadPreset
        ..fields['folder'] = path // Try to organize by folder if preset allows
        ..files.add(http.MultipartFile.fromBytes(
          'file',
          bytes,
          filename: fileName,
        ));

      final response = await request.send();

      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final jsonData = json.decode(responseData);
        final imageUrl = jsonData['secure_url'] as String;

        debugPrint('✅ Image uploaded: $imageUrl');
        return imageUrl;
      } else {
        debugPrint('❌ Upload failed with status: ${response.statusCode}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error uploading image to Cloudinary: $e');
      return null;
    }
  }

  /// Upload multiple images
  Future<List<String>> uploadImages(List<Uint8List> files, String folderPath) async {
    final List<String> urls = [];
    for (final file in files) {
      final url = await uploadImage(file, folderPath);
      if (url != null) {
        urls.add(url);
      }
    }
    return urls;
  }
}
