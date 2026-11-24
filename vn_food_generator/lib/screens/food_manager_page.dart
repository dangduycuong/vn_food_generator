import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_clipboard/super_clipboard.dart';

import '../models/food_item.dart';
import '../services/crawler_service.dart';
import '../services/github_service.dart';

class FoodManagerPage extends StatefulWidget {
  const FoodManagerPage({super.key});

  @override
  State<FoodManagerPage> createState() => _FoodManagerPageState();
}

class _FoodManagerPageState extends State<FoodManagerPage> {
  static const String _tokenStorageKey = 'github_pat_token';
  String _savedToken = '';

  final _crawlUrlController = TextEditingController();
  final _nameController = TextEditingController();
  final _areaController = TextEditingController(text: 'Hà Nội');
  final _thumbNameController = TextEditingController();
  final _ingredientsController = TextEditingController();
  final _instructionsController = TextEditingController();

  String _selectedCategory = 'Món Nước';
  Uint8List? _selectedImageBytes;
  String? _selectedImageExt;

  List<FoodItem> _existingItems = [];
  String? _editingId;
  String? _oldThumbName;
  bool _isLoadingList = false;
  bool _isCrawling = false;
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

  Future<void> _initTokenAndLoadData() async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString(_tokenStorageKey) ?? '';
    setState(() => _savedToken = token);

