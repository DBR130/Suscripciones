import 'package:flutter/material.dart';

import 'Common/AppTheme.dart';
import 'Common/Routers.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      debugShowCheckedModeBanner: false,
      title: 'SubTrack',
      theme: AppTheme.dark,
      routerConfig: Routers.router,
    );
  }
}
