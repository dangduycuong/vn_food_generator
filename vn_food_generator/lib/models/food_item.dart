class FoodItem {
  final String id;
  final String name;
  final String category;
  final String area;
  final String thumb;
  final List<String> ingredients;
  final String instructions;

  FoodItem({
    required this.id,
    required this.name,
    required this.category,
    required this.area,
    required this.thumb,
    required this.ingredients,
    required this.instructions,
  });

  factory FoodItem.fromJson(Map<String, dynamic> json) {
    return FoodItem(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      category: json['category']?.toString() ?? 'Món Nước',
      area: json['area']?.toString() ?? 'Hà Nội',
      thumb: json['thumb']?.toString() ?? '',
      ingredients: List<String>.from(json['ingredients'] ?? []),
      instructions: json['instructions']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'category': category,
    'area': area,
    'thumb': thumb,
    'ingredients': ingredients,
    'instructions': instructions,
  };

  static String slugify(String text) {
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
}
