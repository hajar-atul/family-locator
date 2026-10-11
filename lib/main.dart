import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'family_page.dart';
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
          final user = Supabase.instance.client.auth.currentUser;
          return user == null
              ? const LoginPage()
              : FamilyGate(key: ValueKey(user.id));
        },
      ),
    );
  }
}

/// Decides whether to show the family setup or the map.
class FamilyGate extends StatefulWidget {
  const FamilyGate({super.key});

  @override
  State<FamilyGate> createState() => _FamilyGateState();
}

class _FamilyGateState extends State<FamilyGate> {
  late Future<Map<String, dynamic>?> _future = _load();

  Future<Map<String, dynamic>?> _load() async {
    final client = Supabase.instance.client;
    final rows = await client
        .from('family_members')
        .select('families(id, name, invite_code)')
        .eq('user_id', client.auth.currentUser!.id)
        .limit(1);
    if (rows.isEmpty) return null;
    return rows.first['families'] as Map<String, dynamic>;
  }

  void _reload() => setState(() => _future = _load());

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>?>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasError) {
          return Scaffold(
              body: Center(child: Text('Error: ${snapshot.error}')));
        }
        final family = snapshot.data;
        if (family == null) return FamilyPage(onDone: _reload);
        return MapPage(
          familyName: family['name'] as String,
          inviteCode: family['invite_code'] as String,
        );
      },
    );
  }
}

class MapPage extends StatefulWidget {
  final String familyName;
  final String inviteCode;
  const MapPage({
    super.key,
    required this.familyName,
    required this.inviteCode,
  });

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final _client = Supabase.instance.client;
  final MapController _mapController = MapController();
  LatLng? _myLocation;
  final Map<String, LatLng> _others = {};
  final Map<String, String> _names = {};
  String _status = 'Getting location...';
  StreamSubscription? _locationSub;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _loadNames();
    _getLocation(moveMap: true);
    _listenToOthers();
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

  Future<void> _loadNames() async {
    final rows =
        await _client.from('family_members').select('user_id, display_name');
    if (!mounted) return;
    setState(() {
      for (final r in rows) {
        _names[r['user_id'] as String] = r['display_name'] as String;
      }
    });
  }

  void _listenToOthers() {
    final myId = _client.auth.currentUser?.id;
    _locationSub =
        _client.from('locations').stream(primaryKey: ['user_id']).listen((rows) {
      if (!mounted) return;
      var unknown = false;
      setState(() {
        _others.clear();
        for (final row in rows) {
          final id = row['user_id'] as String;
          if (id == myId) continue;
          if (!_names.containsKey(id)) unknown = true;
          _others[id] = LatLng(
            (row['lat'] as num).toDouble(),
            (row['lng'] as num).toDouble(),
          );
        }
      });
      if (unknown) _loadNames();
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

  Marker _marker(LatLng point, String label, Color color) {
    return Marker(
      point: point,
      width: 100,
      height: 70,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(label,
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),
          Icon(Icons.location_pin, color: color, size: 40),
        ],
      ),
    );
  }

  void _showFamilyInfo() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(widget.familyName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Invite code:'),
            SelectableText(
              widget.inviteCode,
              style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            const Text('Members:'),
            for (final name in _names.values) Text('• $name'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final myId = _client.auth.currentUser?.id;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.familyName),
        actions: [
          IconButton(
            icon: const Icon(Icons.group),
            onPressed: _showFamilyInfo,
          ),
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
                  for (final e in _others.entries)
                    _marker(e.value, _names[e.key] ?? 'Family', Colors.blue),
                  if (_myLocation != null)
                    _marker(
                        _myLocation!, _names[myId] ?? 'Me', Colors.red),
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
                child: Text('$_status  •  Family online: ${_others.length}'),
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