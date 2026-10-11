import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Family Locator',
      theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
      home: const MapPage(),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final MapController _mapController = MapController();
  LatLng? _myLocation;
  String _status = 'Getting location...';

  @override
  void initState() {
    super.initState();
    _getLocation();
  }

  Future<void> _getLocation() async {
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
      _mapController.move(latLng, 16);
    } catch (e) {
      setState(() => _status = 'Error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Family Locator')),
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
              if (_myLocation != null)
                MarkerLayer(
                  markers: [
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
                child: Text(_status),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _getLocation,
        child: const Icon(Icons.my_location),
      ),
    );
  }
}