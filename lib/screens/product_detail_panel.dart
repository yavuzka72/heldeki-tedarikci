import 'package:flutter/material.dart';

import 'package:haldeki_tedarikci_web/config.dart';
import 'package:haldeki_tedarikci_web/models/product.dart';
import 'package:haldeki_tedarikci_web/models/variant.dart';
import 'package:haldeki_tedarikci_web/screens/market_controller.dart';

class ProductDetailPanel extends StatelessWidget {
  final MarketController c;

  const ProductDetailPanel({super.key, required this.c});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final p = c.selectedProduct;

    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(.05),
            blurRadius: 18,
            offset: const Offset(0, 10),
          )
        ],
      ),
      child: p == null
          ? const _EmptyState(
              icon: Icons.touch_app_outlined,
              title: 'Ürün seç',
              subtitle: 'Soldan bir ürün seçince detayları burada göreceksin.',
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Ürün Detayı',
                          style: TextStyle(
                            color: cs.onSurface,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Kapat',
                        onPressed: () {
                          c.selectedProduct = null;
                          c.notifyListeners();
                        },
                        icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _imageBlock(context, cs, p),
                        const SizedBox(height: 12),
                        Text(
                          p.name,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Varyant fiyatlarını düzenle',
                          style: TextStyle(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 12),
                        if (c.isLoadingVariants(p)) ...[
                          Row(
                            children: const [
                              SizedBox(
                                width: 18,
                                height: 18,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                              SizedBox(width: 10),
                              Text('Varyantlar / fiyatlar yükleniyor…'),
                            ],
                          ),
                          const SizedBox(height: 12),
                        ],
                        ...c
                            .variantsFor(p)
                            .map((v) => _variantRow(context, cs, p, v)),
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: FilledButton.icon(
                      icon: const Icon(Icons.save),
                      label: Text(
                        c.dirtyPrices.isEmpty
                            ? 'Hepsini Kaydet'
                            : 'Hepsini Kaydet (${c.dirtyPrices.length})',
                      ),
                      onPressed: c.dirtyPrices.isEmpty
                          ? null
                          : () => c.saveAllDirty(
                                messenger: ScaffoldMessenger.of(context),
                              ),
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _imageBlock(BuildContext context, ColorScheme cs, Product p) {
    final img = (p.image ?? '').toString();
    final imageUrl = img.startsWith('http') ? img : AppConfig.imageUrl(img);

    return Column(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: AspectRatio(
            aspectRatio: 4 / 3,
            child: Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                color: cs.surfaceVariant.withOpacity(.6),
                child: Icon(Icons.image_not_supported_outlined,
                    color: cs.onSurfaceVariant),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: cs.surfaceVariant.withOpacity(.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Resim yükle',
                      style: TextStyle(
                          color: cs.onSurface, fontWeight: FontWeight.w900),
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: c.uploadingDetailImage
                        ? null
                        : () => c.pickAndUploadDetailImage(
                              messenger: ScaffoldMessenger.of(context),
                            ),
                    icon: c.uploadingDetailImage
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.image_outlined),
                    label: Text(c.uploadingDetailImage
                        ? 'Yükleniyor'
                        : 'Resim Güncelle'),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (c.detailImageBytes == null)
                Text(
                  'Ürün için fotoğraf ekleyebilirsin.',
                  style: TextStyle(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        width: 64,
                        height: 64,
                        child: Image.memory(c.detailImageBytes!,
                            fit: BoxFit.cover),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            c.detailImageName ?? 'Seçilen resim',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: cs.onSurface,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            c.uploadingDetailImage ? 'Yükleniyor…' : 'Seçildi',
                            style: TextStyle(
                              color: c.uploadingDetailImage
                                  ? cs.primary
                                  : cs.onSurfaceVariant,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Kaldır',
                      onPressed: c.clearDetailImage,
                      icon: Icon(Icons.close, color: cs.onSurfaceVariant),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _variantRow(
      BuildContext context, ColorScheme cs, Product p, ProductVariant v) {
    final controller = c.pc(v.id, v.price);
    final isDirty = c.dirtyPrices.containsKey(v.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surfaceVariant.withOpacity(.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  v.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: cs.onSurface, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
              ],
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 130,
            child: TextField(
              controller: controller,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                isDense: true,
                prefixText: '₺ ',
                suffixIcon: isDirty
                    ? Icon(Icons.circle, size: 10, color: cs.primary)
                    : null,
              ),
              onChanged: (txt) {
                final val = c.tryParsePrice(txt);
                if (val == null) return;
                c.dirtyPrices[v.id] = val;
                c.notifyListeners();
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _EmptyState(
      {required this.icon, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(18.0),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 46, color: cs.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              title,
              style:
                  TextStyle(color: cs.onSurface, fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(
                  color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
