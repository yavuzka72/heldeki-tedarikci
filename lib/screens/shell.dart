import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../models/cart.dart';
import '../services/api_client.dart';

/// =====================================================
///  NET WHITE THEME (EsnafExpress gibi)
/// =====================================================
class KSide {
  static const accent = Color(0xFF062F22); // koyu karthaldaki green

  static const bg = Color(0xFFFFFFFF);
  static const card = Color(0xFFFFFFFF);
  static const soft = Color(0xFFF8FAFC);
  static const line = Color(0xFFE6E8EF);

  static const text = Color(0xFF111827);
  static const muted = Color(0xFF6B7280);
}

class ShellScaffold extends StatelessWidget {
  final Widget child;
  final int currentIndex;

  const ShellScaffold({
    super.key,
    required this.child,
    required this.currentIndex,
  });

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isWide = width >= 1000;

    // Sepet
    final cart = context.watch<Cart>();
    final lineCount = cart.lines;
    final hasItems = lineCount > 0;

    // 🔹 Oturum bilgisi (tedarikçi / bayi)
    final api = context.watch<ApiClient>(); // ✅ singleton/provider üzerinden
    final session = api.session;

    final supplierName = (session?.name ?? 'Misafir');
    final supplierEmail = (session?.email ?? '');

    final city = (session?.city ?? '').trim();
    final district = (session?.district ?? '').trim();
    final address = (session?.adress ?? '').trim();

    final addrParts = <String>[
      if (city.isNotEmpty) city,
      if (district.isNotEmpty) district,
      if (address.isNotEmpty) address,
    ];
    final supplierAddress = addrParts.isEmpty
        ? ''
        : addrParts.join(' / '); // İSTANBUL / PENDİK / ...

    return Scaffold(
      backgroundColor: KSide.bg,
      body: Column(
        children: [
          // ---------- ÜST BAR ----------
          _TopBar(
            supplierName: supplierName,
            supplierEmail: supplierEmail,
            onLogout: () async {
              try {
                await api.logout();
              } catch (_) {}
              if (context.mounted) context.go('/login');
            },
          ),

          // ---------- ORTA ALAN (sol menü + içerik) ----------
          Expanded(
            child: Row(
              children: [
                if (isWide)
                  _WhiteRail(
                    currentIndex: currentIndex,
                    lineCount: lineCount,
                    hasItems: hasItems,
                    onSelected: (i) {
                      switch (i) {
                        case 0:
                          context.go('/dashboard');
                          break;
                        case 1:
                          context.go('/market');
                          break;
                        case 2:
                          context.go('/cart');
                          break;
                        case 3:
                          context.go('/orders');
                          break;
                        case 4:
                          context.go('/profile');
                          break;
                      }
                    },
                  ),
                if (isWide)
                  const VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: KSide.line,
                  ),
                Expanded(
                  child: Container(
                    color: KSide.bg,
                    child: child,
                  ),
                ),
              ],
            ),
          ),

          // ---------- ALT BARLAR ----------
          if (isWide) ...[
            _BottomInfoBar(
              supplierName: supplierName,
              supplierAddress: supplierAddress,
            ),
          ] else ...[
            _BottomInfoBar(
              supplierName: supplierName,
              supplierAddress: supplierAddress,
            ),
            _BottomNav(
              currentIndex: currentIndex,
              lineCount: lineCount,
              hasItems: hasItems,
              onSelected: (i) {
                switch (i) {
                  case 0:
                    context.go('/dashboard');
                    break;
                  case 1:
                    context.go('/market');
                    break;
                  case 2:
                    context.go('/cart');
                    break;
                  case 3:
                    context.go('/orders');
                    break;
                  case 4:
                    context.go('/profile');
                    break;
                }
              },
            ),
          ],
        ],
      ),
    );
  }
}

/// =====================================================
///  LEFT NAVIGATION RAIL (NET WHITE)
/// =====================================================
class _WhiteRail extends StatelessWidget {
  final int currentIndex;
  final int lineCount;
  final bool hasItems;
  final ValueChanged<int> onSelected;

  const _WhiteRail({
    required this.currentIndex,
    required this.lineCount,
    required this.hasItems,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        navigationRailTheme: const NavigationRailThemeData(
          backgroundColor: KSide.card,
          elevation: 0,
        ),
        iconTheme: const IconThemeData(color: KSide.muted),
      ),
      child: NavigationRail(
        backgroundColor: KSide.card,
        labelType: NavigationRailLabelType.all,
        minWidth: 92,
        useIndicator: true,
        indicatorColor: KSide.accent.withOpacity(.10),
        indicatorShape: const StadiumBorder(),
        groupAlignment: -1.0,
        selectedIndex: currentIndex.clamp(0, 4),
        selectedIconTheme: const IconThemeData(
          color: KSide.accent,
          size: 22,
        ),
        unselectedIconTheme: const IconThemeData(
          color: KSide.muted,
          size: 22,
        ),
        selectedLabelTextStyle: const TextStyle(
          color: KSide.accent,
          fontWeight: FontWeight.w800,
        ),
        unselectedLabelTextStyle: const TextStyle(
          color: KSide.muted,
          fontWeight: FontWeight.w700,
        ),
        leading: const _RailHeader(title: 'Haldeki Tedarikçi'),
        destinations: [
          const NavigationRailDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: Text('Ana Sayfa'),
          ),
          const NavigationRailDestination(
            icon: Icon(Icons.store_mall_directory_outlined),
            selectedIcon: Icon(Icons.store_mall_directory),
            label: Text('Ürünler'),
          ),
          NavigationRailDestination(
            icon: _BadgeIcon(
              count: lineCount,
              child: Icon(
                Icons.price_change_rounded,
                color: hasItems ? KSide.accent : null,
                size: 22,
              ),
            ),
            selectedIcon: _BadgeIcon(
              count: lineCount,
              child: Icon(
                Icons.price_change_rounded,
                color: hasItems ? KSide.accent : null,
                size: 22,
              ),
            ),
            label: const Text('Fiyat Listesi'),
          ),
          const NavigationRailDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: Text('Gelen Siparişler'),
          ),
          const NavigationRailDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: Text('Profil'),
          ),
        ],
        onDestinationSelected: onSelected,
      ),
    );
  }
}

