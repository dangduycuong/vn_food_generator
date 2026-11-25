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
        .replaceFirst(
          RegExp(r'^Cách Làm\s+(món\s+)?', caseSensitive: false),
          '',
        )
        .split(
          RegExp(
            r'[,|\-]|\s+(Giòn|Ngon|Đậm|Chuẩn|Đơn Giản|Tại Nhà|Siêu|Trắng)',
            caseSensitive: false,
          ),
        )
        .first
        .trim();

    // 2. Săn tìm URL ảnh đại diện
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

    // 4. Quét Nguyên liệu & Cách làm (Bao phủ mọi biến thể tiêu đề)
    final List<String> ingredients = [];
    final List<String> instructions = [];
    String section = '';
    int stepCounter = 0;

    if (contentNode != null) {
      // Xóa hộp Mục Lục (TOC) trước khi duyệt
      contentNode
          .querySelectorAll('#ez-toc-container, .ez-toc-v2_0_69, .toc_widget')
          .forEach((e) => e.remove());

      for (final el in contentNode.querySelectorAll('h2, h3, h4, li, p')) {
        final tag = el.localName ?? '';
        final text = el.text.replaceAll(RegExp(r'\s+'), ' ').trim();
        if (text.isEmpty) continue;

        if (tag == 'h2' || tag == 'h3' || tag == 'h4') {
          final lower = text.toLowerCase();

          // Mốc Nguyên liệu
          if (lower.contains('nguyên liệu') && !lower.contains('sơ chế')) {
            section = 'ingredients';
            continue;
          }

          // Mốc Cách làm (bổ sung thêm từ khóa "hướng dẫn")
          if (lower.contains('cách làm') ||
              lower.contains('các bước') ||
              lower.contains('cách nấu') ||
              lower.contains('chế biến') ||
              lower.contains('thực hiện') ||
              lower.contains('hướng dẫn')) {
            if (tag != 'h2' || !lower.contains(cleanName.toLowerCase())) {
              section = 'instructions';
              continue;
            }
          }

          // Mốc dừng khi sang phần mẹo/lưu ý cuối bài
          if ((tag == 'h2' || tag == 'h3') &&
              (lower.contains('bí quyết') ||
                  (lower.contains('thưởng thức') &&
                      !lower.contains('trình bày')) ||
                  lower.contains('biến tấu') ||
                  lower.contains('lỗi thường gặp') ||
                  lower.contains('mẹo') ||
                  lower.contains('lưu ý'))) {
            if (section == 'instructions') break;
          }

          // Tiêu đề bước con trong H3/H4
          if (section == 'instructions' && (tag == 'h3' || tag == 'h4')) {
            stepCounter++;
            final stepTitle =
                RegExp(r'^bước\s*\d+', caseSensitive: false).hasMatch(text)
                ? text
                : 'Bước $stepCounter: $text';
            instructions.add('\n$stepTitle');
            continue;
          }
        }

        // Cơ chế dự phòng thông minh: Nếu đang ở phần nguyên liệu mà gặp đoạn văn bắt đầu bằng "Bước 1:" thì tự động chuyển sang Cách làm
        if (section == 'ingredients' &&
            tag == 'p' &&
            RegExp(r'^bước\s*1\b', caseSensitive: false).hasMatch(text)) {
          section = 'instructions';
        }

        // Thu thập dữ liệu
        if (section == 'ingredients' && tag == 'li') {
          if (!RegExp(r'^\d+\.\s').hasMatch(text)) {
            ingredients.add(text);
          }
        } else if (section == 'instructions' && (tag == 'p' || tag == 'li')) {
          if (!text.contains('Ảnh:') &&
              !text.startsWith('Xem thêm') &&
              !text.startsWith('XEM NGAY') &&
              !text.startsWith('Chúc bạn thực hiện thành công')) {
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
