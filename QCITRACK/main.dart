import 'dart:io';

import 'package:flutter/material.dart';

import 'auth/login_page.dart';
import 'core/http_override.dart';        

void main() {
  HttpOverrides.global = MyHttpOverrides();   // <-- SSL BYPASS ENABLED
  runApp(const QCITrackApp());
}

class QCITrackApp extends StatelessWidget {
  const QCITrackApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QCITrack',
      debugShowCheckedModeBanner: false,
      home: const LoginPage(),
    );
  }
}
