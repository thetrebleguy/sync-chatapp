// main.dart
import 'package:flutter/material.dart';
import 'package:overlay_support/overlay_support.dart';
import 'screens/login_screen.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return OverlaySupport.global( // 2. Wrap your app here!
      child: MaterialApp(
        title: 'Hirewire',
        theme: ThemeData(primarySwatch: Colors.deepPurple),
        home: const LoginScreen(),
      ),
    );
  }
}
