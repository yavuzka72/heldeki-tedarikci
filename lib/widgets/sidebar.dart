import 'package:flutter/material.dart';

class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.currentRoute,
    required this.onNavigate,
    this.appTitle = 'Haldeki Tedarikçi',
    this.logoAsset,
  });

  final String currentRoute;
  final ValueChanged<String> onNavigate;
  final String appTitle;
  final String? logoAsset;

  bool _isActive(String route) => currentRoute == route;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 270,
      decoration: const BoxDecoration(
        color: KSideColors.bg, // ✅ düz beyaz
        border: Border(
          right: BorderSide(color: KSideColors.line),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _header(context),
            const SizedBox(height: 8),
            Expanded(
              child: Scrollbar(
                thumbVisibility: true,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
                  children: [
                    _sectionLabel('GENEL'),
                    _tile(
                      context,
                      icon: Icons.arrow_back,
                      label: 'Siteyi Görüntüle',
                      onTap: () => onNavigate('/'),
                      active: _isActive('/'),
                    ),
                    const SizedBox(height: 10),
                    _sectionLabel('HALDEKİ'),
                    _tile(
                      context,
                      icon: Icons.home_filled,
                      label: 'Ana Sayfa',
                      route: '/dashboard',
                    ),
                    _tile(
                      context,
                      icon: Icons.inventory_2_outlined,
                      label: 'Ürünler',
                      route: '/products',
                    ),
                    _tile(
                      context,
                      icon: Icons.receipt_long_outlined,
                      label: 'Fiyat Listesi',
                      route: '/price-list',
                    ),
                    _tile(
                      context,
                      icon: Icons.shopping_bag_outlined,
                      label: 'Gelen Siparişler',
                      route: '/orders',
                    ),
                    _tile(
                      context,
                      icon: Icons.person_outline,
                      label: 'Profil',
                      route: '/profile',
                    ),
                    const SizedBox(height: 10),
                    _sectionLabel('OPERASYON (OPSİYONEL)'),
                    _group(
                      context,
                      icon: Icons.receipt_long_outlined,
                      label: 'Sipariş',
                      children: [
                        _subtile(context, 'Tüm Siparişler', '/orders'),
                        _subtile(context, 'Bekleyen', '/orders/pending'),
                      ],
                    ),
                    _group(
                      context,
                      icon: Icons.speed_outlined,
                      label: 'Kurye',
                      children: [
                        _subtile(context, 'Aktif Kuryeler', '/couriers/active'),
                        _subtile(context, 'Talepler', '/couriers/requests'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            _footer(context),
          ],
        ),
      ),
    );
  }

  // ================= HEADER =================

  Widget _header(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KSideColors.card, // ✅ beyaz
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: KSideColors.line),
        ),
        child: Row(
          children: [
            _Logo(logoAsset: logoAsset),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    appTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: KSideColors.text,
                      fontWeight: FontWeight.w900,
                      fontSize: 14.5,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: const [
                      _Dot(),
                      SizedBox(width: 6),
                      Text(
                        'Panel',
                        style: TextStyle(
                          color: KSideColors.muted,
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: KSideColors.accent.withOpacity(.10),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: KSideColors.accent.withOpacity(.25)),
              ),
              child: const Text(
                'PRO',
                style: TextStyle(
                  color: KSideColors.accent,
                  fontWeight: FontWeight.w900,
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _footer(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: KSideColors.card, // ✅ beyaz
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: KSideColors.line),
        ),
        child: const Row(
          children: [
            Icon(Icons.lock_outline, color: KSideColors.muted, size: 18),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Güvenli oturum aktif',
                style: TextStyle(
                  color: KSideColors.muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ================= SECTION LABEL =================

  Widget _sectionLabel(String text) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
      child: Text(
        text,
        style: const TextStyle(
          color: KSideColors.muted,
          fontWeight: FontWeight.w900,
          letterSpacing: .8,
          fontSize: 11.5,
        ),
      ),
    );
  }

  // ================= TILE =================

  Widget _tile(
    BuildContext context, {
    required IconData icon,
    required String label,
    String? route,
    VoidCallback? onTap,
    bool? active,
  }) {
    final isSelected = active ?? (route != null && _isActive(route));
    final cb = onTap ?? (() => onNavigate(route ?? '/'));

    return _SideTile(
      icon: icon,
      label: label,
      selected: isSelected,
      onTap: cb,
    );
  }

  // ================= GROUP =================

  Widget _group(
    BuildContext context, {
    required IconData icon,
    required String label,
    required List<Widget> children,
  }) {
    final groupActive = children.any((w) {
      if (w is _SideSubTile) return _isActive(w.route);
      return false;
    });

    return Theme(
      data: Theme.of(context).copyWith(
        dividerColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        decoration: BoxDecoration(
          color: groupActive
              ? KSideColors.accent.withOpacity(.06)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: groupActive
                ? KSideColors.accent.withOpacity(.18)
                : Colors.transparent,
          ),
        ),
        child: ExpansionTile(
          initiallyExpanded: groupActive,
          leading: Icon(
            icon,
            color: groupActive ? KSideColors.accent : KSideColors.muted,
            size: 20,
          ),
          iconColor: KSideColors.accent,
          collapsedIconColor: KSideColors.muted,
          title: const Text(
            '', // placeholder
          ),
          tilePadding: const EdgeInsets.symmetric(horizontal: 12),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          collapsedShape: const RoundedRectangleBorder(),
          shape: const RoundedRectangleBorder(),
          children: children,
        ),
      ),
    );
  }

  Widget _subtile(BuildContext context, String label, String route) {
    return _SideSubTile(
      label: label,
      route: route,
      selected: _isActive(route),
      onTap: () => onNavigate(route),
    );
  }
}

// =====================================================
//  COLORS — NET, WHITE (LIME/GRADIENT YOK)
// =====================================================

class KSideColors {
  static const accent = Color(0xFF6e188a);

  static const bg = Color(0xFFFFFFFF);
  static const card = Color(0xFFFFFFFF);
  static const line = Color(0xFFE6E8F0);

  static const text = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
}

// =====================================================
//  UI PIECES
// =====================================================

class _SideTile extends StatefulWidget {
  const _SideTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SideTile> createState() => _SideTileState();
}

class _SideTileState extends State<_SideTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;

    final bg = selected
        ? KSideColors.accent.withOpacity(.10)
        : (_hover ? Colors.black.withOpacity(.03) : Colors.transparent);

    final border =
        selected ? KSideColors.accent.withOpacity(.22) : Colors.transparent;

    final iconColor = selected ? KSideColors.accent : KSideColors.muted;
    final textColor = selected ? KSideColors.accent : KSideColors.text;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 4,
                height: 18,
                decoration: BoxDecoration(
                  color: selected ? KSideColors.accent : Colors.transparent,
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              const SizedBox(width: 10),
              Icon(widget.icon, size: 20, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
              ),
              if (selected)
                const Icon(Icons.chevron_right,
                    size: 18, color: KSideColors.accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _SideSubTile extends StatefulWidget {
  const _SideSubTile({
    required this.label,
    required this.route,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final String route;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_SideSubTile> createState() => _SideSubTileState();
}

class _SideSubTileState extends State<_SideSubTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final selected = widget.selected;

    final bg = selected
        ? KSideColors.accent.withOpacity(.08)
        : (_hover ? Colors.black.withOpacity(.02) : Colors.transparent);

    final border =
        selected ? KSideColors.accent.withOpacity(.14) : Colors.transparent;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: border),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.circle,
                size: selected ? 14 : 6,
                color: selected ? KSideColors.accent : KSideColors.muted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: selected ? KSideColors.accent : KSideColors.muted,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Logo extends StatelessWidget {
  const _Logo({this.logoAsset});
  final String? logoAsset;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: KSideColors.accent.withOpacity(.10), // ✅ düz renk
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: KSideColors.line),
      ),
      alignment: Alignment.center,
      child: (logoAsset != null)
          ? ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.asset(
                logoAsset!,
                width: 44,
                height: 44,
                fit: BoxFit.cover,
              ),
            )
          : const Icon(Icons.apps, color: KSideColors.accent),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: KSideColors.accent,
        borderRadius: BorderRadius.circular(99),
      ),
    );
  }
}
