import 'package:flutter/material.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '小学作业生成器',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: false,
        fontFamily: null,
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff2f6fd0)),
      ),
      home: const HomePage(),
    );
  }
}
