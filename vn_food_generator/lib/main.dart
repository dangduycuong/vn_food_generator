import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_clipboard/super_clipboard.dart';

void main() => runApp(
  const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: GitHubFoodManagerPage(),
  ),
);

class GitHubFoodManagerPage extends StatefulWidget {
  const GitHubFoodManagerPage({super.key});

  @override
  State<GitHubFoodManagerPage> createState() => _GitHubFoodManagerPageState();
}

class _GitHubFoodManagerPageState extends State<GitHubFoodManagerPage> {
  static const String _apiHost =
      'api'
      '.github.com';
  static const String _rawHost =
      'raw'
      '.githubusercontent.com';

  final String _owner = 'dangduycuong';
  final String _repo = 'vietnamese-food-api';
  final String _branch = 'main';
  static const String _tokenStorageKey = 'github_pat_token';

  String _savedToken = '';

  final _nameController = TextEditingController();
  final _areaController = TextEditingController(text: 'Hà Nội');
  final _thumbNameController = TextEditingController();
  final _ingredientsController = TextEditingController();
  final _instructionsController = TextEditingController();

  String _selectedCategory = 'Món Nước';
  Uint8List? _selectedImageBytes;
  String? _selectedImageExt;

  List<Map<String, dynamic>> _existingItems = [];
  String? _editingId;
  String? _oldThumbName;
  bool _isLoadingList = false;
  bool _isSaving = false;
  String _statusLog = 'Đang khởi tạo...';

  final List<String> _categories = [
    'Món Nước',
    'Món Khô',
    'Món Cuốn & Bánh',
    'Đồ Uống',
    'Món Chay',
  ];

  @override
  void initState() {
    super.initState();
    _initTokenAndLoadData();
  }

