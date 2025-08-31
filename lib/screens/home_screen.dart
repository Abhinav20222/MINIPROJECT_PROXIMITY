import 'package:flutter/material.dart';
import 'package:offgrid/screens/chat_screen.dart';
import 'package:offgrid/screens/settings_screen.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:app_settings/app_settings.dart';
import '../utils/app_state.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late AppState appState;
  
  final Map<String, String> _discoveredEndpoints = {};
  String? _connectedEndpointId;
  String? _connectedEndpointName;
  
  String? _connectingToEndpointId;
  bool _isDiscovering = false;
  bool _isAdvertising = false;

  @override
  void initState() {
    super.initState();
    appState = Provider.of<AppState>(context, listen: false);
    _requestPermissions().then((_) => _checkServices());
    
    if (appState.nearbyService == null) {
      appState.initializeNearbyService();
    }
    _subscribeToServiceEvents();
  }

  Future<void> _requestPermissions() async {
    await [
      Permission.location,
      Permission.bluetoothScan,
      Permission.bluetoothAdvertise,
      Permission.bluetoothConnect,
      Permission.nearbyWifiDevices,
    ].request();
  }

  Future<void> _checkServices() async {
    if (await Permission.location.serviceStatus.isDisabled && mounted) {
      _showServiceDisabledDialog(
        'Services Disabled',
        'For offline chat to work, please enable Location, Wi-Fi, and Bluetooth in your phone\'s settings.',
        AppSettingsType.location,
      );
    }
  }

  void _showServiceDisabledDialog(String title, String content, AppSettingsType settingsType) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(title),
          content: Text(content),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Open Settings'),
              onPressed: () {
                AppSettings.openAppSettings(type: settingsType);
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _subscribeToServiceEvents() {
    appState.nearbyService?.onEndpointFound = (endpoint) {
      if (mounted) { setState(() { _discoveredEndpoints[endpoint['id']] = endpoint['name']; }); }
    };
    appState.nearbyService?.onEndpointLost = (endpointId) {
      if (mounted) { setState(() { _discoveredEndpoints.remove(endpointId); }); }
    };
    appState.nearbyService?.onConnectionResult = (result) {
      if (mounted) {
        setState(() {
          _isDiscovering = false;
          _isAdvertising = false;
          _connectingToEndpointId = null;
        });
        if (result['status'] == 'connected') {
          setState(() {
            _connectedEndpointId = result['endpointId'];
            _connectedEndpointName = result['endpointName']; 
            _discoveredEndpoints.clear();
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Connected to $_connectedEndpointName!')),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Connection failed: ${result['status']}')),
          );
        }
      }
    };
    appState.nearbyService?.onDisconnected = (endpointId) {
      if (mounted) {
        setState(() {
          _isDiscovering = false;
          _isAdvertising = false;
          _connectingToEndpointId = null;
          _connectedEndpointId = null;
          _connectedEndpointName = null;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Disconnected.')),
        );
      }
    };
  }

  @override
  void dispose() {
    appState.nearbyService?.onEndpointFound = null;
    appState.nearbyService?.onEndpointLost = null;
    appState.nearbyService?.onConnectionResult = null;
    appState.nearbyService?.onDisconnected = null;
    super.dispose();
  }

  Widget _buildOfflineUI(AppState appState) {
    final bool isBusy = _isDiscovering || _isAdvertising;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(8.0),
          child: Text("Your Name: ${appState.username}", style: const TextStyle(fontSize: 16)),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            ElevatedButton.icon(
              icon: const Icon(Icons.search),
              label: const Text('Discover'),
              onPressed: isBusy ? null : () {
                setState(() => _isDiscovering = true);
                appState.nearbyService?.startDiscovery(appState.username!);
              },
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.wifi_tethering),
              label: const Text('Advertise'),
              onPressed: isBusy ? null : () {
                setState(() => _isAdvertising = true);
                appState.nearbyService?.startAdvertising(appState.username!);
              },
            ),
          ],
        ),
        const Divider(),
        if (_connectedEndpointId != null)
          _buildConnectedView(appState)
        else
          _buildDiscoveryListView(appState),
      ],
    );
  }

  // --- THIS WIDGET HAS BEEN UPDATED ---
  Widget _buildConnectedView(AppState appState) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 50),
          Text('Connected to:', style: Theme.of(context).textTheme.headlineSmall),
          const SizedBox(height: 10),
          Text(_connectedEndpointName ?? 'Unknown', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 30),
          ElevatedButton(
            child: const Text('Go to Chat'),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChatScreen(
                    peerId: _connectedEndpointId!,
                    peerName: _connectedEndpointName!,
                  ),
                ),
              );
            },
          ),
           const SizedBox(height: 10),
          TextButton(
            child: const Text('Disconnect'),
            onPressed: () {
                // First, tell the service to disconnect from everyone.
                appState.nearbyService?.stopAllEndpoints();
                
                // Then, immediately update the UI without waiting for the callback.
                setState(() {
                  _isDiscovering = false;
                  _isAdvertising = false;
                  _connectingToEndpointId = null;
                  _connectedEndpointId = null;
                  _connectedEndpointName = null;
                  _discoveredEndpoints.clear(); // Also clear any leftover discovered devices
                });
            },
          )
        ],
      ),
    );
  }
  // ------------------------------------

  Widget _buildDiscoveryListView(AppState appState) {
    return Expanded(
      child: _discoveredEndpoints.isEmpty
          ? const Center(child: Text('No devices found yet.'))
          : ListView.builder(
              itemCount: _discoveredEndpoints.length,
              itemBuilder: (context, index) {
                final endpointId = _discoveredEndpoints.keys.elementAt(index);
                final endpointName = _discoveredEndpoints[endpointId];
                final bool isConnecting = _connectingToEndpointId == endpointId;

                return ListTile(
                  title: Text(endpointName ?? 'Unknown Device'),
                  subtitle: Text(endpointId),
                  trailing: isConnecting 
                    ? const CircularProgressIndicator() 
                    : const Icon(Icons.chevron_right),
                  onTap: _connectingToEndpointId != null ? null : () {
                    setState(() {
                      _connectingToEndpointId = endpointId;
                    });
                    appState.nearbyService?.connectToEndpoint(endpointId);
                  },
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = Provider.of<AppState>(context);
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('OffGrid'), 
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const SettingsScreen()),
              );
            },
          ),
        ],
      ),
      body: _buildOfflineUI(appState),
    );
  }
}