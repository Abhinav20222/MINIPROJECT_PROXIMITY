// lib/main.dart
import 'package:flutter/material.dart';
import 'package:offgrid/screens/permission_check_screen.dart'; // <-- Changed the import
import 'package:provider/provider.dart';
import 'utils/app_state.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AppState(),
      child: MaterialApp(
        title: 'OffGrid',
        theme: ThemeData.dark(),
        // --- This line has been changed ---
        home: const PermissionCheckScreen(),
        // --------------------------------
      ),
    );
  }
}