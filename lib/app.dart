import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:haldeki_tedarikci_web/theme/brand_theme.dart';

import 'router.dart';

class HaldekiApp extends StatelessWidget {
  const HaldekiApp({super.key});

  @override
  Widget build(BuildContext context) {
    final router = AppRouter.build();
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'Haldeki Tedarikci',
      theme: lightTheme(),
      darkTheme: darkTheme(),
      themeMode: ThemeMode.light,
      routerConfig: router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('tr'), Locale('en')],
      locale: const Locale('tr'),
    );
  }
}
