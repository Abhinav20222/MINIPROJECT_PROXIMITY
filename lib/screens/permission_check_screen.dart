import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:app_settings/app_settings.dart';
import 'package:offgrid/screens/home_screen.dart';

class PermissionCheckScreen extends StatefulWidget {
  const PermissionCheckScreen({super.key});

  @override
  State<PermissionCheckScreen> createState() => _PermissionCheckScreenState();
}

class _PermissionCheckScreenState extends State<PermissionCheckScreen> with WidgetsBindingObserver {
  bool _isLocationEnabled = false;
  bool _isBluetoothEnabled = false;
  // We no longer need to track Wi-Fi state here, as the check is unreliable.

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkRequiredServices();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkRequiredServices();
    }
  }

  Future<void> _checkRequiredServices() async {
    final locationStatus = await Permission.location.serviceStatus.isEnabled;
    final bluetoothStatus = await Permission.bluetooth.serviceStatus.isEnabled;
    
    if (mounted) {
      setState(() {
        _isLocationEnabled = locationStatus;
        _isBluetoothEnabled = bluetoothStatus;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // The "NEXT" button now only depends on Location and Bluetooth
    final bool allRequiredEnabled = _isLocationEnabled && _isBluetoothEnabled;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Before you start'),
        automaticallyImplyLeading: false,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const Text(
              'Please enable the following services to use offline features.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 40),
            _buildServiceRow(
              icon: Icons.location_on,
              title: 'Location',
              subtitle: 'To discover nearby devices',
              isEnabled: _isLocationEnabled,
              onPressed: () => AppSettings.openAppSettings(type: AppSettingsType.location),
            ),
            const SizedBox(height: 20),
            // The Wi-Fi row is now just a helpful shortcut, not a requirement.
            _buildInfoRow(
              icon: Icons.wifi,
              title: 'Wi-Fi',
              subtitle: 'For connecting to other devices',
              onPressed: () => AppSettings.openAppSettings(type: AppSettingsType.wifi),
            ),
            const SizedBox(height: 20),
            _buildServiceRow(
              icon: Icons.bluetooth,
              title: 'Bluetooth',
              subtitle: 'For discovering nearby devices',
              isEnabled: _isBluetoothEnabled,
              onPressed: () => AppSettings.openAppSettings(type: AppSettingsType.bluetooth),
            ),
            const Spacer(),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(double.infinity, 50),
                backgroundColor: allRequiredEnabled ? Colors.blue : Colors.grey,
              ),
              onPressed: allRequiredEnabled 
                ? () {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(builder: (context) => const HomeScreen()),
                    );
                  }
                : null,
              child: const Text('NEXT', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // This widget is for required services (Location, Bluetooth)
  Widget _buildServiceRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool isEnabled,
    required VoidCallback onPressed,
  }) {
    return Row(
      children: [
        Icon(icon, size: 40, color: isEnabled ? Colors.green : Colors.grey),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(subtitle, style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
        if (!isEnabled)
          ElevatedButton(
            onPressed: onPressed,
            child: const Text('Enable'),
          ),
      ],
    );
  }

  // This new widget is for informational rows (Wi-Fi)
  Widget _buildInfoRow({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onPressed,
  }) {
    return Row(
      children: [
        Icon(icon, size: 40, color: Colors.grey),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text(subtitle, style: const TextStyle(color: Colors.grey)),
            ],
          ),
        ),
        // This button is always visible as a helpful shortcut
        ElevatedButton(
          onPressed: onPressed,
          child: const Text('Settings'),
        ),
      ],
    );
  }
}