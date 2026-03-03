// lib/main.dart
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';
import 'models/cart.dart'; // <-- Cart için
import 'services/api_client.dart';

Future<void> _bootstrap() async {
  WidgetsFlutterBinding.ensureInitialized();

  Intl.defaultLocale = 'tr_TR';
  await initializeDateFormatting('tr_TR', null);

  try {
    setUrlStrategy(PathUrlStrategy());
  } catch (_) {}

  final api = ApiClient();
  await api.init();

  runApp(
    MultiProvider(
      providers: [
        Provider<ApiClient>.value(value: api),
        ChangeNotifierProvider<Cart>.value(value: Cart.I),
      ],
      child: const HaldekiApp(),
    ),
  );
}

void main() {
  runZonedGuarded(() async {
    await _bootstrap();
  }, (error, stack) {
    FlutterError.reportError(
      FlutterErrorDetails(exception: error, stack: stack),
    );
  });
}