  // 1. Đọc Token đã lưu trong máy -> Nếu chưa có thì mở bảng Cài đặt
  Future<void> _initTokenAndLoadData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenStorageKey) ?? '';

    setState(() => _savedToken = token);

    if (token.isEmpty) {
      setState(
        () => _statusLog =
            '⚠️ Chưa cấu hình GitHub Token. Vui lòng nhập Token để bắt đầu.',
      );
      // Đợi khung hình render xong rồi bật popup cài đặt
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _showTokenSettingsDialog(isFirstTime: true);
      });
    } else {
      await _fetchExistingItems();
    }
  }

  // 2. Hộp thoại Cài đặt & Lưu GitHub Token
  Future<void> _showTokenSettingsDialog({bool isFirstTime = false}) async {
    final dialogController = TextEditingController(text: _savedToken);

    await showDialog(
      context: context,
      barrierDismissible: !isFirstTime, // Bắt buộc nhập nếu là lần đầu
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.vpn_key, color: Colors.teal),
            SizedBox(width: 8),
            Text('Cấu hình GitHub Token'),
          ],
        ),
        content: SizedBox(
          width: 450,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Token sẽ được lưu cục bộ trên máy này để tự động kết nối mỗi lần mở ứng dụng.',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: dialogController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Personal Access Token (ghp_...)',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (!isFirstTime)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.teal,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.check),
            label: const Text('Lưu & Kết nối'),
            onPressed: () async {
              final newToken = dialogController.text.trim();
              if (newToken.isEmpty) return;

              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(_tokenStorageKey, newToken);

              setState(() => _savedToken = newToken);
              if (ctx.mounted) Navigator.pop(ctx);
              await _fetchExistingItems();
            },
          ),
        ],
      ),
    );
  }

  // 3. Tải danh sách món hiện có từ GitHub
  Future<void> _fetchExistingItems() async {
    setState(() {
      _isLoadingList = true;
      _statusLog = '⏳ Đang tải danh sách món từ GitHub...';
    });

    try {
      final jsonApiUrl = Uri.https(
        _apiHost,
        '/repos/$_owner/$_repo/contents/vietnamese_foods.json',
      );
      final headers = {
        'Accept': 'application/vnd.github+json',
        if (_savedToken.isNotEmpty) 'Authorization': 'Bearer $_savedToken',
      };

      final res = await http.get(jsonApiUrl, headers: headers);
      if (res.statusCode == 200) {
        final meta = json.decode(res.body);
        final rawBase64 = meta['content'].toString().replaceAll('\n', '');
        final jsonStr = utf8.decode(base64Decode(rawBase64));
        final Map<String, dynamic> data = json.decode(jsonStr);
        final List<dynamic> list = data['items'] ?? [];

        setState(() {
          _existingItems = list.cast<Map<String, dynamic>>();
          _statusLog =
              '✅ Kết nối thành công! Đã tải ${_existingItems.length} món.';
        });
      } else {
        throw Exception(
          'Mã lỗi ${res.statusCode}: Kiểm tra lại Token trong mục Cài đặt (⚙️).',
        );
      }
    } catch (e) {
      setState(() => _statusLog = '❌ Lỗi tải danh sách: $e');
    } finally {
      setState(() => _isLoadingList = false);
    }
  }

  void _startEditing(Map<String, dynamic> item) {
    setState(() {
      _editingId = item['id'];
      _oldThumbName = item['thumb'];
      _nameController.text = item['name'] ?? '';
      _areaController.text = item['area'] ?? '';
      _thumbNameController.text = item['thumb'] ?? '';

      final cat = item['category']?.toString() ?? 'Món Nước';
      _selectedCategory = _categories.contains(cat) ? cat : _categories.first;

      final List<dynamic> ings = item['ingredients'] ?? [];
      _ingredientsController.text = ings.join('\n');
      _instructionsController.text = item['instructions'] ?? '';

      _selectedImageBytes = null;
      _statusLog = '✏️ Đang sửa món: ${item['name']} (${item['id']})';
    });
  }

  void _resetToAddMode() {
    setState(() {
      _editingId = null;
      _oldThumbName = null;
      _nameController.clear();
      _areaController.text = 'Hà Nội';
      _thumbNameController.clear();
      _ingredientsController.clear();
      _instructionsController.clear();
      _selectedImageBytes = null;
      _statusLog = '➕ Đã chuyển sang chế độ Thêm món mới.';
    });
  }

  Future<void> _pasteImageFromClipboard() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;
    final reader = await clipboard.read();

    if (reader.canProvide(Formats.png)) {
      reader.getFile(
        Formats.png,
        (file) async => _applyImageBytes(await file.readAll(), 'png'),
      );
    } else if (reader.canProvide(Formats.jpeg)) {
      reader.getFile(
        Formats.jpeg,
        (file) async => _applyImageBytes(await file.readAll(), 'jpg'),
      );
    } else if (reader.canProvide(Formats.webp)) {
      reader.getFile(
        Formats.webp,
        (file) async => _applyImageBytes(await file.readAll(), 'webp'),
      );
    } else {
      _showMsg(
        'Không có ảnh trong Clipboard! Hãy chuột phải "Copy Image" trên web trước.',
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
            'mon_${DateTime.now().millisecondsSinceEpoch}.$ext';
      }
      _statusLog =
          '✅ Đã nhận ảnh mới (${(bytes.length / 1024).toStringAsFixed(1)} KB)';
    });
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result != null && result.files.single.bytes != null) {
      final file = result.files.single;
      _applyImageBytes(file.bytes!, (file.extension ?? 'jpg').toLowerCase());
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

  Future<void> _saveToGitHub() async {
    if (_savedToken.isEmpty) {
      _showTokenSettingsDialog(isFirstTime: true);
      return;
    }
    if (_nameController.text.trim().isEmpty) {
      _showMsg('Vui lòng nhập Tên món ăn!', isError: true);
      return;
    }
    if (_editingId == null && _selectedImageBytes == null) {
      _showMsg('Vui lòng dán hoặc chọn ảnh cho món mới!', isError: true);
      return;
    }

    setState(() {
      _isSaving = true;
      _statusLog = '⏳ Đang xử lý dữ liệu lên GitHub...';
    });

    final headers = {
      'Authorization': 'Bearer $_savedToken',
      'Accept': 'application/vnd.github+json',
      'Content-Type': 'application/json',
    };
    try {
      final imageFileName = _thumbNameController.text.trim();
      if (_selectedImageBytes != null) {
        setState(
          () => _statusLog = '⏳ Đang tải ảnh $imageFileName lên GitHub...',
        );
        final imageApiUrl = Uri.https(
          'github.com',
          '/repos/$_owner/$_repo/contents/images/$imageFileName',
        );
        String? existingSha;
        final checkRes = await http.get(imageApiUrl, headers: headers);
        if (checkRes.statusCode == 200) {
          existingSha = json.decode(checkRes.body)['sha'];
        }
        final uploadRes = await http.put(
          imageApiUrl,
          headers: headers,
          body: json.encode({
            'message': 'Upload image $imageFileName',
            'content': base64Encode(_selectedImageBytes!),
            'branch': _branch,
            'sha': ?existingSha,
          }),
        );
        if (uploadRes.statusCode != 200 && uploadRes.statusCode != 201) {
          throw Exception('Lỗi upload ảnh: ${uploadRes.body}');
        }
      }
      final jsonApiUrl = Uri.https(
        _apiHost,
        '/repos/$_owner/$_repo/contents/vietnamese_foods.json',
      );
      final getJsonRes = await http.get(jsonApiUrl, headers: headers);
      if (getJsonRes.statusCode != 200) {
        throw Exception('Không đọc được file JSON: ${getJsonRes.body}');
      }
      final meta = json.decode(getJsonRes.body);
      final String fileSha = meta['sha'];
      final String currentJson = utf8.decode(
        base64Decode(meta['content'].toString().replaceAll('\n', '')),
      );
      final Map<String, dynamic> rootData = json.decode(currentJson);
      final List items = rootData['items'] ?? [];
      final ingredientsList = _ingredientsController.text
          .split('\n')
          .map((line) => line.replaceFirst(RegExp(r'^[-•+]\s'), '').trim())
          .where((line) => line.isNotEmpty)
          .toList();
      String targetId;
      String commitMessage;
      if (_editingId != null) {
        targetId = _editingId!;
        final index = items.indexWhere((e) => e['id'] == targetId);
        if (index == -1) {
          throw Exception('Không tìm thấy món $targetId để sửa.');
        }
        items[index] = {
          'id': targetId,
          'name': _nameController.text.trim(),
          'category': _selectedCategory,
          'area': _areaController.text.trim(),
          'thumb': imageFileName,
          'ingredients': ingredientsList,
          'instructions': _instructionsController.text.trim(),
        };
        commitMessage =
            'Update dish: ${_nameController.text.trim()} ($targetId)';
      } else {
        int maxNum = 0;
        for (var item in items) {
          final match = RegExp(r'(\d+)$').firstMatch(item['id'].toString());
          if (match != null) {
            final num = int.parse(match.group(1)!);
            if (num > maxNum) {
              maxNum = num;
            }
          }
        }
        targetId = 'vn${(maxNum + 1).toString().padLeft(2, '0')}';
        items.add({
          'id': targetId,
          'name': _nameController.text.trim(),
          'category': _selectedCategory,
          'area': _areaController.text.trim(),
          'thumb': imageFileName,
          'ingredients': ingredientsList,
          'instructions': _instructionsController.text.trim(),
        });
        commitMessage = 'Add dish: ${_nameController.text.trim()} ($targetId)';
      }
      rootData['items'] = items;
      const encoder = JsonEncoder.withIndent('  ');
      final updatedJsonString = encoder.convert(rootData);
      final updateRes = await http.put(
        jsonApiUrl,
        headers: headers,
        body: json.encode({
          'message': commitMessage,
          'content': base64Encode(utf8.encode(updatedJsonString)),
          'sha': fileSha,
          'branch': _branch,
        }),
      );
      if (updateRes.statusCode != 200) {
        throw Exception('Lỗi lưu JSON: ${updateRes.body}');
      }
      _showMsg(
        _editingId != null
            ? 'Đã cập nhật món thành công!'
            : 'Đã thêm món mới thành công!',
      );
      _resetToAddMode();
      await _fetchExistingItems();
      setState(() => _statusLog = '🎉 THÀNH CÔNG! ($commitMessage)');
    } catch (e) {
      setState(() => _statusLog = '❌ LỖI:\n$e');
      _showMsg('Thao tác thất bại, xem chi tiết ở khung Log.', isError: true);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future _deleteItem(Map<String, dynamic> item) async {
    if (_savedToken.isEmpty) {
      _showTokenSettingsDialog(isFirstTime: true);
      return;
    }
    final confirm = await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa món'),
        content: Text(
          'Bạn có chắc muốn xóa món "${item['name']}" (${item['id']}) khỏi GitHub không?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Xóa vĩnh viễn'),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    setState(() {
      _isSaving = true;
      _statusLog = '⏳ Đang xóa món "${item['name']}"...';
    });
    final headers = {
      'Authorization': 'Bearer $_savedToken',
      'Accept': 'application/vnd.github+json',
      'Content-Type': 'application/json',
    };
    try {
      final jsonApiUrl = Uri.https(
        _apiHost,
        '/repos/$_owner/$_repo/contents/vietnamese_foods.json',
      );
      final getJsonRes = await http.get(jsonApiUrl, headers: headers);
      if (getJsonRes.statusCode != 200) {
        throw Exception('Không đọc được file JSON.');
      }
      final meta = json.decode(getJsonRes.body);
      final String fileSha = meta['sha'];
      final String currentJson = utf8.decode(
        base64Decode(meta['content'].toString().replaceAll('\n', '')),
      );
      final Map<String, dynamic> rootData = json.decode(currentJson);
      final List items = rootData['items'] ?? [];
      items.removeWhere((e) => e['id'] == item['id']);
      rootData['items'] = items;
      const encoder = JsonEncoder.withIndent('  ');
      final updateRes = await http.put(
        jsonApiUrl,
        headers: headers,
        body: json.encode({
          'message': 'Delete dish: ${item['name']} (${item['id']})',
          'content': base64Encode(utf8.encode(encoder.convert(rootData))),
          'sha': fileSha,
          'branch': _branch,
        }),
      );
      if (updateRes.statusCode != 200) {
        throw Exception('Lỗi cập nhật JSON khi xóa.');
      }
      final thumbName = item['thumb']?.toString() ?? '';
      if (thumbName.isNotEmpty) {
        final imgUrl = Uri.https(
          _apiHost,
          '/repos/$_owner/$_repo/contents/images/$thumbName',
        );
        final imgMetaRes = await http.get(imgUrl, headers: headers);
        if (imgMetaRes.statusCode == 200) {
          final imgSha = json.decode(imgMetaRes.body)['sha'];
          await http.delete(
            imgUrl,
            headers: headers,
            body: json.encode({
              'message': 'Delete image $thumbName',
              'sha': imgSha,
              'branch': _branch,
            }),
          );
        }
      }
      if (_editingId == item['id']) {
        _resetToAddMode();
      }
      _showMsg('Đã xóa món "${item['name']}" thành công!');
      await _fetchExistingItems();
      setState(() => _statusLog = '🗑️ Đã xóa xong món "${item['name']}".');
    } catch (e) {
      setState(() => _statusLog = '❌ LỖI KHI XÓA:\n$e');
      _showMsg('Lỗi khi xóa món, xem chi tiết ở khung Log.', isError: true);
    } finally {
      setState(() => _isSaving = false);
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
  Widget build(BuildContext context) {
    final isEditing = _editingId != null;
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Quản lý Dữ liệu Ẩm thực Việt Nam (Thêm / Sửa / Xóa)',
        ),
        backgroundColor: isEditing ? Colors.orange.shade800 : Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          if (isEditing)
            TextButton.icon(
              onPressed: _resetToAddMode,
              icon: const Icon(Icons.add_circle_outline, color: Colors.white),
              label: const Text(
                'Hủy sửa / Thêm mới',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          IconButton(
            onPressed: _fetchExistingItems,
            tooltip: 'Tải lại danh sách từ GitHub',
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () => _showTokenSettingsDialog(),
            tooltip: 'Cài đặt GitHub Token',
            icon: const Icon(Icons.settings),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Row(
        children: [
          // CỘT 1: DANH SÁCH MÓN ĐÃ ĐĂNG
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                border: Border(right: BorderSide(color: Colors.grey.shade300)),
              ),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.grey.shade200,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Danh sách món (${_existingItems.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Text(
                          'Bấm để Sửa',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: _isLoadingList
                        ? const Center(child: CircularProgressIndicator())
                        : Material(
                            type: MaterialType.transparency,
                            child: ListView.separated(
                              itemCount: _existingItems.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, index) {
                                final item = _existingItems[index];
                                final isSelected = item['id'] == _editingId;
                                final imgUrl = Uri.https(
                                  _rawHost,
                                  '/$_owner/$_repo/$_branch/images/${item['thumb']}',
                                ).toString();
                                return ListTile(
                                  selected: isSelected,
                                  selectedTileColor: Colors.orange.shade50,
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      imgUrl,
                                      width: 44,
                                      height: 44,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          const Icon(Icons.fastfood, size: 32),
                                    ),
                                  ),
                                  title: Text(
                                    item['name'] ?? '',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${item['id']} • ${item['category']}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  onTap: () => _startEditing(item),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                      size: 20,
                                    ),
                                    tooltip: 'Xóa món này',
                                    onPressed: _isSaving
                                        ? null
                                        : () => _deleteItem(item),
                                  ),
                                );
                              },
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
          // CỘT 2: FORM NHẬP / SỬA THÔNG TIN
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: isEditing
                                ? 'Đang sửa tên món ($_editingId)'
                                : 'Tên món ăn mới',
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (val) {
                            if (!isEditing || _selectedImageBytes != null) {
                              final ext = _selectedImageExt ?? 'png';
                              _thumbNameController.text =
                                  '${_slugify(val)}.$ext';
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: DropdownButtonFormField(
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
                            labelText: 'Tên file ảnh trên GitHub',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _ingredientsController,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: 'Nguyên liệu (Mỗi dòng 1 nguyên liệu)',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _instructionsController,
                    maxLines: 9,
                    decoration: const InputDecoration(
                      labelText: 'Cách chế biến',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          // CỘT 3: HÌNH ẢNH & NÚT LƯU
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
                        'Hình ảnh:',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pasteImageFromClipboard,
                            icon: const Icon(Icons.paste, size: 16),
                            label: const Text('Dán ảnh'),
                          ),
                          IconButton(
                            onPressed: _pickImage,
                            tooltip: 'Chọn file từ máy',
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
                          border: Border.all(
                            color: isEditing ? Colors.orange : Colors.teal,
                            width: 1.5,
                          ),
                        ),
                        child: _selectedImageBytes != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.memory(
                                  _selectedImageBytes!,
                                  fit: BoxFit.contain,
                                ),
                              )
                            : (isEditing &&
                                  _oldThumbName != null &&
                                  _oldThumbName!.isNotEmpty)
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: Image.network(
                                  Uri.https(
                                    _rawHost,
                                    '/$_owner/$_repo/$_branch/images/$_oldThumbName',
                                  ).toString(),
                                  fit: BoxFit.contain,
                                  errorBuilder: (_, _, _) => const Center(
                                    child: Text('Không tải được ảnh cũ'),
                                  ),
                                ),
                              )
                            : const Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.content_paste_go,
                                    size: 50,
                                    color: Colors.teal,
                                  ),
                                  SizedBox(height: 8),
                                  Text(
                                    'Bấm vào đây để dán ảnh',
                                    style: TextStyle(color: Colors.black54),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _saveToGitHub,
                    icon: _isSaving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : Icon(isEditing ? Icons.save : Icons.cloud_upload),
                    label: Text(
                      _isSaving
                          ? 'ĐANG LƯU...'
                          : (isEditing
                                ? 'LƯU THAY ĐỔI ($_editingId)'
                                : 'ĐĂNG MÓN MỚI'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isEditing
                          ? Colors.orange.shade800
                          : Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    height: 120,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade900,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: SingleChildScrollView(
                      child: SelectableText(
                        _statusLog,
                        style: const TextStyle(
                          color: Colors.tealAccent,
                          fontFamily: 'monospace',
                          fontSize: 11,
                        ),
                      ),
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
