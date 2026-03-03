// lib/router.dart
import 'package:go_router/go_router.dart';
import 'package:haldeki_tedarikci_web/screens/price_list_screen.dart';
import 'package:haldeki_tedarikci_web/screens/supplier_profile_screen.dart';

import 'screens/login_screen.dart';
import 'screens/shell.dart';
import 'screens/dashboard_screen.dart';
import 'screens/market_screen.dart';
import 'screens/orders_screen.dart';
import 'screens/order_detail_screen.dart';

class AppRouter {
  static GoRouter build() {
    return GoRouter(
      initialLocation: '/login',
      routes: [
        GoRoute(
          path: '/login',
          builder: (context, state) => const LoginScreen(),
        ),
        ShellRoute(
          builder: (context, state, child) {
            final loc = state.uri.path;
            final index = _navIndexFor(loc);
            return ShellScaffold(currentIndex: index, child: child);
          },
          routes: [
            GoRoute(
                path: '/dashboard',
                builder: (_, __) => const DashboardScreen()),
            GoRoute(path: '/market', builder: (_, __) => const MarketScreen()),
            GoRoute(
              path: '/cart',
              builder: (_, __) => const PriceListScreen(), // ✅ const YOK
            ),
            GoRoute(
              path: '/orders',
              builder: (_, __) => const OrdersScreen(),
              routes: [
                GoRoute(
                  path: ':orderNumber',
                  builder: (_, state) => OrderDetailScreen(
                    orderNumber: state.pathParameters['orderNumber']!,
                  ),
                ),
              ],
            ),
            // ✅ Suppliers
            GoRoute(
              path: '/profile',
              builder: (_, state) => const DealerProfileScreen(),
            ),
          ],
        ),
      ],
    );
  }

  // ✅ suppliers index=4
  static int _navIndexFor(String loc) {
    if (loc == '/dashboard') return 0;
    if (loc == '/market') return 1;
    if (loc == '/cart') return 2;
    if (loc == '/orders' || loc.startsWith('/orders/')) return 3;
    if (loc == '/profile') return 4;
    return 0;
  }
}
