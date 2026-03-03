
class ProductDto {
  final int id;
  final String name;
  final bool active;

  ProductDto({required this.id, required this.name, required this.active});

  factory ProductDto.fromJson(Map<String, dynamic> j) => ProductDto(
        id: j['id'] as int,
        name: j['name'] as String? ?? '-',
        active: (j['active'] == true || j['active'] == 1),
      );
}

class VariantDto {
  final int id;
  final String name;
  final bool active;

  VariantDto({required this.id, required this.name, required this.active});

  factory VariantDto.fromJson(Map<String, dynamic> j) => VariantDto(
        id: j['id'] as int,
        name: j['name'] as String? ?? '-',
        active: (j['active'] == true || j['active'] == 1),
      );
}

class PriceDto {
  final int id;
  final double price;
  final bool active;

  PriceDto({required this.id, required this.price, required this.active});

  factory PriceDto.fromJson(Map<String, dynamic> j) => PriceDto(
        id: j['id'] as int,
        price: (j['price'] is num) ? (j['price'] as num).toDouble() : double.tryParse(j['price'].toString()) ?? 0,
        active: (j['active'] == true || j['active'] == 1),
      );
}
