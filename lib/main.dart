import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'login_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: 'https://wsquzbpeovlzpizvsbxc.supabase.co',
    anonKey: 'sb_publishable_94vdrfB02IBiqlKXk8fStw_dUC2mPa5',

  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Locator',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: StreamBuilder<AuthState>(
        stream: Supabase.instance.client.auth.onAuthStateChange,
        builder: (context, snapshot) {
          final session = Supabase.instance.client.auth.currentSession;
          return session == null ? const LoginPage() : const MapPage();
        },
      ),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _client = Supabase.instance.client;
  final MapController _mapController = MapController();
  LatLng? _myLocation;
  final Map<String, LatLng> _others = {};
  String _status = 'Getting location...';
  StreamSubscription? _locationSub;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _getLocation(moveMap: true);
    _listenToOthers();
    // Re-send location every 10 seconds
    _timer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _getLocation(moveMap: false),
    );
  }

  @override
  void dispose() {
    _locationSub?.cancel();
    _timer?.cancel();
    super.dispose();
  }

  void _listenToOthers() {
    final myId = _client.auth.currentUser?.id;
    _locationSub = _client
        .from('locations')
        .stream(primaryKey: ['user_id'])
        .listen((rows) {
      if (!mounted) return;
      setState(() {
        _others.clear();
        for (final row in rows) {
          final id = row['user_id'] as String;
          if (id == myId) continue;
          _others[id] = LatLng(
            (row['lat'] as num).toDouble(),
            (row['lng'] as num).toDouble(),
          );
        }
      });
    });
  }

  Future<void> _getLocation({required bool moveMap}) async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _status = 'Location services are turned off.');
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        setState(() => _status = 'Location permission denied.');
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      final latLng = LatLng(position.latitude, position.longitude);
      setState(() {
        _myLocation = latLng;
        _status = 'Location found';
      });
      if (moveMap) _mapController.move(latLng, 16);

      final user = _client.auth.currentUser;
      if (user != null) {
        await _client.from('locations').upsert({
          'user_id': user.id,
          'lat': position.latitude,
          'lng': position.longitude,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        });
        if (mounted) setState(() => _status = 'Location saved');
      }
    } catch (e) {
      if (mounted) setState(() => _status = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Family Locator'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => _client.auth.signOut(),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: LatLng(3.1390, 101.6869),
              initialZoom: 12,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.family_locator',
              ),
              MarkerLayer(
                markers: [
                  // Other family members (blue)
                  for (final entry in _others.entries)
                    Marker(
                      point: entry.value,
                      width: 48,
                      height: 48,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.blue,
                        size: 48,
                      ),
                    ),
                  // Me (red)
                  if (_myLocation != null)
                    Marker(
                      point: _myLocation!,
                      width: 48,
                      height: 48,
                      child: const Icon(
                        Icons.location_pin,
                        color: Colors.red,
                        size: 48,
                      ),
                    ),
                ],
              ),
            ],
          ),
          Positioned(
            top: 12,
            left: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Text('$_status  •  Others online: ${_others.length}'),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _getLocation(moveMap: true),
        child: const Icon(Icons.my_location),
      ),
    );
  }
}