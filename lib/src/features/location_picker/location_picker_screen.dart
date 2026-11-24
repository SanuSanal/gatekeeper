import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../platform/gatekeeper_platform.dart';
import '../../settings/validators.dart';

/// Pick the parking spot: tap the map, use the current location, or type coordinates.
/// Map tiles come from OpenStreetMap (network access only while this screen is open).
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    required this.platform,
    this.initial,
    required this.radiusMeters,
  });

  final GateKeeperPlatform platform;
  final LatLng? initial;
  final int radiusMeters;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  final _map = MapController();
  final _form = GlobalKey<FormState>();
  late final TextEditingController _lat;
  late final TextEditingController _lng;
  LatLng? _point;
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _point = widget.initial;
    _lat = TextEditingController(text: _point?.latitude.toStringAsFixed(6) ?? '');
    _lng = TextEditingController(text: _point?.longitude.toStringAsFixed(6) ?? '');
    if (_point == null) WidgetsBinding.instance.addPostFrameCallback((_) => _useCurrent());
  }

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  void _set(LatLng p, {bool move = false}) {
    setState(() => _point = p);
    _lat.text = p.latitude.toStringAsFixed(6);
    _lng.text = p.longitude.toStringAsFixed(6);
    if (move) _map.move(p, 17);
  }

  Future<void> _useCurrent() async {
    setState(() => _locating = true);
    try {
      final loc = await widget.platform.getCurrentLocation();
      if (!mounted) return;
      if (loc == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Current location unavailable')));
      } else {
        _set(LatLng(loc.latitude, loc.longitude), move: true);
        final acc = loc.accuracyMeters;
        if (acc != null) {
          ScaffoldMessenger.of(context)
              .showSnackBar(SnackBar(content: Text('Location accuracy ±${acc.round()} m')));
        }
      }
    } on PlatformException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message ?? 'Location error')));
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _applyTyped() {
    if (!_form.currentState!.validate()) return;
    _set(LatLng(double.parse(_lat.text.trim()), double.parse(_lng.text.trim())), move: true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final p = _point;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Parking location'),
        actions: [
          TextButton(
            onPressed: p == null ? null : () => Navigator.pop(context, p),
            child: const Text('Save'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: FlutterMap(
              mapController: _map,
              options: MapOptions(
                initialCenter: p ?? const LatLng(20, 0),
                initialZoom: p == null ? 2 : 17,
                onTap: (_, latLng) => _set(latLng),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.gatekeeper.app',
                ),
                if (p != null)
                  CircleLayer(
                    circles: [
                      CircleMarker(
                        point: p,
                        radius: widget.radiusMeters.toDouble(),
                        useRadiusInMeter: true,
                        color: scheme.primary.withValues(alpha: 0.18),
                        borderColor: scheme.primary,
                        borderStrokeWidth: 2,
                      ),
                    ],
                  ),
                if (p != null)
                  MarkerLayer(
                    markers: [
                      Marker(
                        point: p,
                        width: 40,
                        height: 40,
                        alignment: Alignment.topCenter,
                        child: Icon(Icons.location_on, size: 40, color: scheme.primary),
                      ),
                    ],
                  ),
                const RichAttributionWidget(
                  attributions: [TextSourceAttribution('OpenStreetMap contributors')],
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Form(
                key: _form,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Tap the map to place your parking spot. Radius: ${widget.radiusMeters} m',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _lat,
                            decoration: const InputDecoration(labelText: 'Latitude', isDense: true),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            validator: Validators.latitude,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextFormField(
                            controller: _lng,
                            decoration: const InputDecoration(labelText: 'Longitude', isDense: true),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                            validator: Validators.longitude,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Apply coordinates',
                          onPressed: _applyTyped,
                          icon: const Icon(Icons.check_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _locating ? null : _useCurrent,
                        icon: _locating
                            ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.my_location_rounded),
                        label: const Text('Use my current location'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