    if (token.isEmpty) {
      setState(() => _statusLog = '⚠️ Chưa cấu hình GitHub Token.');
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _showTokenDialog(isFirstTime: true),
      );
    } else {
      await _loadItems();
    }
  }

  Future<void> _showTokenDialog({bool isFirstTime = false}) async {
    final dialogCtrl = TextEditingController(text: _savedToken);
    await showDialog(
      context: context,
      barrierDismissible: !isFirstTime,
      builder: (ctx) => AlertDialog(
        title: const Text('Cấu hình GitHub Token'),
        content: SizedBox(
          width: 420,
          child: TextField(
            controller: dialogCtrl,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Personal Access Token (ghp_...)',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          if (!isFirstTime)
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Đóng'),
            ),
          ElevatedButton(
            onPressed: () async {
              final newToken = dialogCtrl.text.trim();
              if (newToken.isEmpty) return;
              final prefs = await SharedPreferences.getInstance();
              await prefs.setString(_tokenStorageKey, newToken);
              setState(() => _savedToken = newToken);
              if (ctx.mounted) Navigator.pop(ctx);
              await _loadItems();
            },
            child: const Text('Lưu & Kết nối'),
          ),
        ],
      ),
    );
  }

  Future<void> _loadItems() async {
    setState(() {
      _isLoadingList = true;
      _statusLog = '⏳ Đang tải danh sách từ GitHub...';
    });
    try {
      final list = await GitHubService.fetchItems(_savedToken);
      setState(() {
        _existingItems = list;
        _statusLog = '✅ Đã tải ${list.length} món từ GitHub.';
      });
    } catch (e) {
      setState(() => _statusLog = '❌ Lỗi tải danh sách: $e');
    } finally {
      setState(() => _isLoadingList = false);
    }
  }

  Future<void> _handleCrawl() async {
    if (_crawlUrlController.text.trim().isEmpty) {
      _showMsg('Vui lòng dán đường link bài viết trước!', isError: true);
      return;
    }
    setState(() {
      _isCrawling = true;
      _statusLog = '⏳ Đang tải và bóc tách dữ liệu từ web...';
    });
    try {
      final result = await CrawlerService.crawlFromUrl(
        _crawlUrlController.text,
      );
      _resetToAddMode();
      setState(() {
        _nameController.text = result.name;
        _selectedImageBytes = result.imageBytes;
        _selectedImageExt = result.imageExt;
        _thumbNameController.text =
            '${FoodItem.slugify(result.name)}.${result.imageExt}';
        _ingredientsController.text = result.ingredients.join('\n');
        _instructionsController.text = result.instructions;
        _statusLog =
            '✅ Crawl xong: ${result.name}\n'
            '- Nguyên liệu: ${result.ingredients.length} mục\n'
            '- Tự động tải ảnh: ${result.imageBytes != null ? "Thành công" : "Không tìm thấy ảnh phù hợp"}';
      });
    } catch (e) {
      setState(() => _statusLog = '❌ Lỗi Crawl: $e');
      _showMsg('Không thể lấy dữ liệu từ link này.', isError: true);
    } finally {
      setState(() => _isCrawling = false);
    }
  }

  void _startEditing(FoodItem item) {
    setState(() {
      _editingId = item.id;
      _oldThumbName = item.thumb;
      _nameController.text = item.name;
      _areaController.text = item.area;
      _thumbNameController.text = item.thumb;
      _selectedCategory = _categories.contains(item.category)
          ? item.category
          : _categories.first;
      _ingredientsController.text = item.ingredients.join('\n');
      _instructionsController.text = item.instructions;
      _selectedImageBytes = null;
      _statusLog = '✏️ Đang sửa: ${item.name} (${item.id})';
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
      _statusLog = '➕ Chế độ Thêm món mới.';
    });
  }

  Future<void> _pasteImage() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;
    final reader = await clipboard.read();
    if (reader.canProvide(Formats.png)) {
      reader.getFile(
        Formats.png,
        (f) async => _applyImage(await f.readAll(), 'png'),
      );
    } else if (reader.canProvide(Formats.jpeg)) {
      reader.getFile(
        Formats.jpeg,
        (f) async => _applyImage(await f.readAll(), 'jpg'),
      );
    } else if (reader.canProvide(Formats.webp)) {
      reader.getFile(
        Formats.webp,
        (f) async => _applyImage(await f.readAll(), 'webp'),
      );
    } else {
      _showMsg('Clipboard không có ảnh!', isError: true);
    }
  }

  Future<void> _pickImage() async {
    final res = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (res != null && res.files.single.bytes != null) {
      _applyImage(
        res.files.single.bytes!,
        (res.files.single.extension ?? 'jpg').toLowerCase(),
      );
    }
  }

  void _applyImage(Uint8List bytes, String ext) {
    setState(() {
      _selectedImageBytes = bytes;
      _selectedImageExt = ext;
      if (_nameController.text.isNotEmpty) {
        _thumbNameController.text =
            '${FoodItem.slugify(_nameController.text)}.$ext';
      }
      _statusLog =
          '✅ Đã nhận ảnh (${(bytes.length / 1024).toStringAsFixed(1)} KB)';
    });
  }

  Future<void> _handleSave() async {
    if (_savedToken.isEmpty) return _showTokenDialog(isFirstTime: true);
    if (_nameController.text.trim().isEmpty) {
      return _showMsg('Vui lòng nhập tên món ăn!', isError: true);
    }
    if (_editingId == null && _selectedImageBytes == null) {
      return _showMsg('Vui lòng chọn hoặc dán ảnh cho món mới!', isError: true);
    }

    setState(() {
      _isSaving = true;
      _statusLog = '⏳ Đang lưu lên GitHub...';
    });

    try {
      final ingredients = _ingredientsController.text
          .split('\n')
          .map((e) => e.replaceFirst(RegExp(r'^[-•*+]\s*'), '').trim())
          .where((e) => e.isNotEmpty)
          .toList();

      final draft = FoodItem(
        id: _editingId ?? '',
        name: _nameController.text.trim(),
        category: _selectedCategory,
        area: _areaController.text.trim(),
        thumb: _thumbNameController.text.trim(),
        ingredients: ingredients,
        instructions: _instructionsController.text.trim(),
      );

      final msg = await GitHubService.saveItem(
        token: _savedToken,
        draft: draft,
        isEditing: _editingId != null,
        newImageBytes: _selectedImageBytes,
      );

      _showMsg('Lưu thành công!');
      _resetToAddMode();
      await _loadItems();
      setState(() => _statusLog = '🎉 THÀNH CÔNG: $msg');
    } catch (e) {
      setState(() => _statusLog = '❌ LỖI LƯU: $e');
      _showMsg('Lưu thất bại, xem chi tiết ở Log.', isError: true);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _handleDelete(FoodItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Xác nhận xóa'),
        content: Text('Xóa vĩnh viễn món "${item.name}" khỏi GitHub?'),
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
            child: const Text('Xóa'),
          ),
        ],
      ),
    );
    if (ok != true) return;

    setState(() => _isSaving = true);
    try {
      await GitHubService.deleteItem(_savedToken, item);
      if (_editingId == item.id) _resetToAddMode();
      _showMsg('Đã xóa "${item.name}"');
      await _loadItems();
    } catch (e) {
      setState(() => _statusLog = '❌ Lỗi xóa: $e');
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
        title: const Text('Quản lý Dữ liệu Ẩm thực Việt Nam'),
        backgroundColor: isEditing ? Colors.orange.shade800 : Colors.teal,
        foregroundColor: Colors.white,
        actions: [
          if (isEditing)
            TextButton.icon(
              onPressed: _resetToAddMode,
              icon: const Icon(Icons.add, color: Colors.white),
              label: const Text(
                'Thêm mới',
                style: TextStyle(color: Colors.white),
              ),
            ),
          IconButton(
            onPressed: _loadItems,
            icon: const Icon(Icons.refresh),
            tooltip: 'Tải lại',
          ),
          IconButton(
            onPressed: () => _showTokenDialog(),
            icon: const Icon(Icons.settings),
            tooltip: 'Token',
          ),
        ],
      ),
      body: Row(
        children: [
          // CỘT 1: DANH SÁCH MÓN
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey.shade50,
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    color: Colors.grey.shade200,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Đã đăng (${_existingItems.length})',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const Text(
                          'Chọn để sửa',
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
                              itemBuilder: (_, i) {
                                final item = _existingItems[i];
                                return ListTile(
                                  selected: item.id == _editingId,
                                  selectedTileColor: Colors.orange.shade50,
                                  leading: ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: Image.network(
                                      GitHubService.getImageUrl(item.thumb),
                                      width: 42,
                                      height: 42,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, _, _) =>
                                          const Icon(Icons.fastfood),
                                    ),
                                  ),
                                  title: Text(
                                    item.name,
                                    style: const TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${item.id} • ${item.category}',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  onTap: () => _startEditing(item),
                                  trailing: IconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                      size: 19,
                                    ),
                                    onPressed: _isSaving
                                        ? null
                                        : () => _handleDelete(item),
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
          // CỘT 2: CRAWL & NHẬP LIỆU
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.teal.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.teal.shade200),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: ValueListenableBuilder<TextEditingValue>(
                            valueListenable: _crawlUrlController,
                            builder: (context, value, child) {
                              return TextField(
                                controller: _crawlUrlController,
                                decoration: InputDecoration(
                                  hintText: 'Dán link bài viết công thức để tự động điền...',
                                  isDense: true,
                                  filled: true,
                                  fillColor: Colors.white,
                                  border: const OutlineInputBorder(),
                                  suffixIcon: value.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(
                                            Icons.clear,
                                            size: 18,
                                          ),
                                          tooltip: 'Xóa link',
                                          onPressed: () =>
                                              _crawlUrlController.clear(),
                                        )
                                      : null,
                                ),
                              );
                            },
                          ),
                        ),

                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: _isCrawling ? null : _handleCrawl,
                          icon: _isCrawling
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.download),
                          label: const Text('Crawl'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        flex: 2,
                        child: TextField(
                          controller: _nameController,
                          decoration: InputDecoration(
                            labelText: isEditing
                                ? 'Đang sửa ($_editingId)'
                                : 'Tên món ăn',
                            border: const OutlineInputBorder(),
                          ),
                          onChanged: (val) {
                            if (!isEditing || _selectedImageBytes != null) {
                              _thumbNameController.text =
                                  '${FoodItem.slugify(val)}.${_selectedImageExt ?? 'jpg'}';
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
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
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _areaController,
                          decoration: const InputDecoration(
                            labelText: 'Vùng miền',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _thumbNameController,
                          decoration: const InputDecoration(
                            labelText: 'Tên file ảnh',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ingredientsController,
                    maxLines: 7,
                    decoration: const InputDecoration(
                      labelText: 'Nguyên liệu (mỗi dòng 1 mục)',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
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
          // CỘT 3: ẢNH & LƯU
          Expanded(
            flex: 2,
            child: Container(
              color: Colors.grey.shade100,
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Hình ảnh:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: [
                          OutlinedButton.icon(
                            onPressed: _pasteImage,
                            icon: const Icon(Icons.paste, size: 15),
                            label: const Text('Dán'),
                          ),
                          IconButton(
                            onPressed: _pickImage,
                            icon: const Icon(
                              Icons.folder_open,
                              color: Colors.teal,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: InkWell(
                      onTap: _pasteImage,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isEditing ? Colors.orange : Colors.teal,
                          ),
                        ),
                        child: _selectedImageBytes != null
                            ? Image.memory(
                                _selectedImageBytes!,
                                fit: BoxFit.contain,
                              )
                            : (isEditing &&
                                  _oldThumbName != null &&
                                  _oldThumbName!.isNotEmpty)
                            ? Image.network(
                                GitHubService.getImageUrl(_oldThumbName!),
                                fit: BoxFit.contain,
                              )
                            : const Center(
                                child: Text('Bấm để dán ảnh hoặc dùng Crawl'),
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  ElevatedButton.icon(
                    onPressed: _isSaving ? null : _handleSave,
                    icon: Icon(isEditing ? Icons.save : Icons.cloud_upload),
                    label: Text(isEditing ? 'LƯU THAY ĐỔI' : 'ĐĂNG MÓN MỚI'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: isEditing
                          ? Colors.orange.shade800
                          : Colors.teal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    height: 110,
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
