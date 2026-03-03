// lib/widgets/add_product_sheet.dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/category.dart';

typedef AddProductForm = ({
  String name,
  String? description,
  int? categoryId,
  Uint8List? imageBytes,
  String? imageName,
  String? variantName,
  double? variantPrice,
});

// ----------------- UNIVERSAL IMAGE PICKER (web + mobile + desktop) -----------------
Future<void> pickImageBytes({
  required void Function(Uint8List bytes, String name) onPicked,
}) async {
  final res = await FilePicker.platform.pickFiles(
    type: FileType.image,
    allowMultiple: false,
    withData: true,
    withReadStream: true,
  );
  if (res == null || res.files.isEmpty) return;

  final f = res.files.single;
  Uint8List? bytes = f.bytes;

  if (bytes == null && kIsWeb && f.readStream != null) {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in f.readStream!) {
      builder.add(chunk);
    }
    bytes = builder.takeBytes();
  }

  if (bytes == null && f.readStream != null) {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in f.readStream!) {
      builder.add(chunk);
    }
    bytes = builder.takeBytes();
  }

  if (bytes != null) onPicked(bytes, f.name);
}

// ================== Modern Bottom Sheet: Add Product ==================
Future<AddProductForm?> showAddProductSheet(
  BuildContext context, {
  required List<Category> cats,
  int? preselectedCatId,
  List<String> unitOptions = const ['ADET', 'GR', 'KG', 'BAĞ', 'DEMET', 'KASA'],
  Future<bool> Function(AddProductForm form)? onSubmit,
}) {
  final nameC = TextEditingController();
  final descC = TextEditingController();
  final vPriceC = TextEditingController();

  Uint8List? imgBytes;
  String? imgName;

  int? selCatId = preselectedCatId;
  String selUnit = unitOptions.first;
  bool saving = false;

  return showModalBottomSheet<AddProductForm>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (ctx) {
      final mq = MediaQuery.of(ctx);
      final cs = Theme.of(ctx).colorScheme;
      const borderC = Color(0xFFE6E8EF);
      InputDecoration fieldDecoration({
        String? label,
        String? hint,
        String? suffixText,
      }) {
        return InputDecoration(
          labelText: label,
          hintText: hint,
          suffixText: suffixText,
          isDense: true,
          filled: true,
          fillColor: Colors.white,
          labelStyle: const TextStyle(color: Colors.black87),
          hintStyle: const TextStyle(color: Colors.black87),
          prefixStyle: const TextStyle(color: Colors.black87),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderC),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: borderC),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: cs.primary, width: 1.8),
          ),
          floatingLabelStyle: TextStyle(
            color: cs.primary,
            fontWeight: FontWeight.w800,
          ),
        );
      }

      return Theme(
        data: Theme.of(ctx).copyWith(
          canvasColor: Colors.white,
          cardColor: Colors.white,
          dialogTheme: const DialogTheme(backgroundColor: Colors.white),
        ),
        child: Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 8,
            bottom: mq.viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (ctx, setS) {
              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Header
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Ürün Ekle',
                            style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.black,
                                ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Kapat',
                          onPressed:
                              saving ? null : () => Navigator.of(ctx).pop(null),
                          icon: const Icon(Icons.close, color: Colors.black87),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Form card
                    Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: borderC),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          children: [
                            TextField(
                              controller: nameC,
                              decoration: fieldDecoration(label: 'Ürün adı *'),
                              autofocus: true,
                              textInputAction: TextInputAction.next,
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<int?>(
                              value: selCatId,
                              isExpanded: true,
                              menuMaxHeight: 320,
                              dropdownColor: Colors.white,
                              borderRadius: BorderRadius.circular(14),
                              icon: Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: cs.primary,
                              ),
                              decoration: fieldDecoration(
                                  label: 'Kategori (opsiyonel)'),
                              items: [
                                const DropdownMenuItem<int?>(
                                    value: null, child: Text('— Yok —')),
                                ...cats.map((c) => DropdownMenuItem<int?>(
                                    value: c.id, child: Text(c.name))),
                              ],
                              onChanged: (v) => setS(() => selCatId = v),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: descC,
                              decoration: fieldDecoration(label: 'Açıklama'),
                              maxLines: 3,
                            ),

                            const SizedBox(height: 12),

                            // Image row
                            Row(
                              children: [
                                FilledButton.icon(
                                  style: FilledButton.styleFrom(
                                      backgroundColor: cs.primary),
                                  onPressed: () async {
                                    try {
                                      await pickImageBytes(
                                        onPicked: (bytes, name) {
                                          setS(() {
                                            imgBytes = bytes;
                                            imgName = name;
                                          });
                                        },
                                      );
                                    } catch (_) {}
                                  },
                                  icon: const Icon(Icons.image),
                                  label: const Text('Resim Seç'),
                                ),
                                const SizedBox(width: 12),
                                if (imgName != null)
                                  Expanded(
                                    child: Row(
                                      children: [
                                        Expanded(
                                            child: Text(imgName!,
                                                overflow:
                                                    TextOverflow.ellipsis)),
                                        IconButton(
                                          tooltip: 'Kaldır',
                                          onPressed: () => setS(() {
                                            imgBytes = null;
                                            imgName = null;
                                          }),
                                          icon:
                                              const Icon(Icons.delete_outline),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),

                            const SizedBox(height: 12),

                            if (imgBytes != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: Image.memory(imgBytes!,
                                    height: 160,
                                    width: double.infinity,
                                    fit: BoxFit.cover),
                              ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Variant card
                    Card(
                      elevation: 0,
                      color: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: const BorderSide(color: borderC),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('İlk Varyant (opsiyonel)',
                                style: Theme.of(ctx).textTheme.titleSmall),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  flex: 2,
                                  child: DropdownButtonFormField<String>(
                                    value: selUnit,
                                    isExpanded: true,
                                    menuMaxHeight: 320,
                                    dropdownColor: Colors.white,
                                    borderRadius: BorderRadius.circular(14),
                                    icon: Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      color: cs.primary,
                                    ),
                                    decoration: fieldDecoration(label: 'Birim'),
                                    items: unitOptions
                                        .map((u) => DropdownMenuItem(
                                            value: u, child: Text(u)))
                                        .toList(),
                                    onChanged: (v) =>
                                        setS(() => selUnit = v ?? selUnit),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  flex: 3,
                                  child: TextField(
                                    controller: vPriceC,
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                            decimal: true),
                                    inputFormatters: [
                                      FilteringTextInputFormatter.allow(
                                          RegExp(r'[0-9.,]')),
                                    ],
                                    decoration: fieldDecoration(
                                      label: 'Başlangıç fiyatı (₺)',
                                      hint: 'opsiyonel',
                                      suffixText: '₺',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Actions
                    Row(
                      children: [
                        OutlinedButton(
                          onPressed:
                              saving ? null : () => Navigator.of(ctx).pop(null),
                          child: const Text('Vazgeç'),
                        ),
                        const Spacer(),
                        FilledButton.icon(
                          style: FilledButton.styleFrom(
                              backgroundColor: cs.primary),
                          onPressed: saving
                              ? null
                              : () async {
                                  final name = nameC.text.trim();
                                  if (name.isEmpty) {
                                    ScaffoldMessenger.of(ctx).showSnackBar(
                                      const SnackBar(
                                          content: Text('Ürün adı zorunludur')),
                                    );
                                    return;
                                  }
                                  final priceRaw = vPriceC.text.trim();
                                  final vPrice = priceRaw.isEmpty
                                      ? null
                                      : double.tryParse(
                                          priceRaw.replaceAll(',', '.'));

                                  final form = (
                                    name: name,
                                    description: descC.text.trim().isEmpty
                                        ? null
                                        : descC.text.trim(),
                                    categoryId: selCatId,
                                    imageBytes: imgBytes,
                                    imageName: imgName,
                                    variantName: selUnit,
                                    variantPrice: vPrice,
                                  );

                                  if (onSubmit == null) {
                                    Navigator.of(ctx).pop(form);
                                    return;
                                  }

                                  setS(() => saving = true);
                                  final ok = await onSubmit(form);
                                  if (!ctx.mounted) return;
                                  if (ok) {
                                    Navigator.of(ctx).pop(form);
                                  } else {
                                    setS(() => saving = false);
                                  }
                                },
                          icon: const Icon(Icons.save),
                          label: saving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Text('Kaydet'),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    },
  ).then((value) {
    nameC.dispose();
    descC.dispose();
    vPriceC.dispose();
    return value;
  });
}
