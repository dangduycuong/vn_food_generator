import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/food_item.dart';

class GitHubService {
  static const String owner = 'dangduycuong';
  static const String repo = 'vietnamese-food-api';
  static const String branch = 'main';

  // Tách chuỗi tên miền để tránh trình duyệt tự rút gọn link
  static const String apiHost =
      'api'
      '.github.com';
  static const String rawHost =
      'raw'
      '.githubusercontent.com';

  static String getImageUrl(String thumbName) {
    return Uri.https(
      rawHost,
      '/$owner/$repo/$branch/images/$thumbName',
    ).toString();
  }

  static Future<List<FoodItem>> fetchItems(String token) async {
    final url = Uri.https(
      apiHost,
      '/repos/$owner/$repo/contents/vietnamese_foods.json',
    );
    final headers = {
      'Accept': 'application/vnd.github+json',
      if (token.isNotEmpty) 'Authorization': 'Bearer $token',
    };

    final res = await http.get(url, headers: headers);
    if (res.statusCode != 200) {
      throw Exception('Mã lỗi ${res.statusCode}: Kiểm tra lại GitHub Token.');
    }

    final meta = json.decode(res.body);
    final rawBase64 = meta['content'].toString().replaceAll('\n', '');
    final Map<String, dynamic> data = json.decode(
      utf8.decode(base64Decode(rawBase64)),
    );
    final List<dynamic> list = data['items'] ?? [];
    return list.map((e) => FoodItem.fromJson(e)).toList();
  }

  static Future<String> saveItem({
    required String token,
    required FoodItem draft,
    required bool isEditing,
    Uint8List? newImageBytes,
  }) async {
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github+json',
      'Content-Type': 'application/json',
    };

    // 1. Upload ảnh nếu có ảnh mới
    if (newImageBytes != null) {
      final imgUrl = Uri.https(
        apiHost,
        '/repos/$owner/$repo/contents/images/${draft.thumb}',
      );
      String? existingSha;
      final checkRes = await http.get(imgUrl, headers: headers);
      if (checkRes.statusCode == 200) {
        existingSha = json.decode(checkRes.body)['sha'];
      }

      final uploadRes = await http.put(
        imgUrl,
        headers: headers,
        body: json.encode({
          'message': 'Upload image ${draft.thumb}',
          'content': base64Encode(newImageBytes),
          'branch': branch,
          'sha': ?existingSha,
        }),
      );
      if (uploadRes.statusCode != 200 && uploadRes.statusCode != 201) {
        throw Exception('Lỗi upload ảnh (Mã ${uploadRes.statusCode})');
      }
    }

    // 2. Đọc file JSON hiện tại
    final jsonUrl = Uri.https(
      apiHost,
      '/repos/$owner/$repo/contents/vietnamese_foods.json',
    );
    final getJsonRes = await http.get(jsonUrl, headers: headers);
    if (getJsonRes.statusCode != 200) {
      throw Exception('Không đọc được file JSON (Mã ${getJsonRes.statusCode})');
    }

    final meta = json.decode(getJsonRes.body);
    final String fileSha = meta['sha'];
    final Map<String, dynamic> rootData = json.decode(
      utf8.decode(
        base64Decode(meta['content'].toString().replaceAll('\n', '')),
      ),
    );
    final List<dynamic> items = rootData['items'] ?? [];

    String targetId = draft.id;
    String commitMsg;

    if (isEditing) {
      final index = items.indexWhere((e) => e['id'] == targetId);
      if (index == -1) {
        throw Exception('Không tìm thấy món $targetId để sửa.');
      }
      items[index] = draft.toJson();
      commitMsg = 'Update dish: ${draft.name} ($targetId)';
    } else {
      int maxNum = 0;
      for (var item in items) {
        final match = RegExp(r'(\d+)$').firstMatch(item['id'].toString());
        if (match != null) {
          final num = int.parse(match.group(1)!);
          if (num > maxNum) maxNum = num;
        }
      }
      targetId = 'vn_${(maxNum + 1).toString().padLeft(2, '0')}';

      final newItem = FoodItem(
        id: targetId,
        name: draft.name,
        category: draft.category,
        area: draft.area,
        thumb: draft.thumb,
        ingredients: draft.ingredients,
        instructions: draft.instructions,
      );
      items.add(newItem.toJson());
      commitMsg = 'Add dish: ${draft.name} ($targetId)';
    }

    rootData['items'] = items;
    final updatedJson = const JsonEncoder.withIndent('  ').convert(rootData);

    final updateRes = await http.put(
      jsonUrl,
      headers: headers,
      body: json.encode({
        'message': commitMsg,
        'content': base64Encode(utf8.encode(updatedJson)),
        'sha': fileSha,
        'branch': branch,
      }),
    );

    if (updateRes.statusCode != 200) {
      throw Exception('Lỗi lưu JSON (Mã ${updateRes.statusCode})');
    }
    return commitMsg;
  }

  static Future<void> deleteItem(String token, FoodItem item) async {
    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github+json',
      'Content-Type': 'application/json',
    };

    final jsonUrl = Uri.https(
      apiHost,
      '/repos/$owner/$repo/contents/vietnamese_foods.json',
    );
    final getJsonRes = await http.get(jsonUrl, headers: headers);
    if (getJsonRes.statusCode != 200) {
      throw Exception('Không đọc được file JSON.');
    }

    final meta = json.decode(getJsonRes.body);
    final Map<String, dynamic> rootData = json.decode(
      utf8.decode(
        base64Decode(meta['content'].toString().replaceAll('\n', '')),
      ),
    );
    final List<dynamic> items = rootData['items'] ?? [];

    items.removeWhere((e) => e['id'] == item.id);
    rootData['items'] = items;

    await http.put(
      jsonUrl,
      headers: headers,
      body: json.encode({
        'message': 'Delete dish: ${item.name} (${item.id})',
        'content': base64Encode(
          utf8.encode(const JsonEncoder.withIndent('  ').convert(rootData)),
        ),
        'sha': meta['sha'],
        'branch': branch,
      }),
    );

    if (item.thumb.isNotEmpty) {
      final imgUrl = Uri.https(
        apiHost,
        '/repos/$owner/$repo/contents/images/${item.thumb}',
      );
      final imgMetaRes = await http.get(imgUrl, headers: headers);
      if (imgMetaRes.statusCode == 200) {
        final imgSha = json.decode(imgMetaRes.body)['sha'];
        await http.delete(
          imgUrl,
          headers: headers,
          body: json.encode({
            'message': 'Delete image ${item.thumb}',
            'sha': imgSha,
            'branch': branch,
          }),
        );
      }
    }
  }
}
