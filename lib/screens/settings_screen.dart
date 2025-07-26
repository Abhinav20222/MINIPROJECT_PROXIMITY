import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../utils/app_state.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  _SettingsScreenState createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _usernameController;

  @override
  void initState() {
    super.initState();
    final appState = Provider.of<AppState>(context, listen: false);
    _usernameController = TextEditingController(text: appState.username);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);

    return Scaffold(
      appBar: AppBar(
        title: Text('Settings'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _usernameController,
              decoration: InputDecoration(
                labelText: 'Your Username',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (value) {
                appState.setUsername(value);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Username updated!')),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}