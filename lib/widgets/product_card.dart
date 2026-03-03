import 'package:flutter/material.dart';
import '../models/product.dart';
import '../models/variant.dart';
import '../utils/format.dart';

class ProductCard extends StatefulWidget {
  final Product product;
  final void Function(Product product, ProductVariant variant) onAdd;

  /// API base (local)
  final String baseUrl; // 👈 ekledik

  const ProductCard({
    super.key,
    required this.product,
    required this.onAdd,
    this.baseUrl = 'http://192.168.64.2', // 👈 default
  });

  @override
  State<ProductCard> createState() => _ProductCardState();
}

class _ProductCardState extends State<ProductCard> {
  ProductVariant? _selected;

  @override
  void initState() {
    super.initState();
    final v = widget.product.variants;
    _selected = v.isNotEmpty ? v.first : null;
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.product;
    final cs = Theme.of(context).colorScheme;
    final hasVariants = p.variants.isNotEmpty;

    return Card(
      elevation: .5,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: cs.surfaceVariant.withOpacity(.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                alignment: Alignment.center,
                child: _buildImage(p.image), // p.image path/URL/emoji olabilir
              ),
            ),
            const SizedBox(height: 8),
            Text(
              p.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            if (hasVariants && p.variants.length > 1)
              DropdownButtonFormField<ProductVariant>(
                value: _selected,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Varyant',
                  isDense: true,
                ),
                items: [
                  for (final v in p.variants)
                    DropdownMenuItem(
                      value: v,
                      child: Text('${v.name} • ${_priceLabel(v)}'),
                    ),
                ],
                onChanged: (v) => setState(() => _selected = v),
              )
            else if (hasVariants && p.variants.length == 1)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: cs.surfaceVariant.withOpacity(.35),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.category_outlined, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${p.variants.first.name} • ${_priceLabel(p.variants.first)}',
                      ),
                    ),
                  ],
                ),
              )
            else
              Text('Varyant yok', style: TextStyle(color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: (_selected == null)
                    ? null
                    : () => widget.onAdd(p, _selected!),
                icon: const Icon(Icons.add_shopping_cart),
                label: Text(
                  _selected == null
                      ? 'Stok yok'
                      : 'Sepete Ekle • ${_priceLabel(_selected!)}',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _priceLabel(ProductVariant v) {
    final unit = (v.unit.isEmpty) ? 'adet' : v.unit;
    return '${tl(v.price)} / $unit';
  }

  Widget _buildImage(String value) {
    final s = value.trim();
    if (s.isEmpty) {
      return const Text('🛒', style: TextStyle(fontSize: 42));
    }

    // 1) Zaten tam URL ise (http/https)
    if (s.startsWith('http://') || s.startsWith('https://')) {
      return _netImg(s);
    }

    // 2) Relative path ise (products/...png) => /storage/products/...png
    final looksLikeFile = s.contains('/') &&
        (s.endsWith('.png') ||
            s.endsWith('.jpg') ||
            s.endsWith('.jpeg') ||
            s.endsWith('.webp'));

    if (looksLikeFile) {
      final url =
          '${widget.baseUrl}/storage/${s.startsWith('/') ? s.substring(1) : s}';
      return _netImg(url);
    }

    // 3) Emoji / text fallback
    return Text(s, style: const TextStyle(fontSize: 42));
  }

  Widget _netImg(String url) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Image.network(
        url,
        width: 72,
        height: 72,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) =>
            const Icon(Icons.broken_image_outlined, size: 42),
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        },
      ),
    );
  }
}
