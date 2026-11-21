import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:super_clipboard/super_clipboard.dart';

void main() => runApp(
  const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: GitHubFoodUploaderPage(),
  ),
);

class GitHubFoodUploaderPage extends StatefulWidget {
  const GitHubFoodUploaderPage({super.key});

  @override
  State<GitHubFoodUploaderPage> createState() => _GitHubFoodUploaderPageState();
}

class _GitHubFoodUploaderPageState extends State<GitHubFoodUploaderPage> {
  final String _owner = 'dangduycuong';
  final String _repo = 'vietnamese-food-api';
  final String _branch = 'main';

  final _tokenController = TextEditingController();

  final _nameController = TextEditingController();
  final _areaController = TextEditingController(text: 'Hà Nội');
  final _thumbNameController = TextEditingController();
  final _ingredientsController = TextEditingController();
  final _instructionsController = TextEditingController();

  String _selectedCategory = 'Món Nước';
  Uint8List? _selectedImageBytes;
  String? _selectedImageExt;
  bool _isUploading = false;
  String _statusLog =
      'Sẵn sàng. Bạn có thể chuột phải "Copy Image" trên web rồi bấm Dán ảnh (hoặc Cmd+V).';

  final List<String> _categories = [
    'Món Nước',
    'Món Khô',
    'Món Cuốn & Bánh',
    'Đồ Uống',
    'Món Chay',
  ];