/// =====================================================
///  TOP BAR (NET WHITE)
/// =====================================================
class _TopBar extends StatelessWidget {
  final String supplierName;
  final String supplierEmail;
  final VoidCallback onLogout;

  const _TopBar({
    required this.supplierName,
    required this.supplierEmail,
    required this.onLogout,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: KSide.card,
        border: Border(
          bottom: BorderSide(color: KSide.line),
        ),
      ),
      child: Row(
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: KSide.accent.withOpacity(.10),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: KSide.line),
                ),
                alignment: Alignment.center,
                child:
                    const Icon(Icons.storefront, size: 18, color: KSide.accent),
              ),
              const SizedBox(width: 10),
              const Text(
                'Haldeki Tedarikçi',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: KSide.text,
                ),
              ),
            ],
          ),
          const Spacer(),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                supplierName,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13.5,
                  color: KSide.text,
                ),
              ),
              if (supplierEmail.isNotEmpty)
                Text(
                  supplierEmail,
                  style: const TextStyle(
                    fontSize: 12,
                    color: KSide.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: KSide.accent.withOpacity(.10),
              foregroundColor: KSide.text,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: KSide.accent.withOpacity(.22)),
              ),
            ),
            onPressed: onLogout,
            icon: const Icon(Icons.logout, size: 18, color: KSide.accent),
            label: const Text(
              'Çıkış',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ],
      ),
    );
  }
}

/// =====================================================
///  BOTTOM INFO BAR (NET WHITE)
/// =====================================================
class _BottomInfoBar extends StatelessWidget {
  final String supplierName;
  final String supplierAddress;

  const _BottomInfoBar({
    required this.supplierName,
    required this.supplierAddress,
  });

  @override
  Widget build(BuildContext context) {
    final text = supplierAddress.isEmpty
        ? supplierName
        : '$supplierName — $supplierAddress';

    return Container(
      height: 28,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: const BoxDecoration(
        color: KSide.card,
        border: Border(
          top: BorderSide(color: KSide.line),
        ),
      ),
      alignment: Alignment.centerLeft,
      child: Row(
        children: [
          const Icon(Icons.verified_user, size: 16, color: KSide.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12,
                color: KSide.text,
                fontWeight: FontWeight.w700,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

/// =====================================================
///  MOBILE BOTTOM NAV
/// =====================================================
class _BottomNav extends StatelessWidget {
  final int currentIndex;
  final int lineCount;
  final bool hasItems;
  final ValueChanged<int> onSelected;

  const _BottomNav({
    required this.currentIndex,
    required this.lineCount,
    required this.hasItems,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: KSide.card,
          indicatorColor: KSide.accent.withOpacity(.10),
          labelTextStyle: WidgetStateProperty.all(
            const TextStyle(
              fontWeight: FontWeight.w800,
              color: KSide.text,
            ),
          ),
        ),
      ),
      child: NavigationBar(
        selectedIndex: currentIndex.clamp(0, 4),
        onDestinationSelected: onSelected,
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard),
            label: 'Dashboard',
          ),
          const NavigationDestination(
            icon: Icon(Icons.store_mall_directory_outlined),
            selectedIcon: Icon(Icons.store_mall_directory),
            label: 'Market',
          ),
          NavigationDestination(
            icon: _BadgeIcon(
              count: lineCount,
              child: Icon(
                Icons.price_change_outlined,
                color: hasItems ? KSide.accent : null,
                size: 22,
              ),
            ),
            selectedIcon: _BadgeIcon(
              count: lineCount,
              child: Icon(
                Icons.price_change,
                color: hasItems ? KSide.accent : null,
                size: 22,
              ),
            ),
            label: 'Fiyatlar',
          ),
          const NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long),
            label: 'Siparişler',
          ),
          const NavigationDestination(
            icon: Icon(Icons.account_circle_outlined),
            selectedIcon: Icon(Icons.account_circle),
            label: 'Profil',
          ),
        ],
      ),
    );
  }
}

/// =====================================================
///  RAIL HEADER
/// =====================================================
class _RailHeader extends StatelessWidget {
  const _RailHeader({required this.title, this.logoAsset});
  final String title;
  final String? logoAsset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      child: Column(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: KSide.accent.withOpacity(.10),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: KSide.line),
            ),
            alignment: Alignment.center,
            child: logoAsset == null
                ? const Icon(Icons.apps, color: KSide.accent, size: 20)
                : ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: Image.asset(
                      logoAsset!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    ),
                  ),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: KSide.text,
              fontWeight: FontWeight.w900,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// =====================================================
///  BADGE ICON (NET WHITE + MOR)
/// =====================================================
class _BadgeIcon extends StatelessWidget {
  final int count;
  final Widget child;
  const _BadgeIcon({required this.count, required this.child});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return child;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        child,
        Positioned(
          right: -7,
          top: -6,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: KSide.accent,
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  blurRadius: 14,
                  color: KSide.accent.withOpacity(.25),
                ),
              ],
            ),
            constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
            child: Text(
              count > 99 ? '99+' : '$count',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 10,
                fontWeight: FontWeight.w900,
                height: 1.2,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
