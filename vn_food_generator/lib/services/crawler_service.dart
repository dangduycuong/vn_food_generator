import 'dart:convert';
import 'dart:typed_data';

import 'package:html/parser.dart' as html_parser;
import 'package:http/http.dart' as http;

class CrawlResult {
  final String name;
  final List<String> ingredients;
  final String instructions;
  final Uint8List? imageBytes;
  final String imageExt;

  CrawlResult({
    required this.name,
    required this.ingredients,
    required this.instructions,
    this.imageBytes,
    this.imageExt = 'jpg',
  });
}

class CrawlerService {
  static Future<CrawlResult> crawlFromUrl(String rawUrl) async {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasScheme) {
      throw Exception('Đường link không hợp lệ.');
    }

    final response = await http.get(
      uri,
      headers: {
        'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36',
      },
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Không tải được trang web (Mã lỗi ${response.statusCode})',
      );
    }

    final document = html_parser.parse(utf8.decode(response.bodyBytes));

    // 1. Tách tên món từ thẻ H1
    final h1Text = document.querySelector('h1')?.text.trim() ?? '';
    final cleanName = h1Text
        .replaceFirst(RegExp(r'^Cách Làm\s+', caseSensitive: false), '')
        .split(
          RegExp(
            r'\s+(Giòn|Ngon|Đậm|Chuẩn|Đơn Giản|Tại Nhà)',
            caseSensitive: false,
          ),
        )
        .first
        .trim();

    // 2. Săn tìm URL ảnh đại diện (Meta tags + Ảnh trong thân bài)
    String? foundImgUrl =
        document
            .querySelector('meta[property="og:image"]')
            ?.attributes['content'] ??
        document
            .querySelector('meta[name="twitter:image"]')
            ?.attributes['content'];

    final contentNode =
        document.querySelector('.entry-content') ??
        document.querySelector('article') ??
        document.body;

    if ((foundImgUrl == null || foundImgUrl.isEmpty) && contentNode != null) {
      for (final img in contentNode.querySelectorAll('img')) {
        final candidate =
            img.attributes['data-src'] ??
            img.attributes['data-lazy-src'] ??
            img.attributes['src'] ??
            '';
        if (candidate.startsWith('http') &&
            !candidate.contains('logo') &&
            !candidate.contains('icon') &&
            !candidate.contains('avatar')) {
          foundImgUrl = candidate;
          break;
        }
      }
    }

    // 3. Tải bytes của ảnh tìm được
    Uint8List? imageBytes;
    String imageExt = 'jpg';
    if (foundImgUrl != null && foundImgUrl.isNotEmpty) {
      final imgUri = Uri.tryParse(foundImgUrl);
      if (imgUri != null) {
        final imgRes = await http.get(imgUri, headers: {'Referer': rawUrl});
        if (imgRes.statusCode == 200 && imgRes.bodyBytes.length > 2000) {
          imageBytes = imgRes.bodyBytes;
          if (foundImgUrl.toLowerCase().contains('.png')) imageExt = 'png';
          if (foundImgUrl.toLowerCase().contains('.webp')) imageExt = 'webp';
        }
      }
    }

    // 4. Quét Nguyên liệu & Cách làm
    final List<String> ingredients = [];
    final List<String> instructions = [];
    String section = '';

    if (contentNode != null) {
      for (final el in contentNode.querySelectorAll('h2, h3, h4, li, p')) {
        final tag = el.localName ?? '';
        final text = el.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (text.isEmpty) continue;

        if (tag == 'h2' || tag == 'h3' || tag == 'h4') {
          final lower = text.toLowerCase();
          if (lower.contains('nguyên liệu')) {
            section = 'ingredients';
            continue;
          } else if (lower.contains('cách làm') ||
              lower.contains('cách nấu') ||
              lower.contains('chế biến')) {
            section = 'instructions';
            continue;
          } else if (lower.startsWith('bước ') && section == 'instructions') {
            instructions.add('\n$text:');
            continue;
          } else if (tag == 'h2' &&
              (lower.contains('bí quyết') ||
                  lower.contains('thưởng thức') ||
                  lower.contains('biến tấu') ||
                  lower.contains('lỗi thường gặp'))) {
            break;
          }
        }

        if (section == 'ingredients' && tag == 'li') {
          if (!RegExp(r'^\d+\.\s').hasMatch(text)) {
            ingredients.add(text);
          }
        } else if (section == 'instructions' && (tag == 'p' || tag == 'li')) {
          if (!text.contains('Ảnh:') && !text.startsWith('Xem thêm')) {
            instructions.add(text);
          }
        }
      }
    }

    return CrawlResult(
      name: cleanName.isNotEmpty ? cleanName : h1Text,
      ingredients: ingredients,
      instructions: instructions.join('\n').trim(),
      imageBytes: imageBytes,
      imageExt: imageExt,
    );
  }
}