  // 1. Đọc ảnh trực tiếp từ Clipboard (khi bạn chuột phải Copy Image trên trình duyệt)
  Future<void> _pasteImageFromClipboard() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) {
      _showMsg('Thiết bị không hỗ trợ đọc Clipboard.', isError: true);
      return;
    }

    final reader = await clipboard.read();

    // Ưu tiên kiểm tra định dạng PNG hoặc JPEG trong Clipboard
    if (reader.canProvide(Formats.png)) {
      reader.getFile(Formats.png, (file) async {
        final bytes = await file.readAll();
        _applyImageBytes(bytes, 'png');
      });
    } else if (reader.canProvide(Formats.jpeg)) {
      reader.getFile(Formats.jpeg, (file) async {
        final bytes = await file.readAll();
        _applyImageBytes(bytes, 'jpg');
      });
    } else if (reader.canProvide(Formats.webp)) {
      reader.getFile(Formats.webp, (file) async {
        final bytes = await file.readAll();
        _applyImageBytes(bytes, 'webp');
      });
    } else {
      _showMsg(
        'Không tìm thấy hình ảnh trong Clipboard! Hãy chuột phải chọn "Copy Image" (Sao chép hình ảnh).',
        isError: true,
      );
    }
  }

  void _applyImageBytes(Uint8List bytes, String ext) {
    setState(() {
      _selectedImageBytes = bytes;
      _selectedImageExt = ext;
      if (_nameController.text.isNotEmpty) {
        _thumbNameController.text = '${_slugify(_nameController.text)}.$ext';
      } else {
        _thumbNameController.text =
            'mon_moi_${DateTime.now().millisecondsSinceEpoch}.$ext';
      }
      _statusLog =
          '✅ Đã dán ảnh thành công (${(bytes.length / 1024).toStringAsFixed(1)} KB - định dạng .$ext)';
    });
  }

  // 2. Dự phòng: Chọn file ảnh từ máy tính nếu cần
  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );

    if (result != null && result.files.single.bytes != null) {
      final file = result.files.single;
      final ext = (file.extension ?? 'jpg').toLowerCase();
      _applyImageBytes(file.bytes!, ext);
    }
  }

  String _slugify(String text) {
    const vietnamese = 'aAeEoOuUiIdDyY';
    final regexList = [
      RegExp(r'[àáạảãâầấậẩẫăằắặẳẵ]'),
      RegExp(r'[ÀÁẠẢÃÂẦẤẬẨẪĂẰẮẶẲẴ]'),
      RegExp(r'[èéẹẻẽêềếệểễ]'),
      RegExp(r'[ÈÉẸẺẼÊỀẾỆỂỄ]'),
      RegExp(r'[òóọỏõôồốộổỗơờớợởỡ]'),
      RegExp(r'[ÒÓỌỎÕÔỒỐỘỔỖƠỜỚỢỞỠ]'),
      RegExp(r'[ùúụủũưừứựửữ]'),
      RegExp(r'[ÙÚỤỦŨƯỪỨỰỬỮ]'),
      RegExp(r'[ìíịỉĩ]'),
      RegExp(r'[ÌÍỊỈĨ]'),
      RegExp(r'[đ]'),
      RegExp(r'[Đ]'),
      RegExp(r'[ỳýỵỷỹ]'),
      RegExp(r'[ỲÝỴỶỸ]'),
    ];
    String result = text;
    for (int i = 0; i < regexList.length; i++) {
      result = result.replaceAll(regexList[i], vietnamese[i]);
    }
    return result
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .replaceAll(RegExp(r'\s+'), '_');
  }

  Future<void> _publishToGitHub() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      _showMsg('Vui lòng dán GitHub Token trước!', isError: true);
      return;
    }
    if (_nameController.text.trim().isEmpty || _selectedImageBytes == null) {
      _showMsg('Vui lòng nhập Tên món và dán/chọn Ảnh món ăn!', isError: true);
      return;
    }

    setState(() {
      _isUploading = true;
      _statusLog = '⏳ Đang tải ảnh lên GitHub...';
    });

    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github+json',
      'Content-Type': 'application/json',
    };

    try {
      final imageFileName = _thumbNameController.text.trim();

      // Upload ảnh
      // 1. Tham số đầu tiên CHỈ GHI 'api.github.com' (không có https://)
      final imageApiUrl = Uri.https(
        'api.github.com',
        '/repos/$_owner/$_repo/contents/images/$imageFileName',
      );

      String? existingImageSha;
      final checkImgRes = await http.get(imageApiUrl, headers: headers);
      if (checkImgRes.statusCode == 200) {
        existingImageSha = json.decode(checkImgRes.body)['sha'];
      }

      final uploadImgRes = await http.put(
        imageApiUrl,
        headers: headers,
        body: json.encode({
          'message': 'Upload image $imageFileName via Admin Tool',
          'content': base64Encode(_selectedImageBytes!),
          'branch': _branch,
          'sha': ?existingImageSha,
        }),
      );

      if (uploadImgRes.statusCode != 200 && uploadImgRes.statusCode != 201) {
        throw Exception('Lỗi upload ảnh: ${uploadImgRes.body}');
      }

      setState(() => _statusLog = '✅ Đã tải ảnh xong! Đang cập nhật JSON...');

      // Đọc file JSON hiện tại
      // 2. Tương tự cho jsonApiUrl
      final jsonApiUrl = Uri.https(
        'api.github.com',
        '/repos/$_owner/$_repo/contents/vietnamese_foods.json',
      );

      final getJsonRes = await http.get(jsonApiUrl, headers: headers);
      if (getJsonRes.statusCode != 200) {
        throw Exception(
          'Không đọc được vietnamese_foods.json: ${getJsonRes.body}',
        );
      }

      final jsonFileMeta = json.decode(getJsonRes.body);
      final String fileSha = jsonFileMeta['sha'];
      final String rawBase64 = jsonFileMeta['content'].toString().replaceAll(
        '\n',
        '',
      );
      final String currentJsonString = utf8.decode(base64Decode(rawBase64));

      final Map<String, dynamic> rootData = json.decode(currentJsonString);
      final List<dynamic> items = rootData['items'] ?? [];

      final nextIdNumber = items.length + 1;
      final newId = 'vn_${nextIdNumber.toString().padLeft(2, '0')}';

      final ingredientsList = _ingredientsController.text
          .split('\n')
          .map((line) => line.replaceFirst(RegExp(r'^[-•*+]\s*'), '').trim())
          .where((line) => line.isNotEmpty)
          .toList();

      final newItem = {
        'id': newId,
        'name': _nameController.text.trim(),
        'category': _selectedCategory,
        'area': _areaController.text.trim(),
        'thumb': imageFileName,
        'ingredients': ingredientsList,
        'instructions': _instructionsController.text.trim(),
      };

      items.add(newItem);
      rootData['items'] = items;

      const encoder = JsonEncoder.withIndent('  ');
      final updatedJsonString = encoder.convert(rootData);

      final updateJsonRes = await http.put(
        jsonApiUrl,
        headers: headers,
        body: json.encode({
          'message': 'Add dish: ${_nameController.text.trim()} ($newId)',
          'content': base64Encode(utf8.encode(updatedJsonString)),
          'sha': fileSha,
          'branch': _branch,
        }),
      );

      if (updateJsonRes.statusCode != 200) {
        throw Exception('Lỗi cập nhật JSON: ${updateJsonRes.body}');
      }

      setState(() {
        _statusLog =
            '🎉 THÀNH CÔNG! Đã đăng món "${_nameController.text.trim()}" ($newId) lên GitHub!';
        _nameController.clear();
        _thumbNameController.clear();
        _ingredientsController.clear();
        _instructionsController.clear();
        _selectedImageBytes = null;
      });
      _showMsg('Đã đăng món mới lên GitHub thành công!');
    } catch (e, stackTrace) {
      debugPrint('=== CHI TIẾT LỖI GITHUB ===\n$e\n$stackTrace');
      setState(() => _statusLog = '❌ LỖI:\n$e');
      _showMsg(
        'Có lỗi xảy ra, bấm biểu tượng Copy ở khung đen để chép lỗi.',
        isError: true,
      );
    } finally {
      setState(() => _isUploading = false);
    }
  }

  void _showMsg(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.red.shade700 : Colors.teal,
      ),
    );
  }

  @override
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('GitHub Food Publisher (Hỗ trợ Dán ảnh trực tiếp)'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: Row(
        children: [
          // CỘT TRÁI: FORM NHẬP LIỆU
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  TextField(
                    controller: _tokenController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      labelText: 'GitHub Personal Access Token (ghp_...)',
                      prefixIcon: Icon(Icons.vpn_key),
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _nameController,
                          decoration: const InputDecoration(
                            labelText: 'Tên món ăn (VD: Bún Đậu Mắm Tôm)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (val) {
                            final ext = _selectedImageExt ?? 'png';
                            _thumbNameController.text = '${_slugify(val)}.$ext';
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _selectedCategory,
                          decoration: const InputDecoration(
                            labelText: 'Danh mục',
                            border: OutlineInputBorder(),
                          ),
                          items: _categories
                              .map(
                                (c) =>
                                    DropdownMenuItem(value: c, child: Text(c)),
                              )
                              .toList(),
                          onChanged: (val) =>
                              setState(() => _selectedCategory = val!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _areaController,
                          decoration: const InputDecoration(
                            labelText: 'Vùng miền / Tỉnh thành',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _thumbNameController,
                          decoration: const InputDecoration(
                            labelText: 'Tên file ảnh sẽ lưu trên GitHub',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _ingredientsController,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Nguyên liệu (Copy từ web dán vào, mỗi dòng 1 nguyên liệu)',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _instructionsController,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText:
                          'Cách chế biến (Copy từ web dán nguyên đoạn vào)',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // CỘT PHẢI: KHUNG DÁN ẢNH & NÚT ĐĂNG
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey.shade100,
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Hình ảnh món ăn:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pasteImageFromClipboard,
                            icon: const Icon(Icons.paste, size: 18),
                            label: const Text('Dán ảnh'),
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: _pickImage,
                            tooltip: 'Hoặc chọn file từ máy',
                            icon: const Icon(
                              Icons.folder_open,
                              color: Colors.teal,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: InkWell(
                      onTap: _pasteImageFromClipboard,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.teal, width: 1.5),
                        ),
                        child: _selectedImageBytes != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  _selectedImageBytes!,
                                  fit: BoxFit.contain,
                                ),
                              )
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.content_paste_go,
                                    size: 60,
                                    color: Colors.teal,
                                  ),
                                  SizedBox(height: 12),
                                  Text(
                                    'Chuột phải "Copy Image" trên web\nrồi bấm vào đây để dán ảnh',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isUploading ? null : _publishToGitHub,
                    icon: _isUploading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.cloud_upload),
                    label: Text(
                      _isUploading
                          ? 'ĐANG ĐẨY LÊN GITHUB...'
                          : 'ĐĂNG MÓN LÊN GITHUB',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 18),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height:
                        140, // Giới hạn chiều cao và cho phép cuộn nếu lỗi dài
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Log trạng thái / Lỗi:',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                            InkWell(
                              onTap: () {
                                Clipboard.setData(
                                  ClipboardData(text: _statusLog),
                                );
                                _showMsg('Đã copy toàn bộ nội dung log!');
                              },
                              child: const Row(
                                children: [
                                  Icon(
                                    Icons.copy,
                                    size: 14,
                                    color: Colors.tealAccent,
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Copy log',
                                    style: TextStyle(
                                      color: Colors.tealAccent,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: Colors.white24, height: 12),
                        Expanded(
                          child: SingleChildScrollView(
                            child: SelectableText(
                              _statusLog,
                              style: const TextStyle(
                                color: Colors.tealAccent,
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
