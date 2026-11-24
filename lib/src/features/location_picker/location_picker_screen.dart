import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../platform/gatekeeper_platform.dart';
import '../../settings/validators.dart';

/// Pick the parking spot by moving the map under a fixed centre pin.
/// Also: address search (Android Geocoder), "my location", tap to jump, and pasting
/// coordinates or a Google Maps link. Map tiles come from OpenStreetMap while this screen is open.
class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({
    super.key,
    required this.platform,
    this.initial,
    required this.radiusMeters,
    this.showTiles = true,
  });

  final GateKeeperPlatform platform;
  final LatLng? initial;
  final int radiusMeters;

  /// Tests disable network tiles.
  final bool showTiles;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const _detailZoom = 17.5;

  final _map = MapController();
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  late LatLng _center;
  bool _hasPoint = false;
  bool _locating = false;
  bool _searching = false;
  List<PlaceMessage> _results = const [];
  String? _searchMessage;

  @override
  void initState() {
    super.initState();
    _center = widget.initial ?? const LatLng(20, 0);
    _hasPoint = widget.initial != null;
    if (!_hasPoint) WidgetsBinding.instance.addPostFrameCallback((_) => _useCurrent(silent: true));
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _snack(String text) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  void _goTo(LatLng p, {double? zoom}) {
    _map.move(p, zoom ?? _detailZoom);
    setState(() {
      _center = p;
      _hasPoint = true;
    });
  }

  Future<void> _useCurrent({bool silent = false}) async {
    setState(() => _locating = true);
    try {
      final loc = await widget.platform.getCurrentLocation();
      if (!mounted) return;
      if (loc == null) {
        if (!silent) _snack('Current location unavailable');
      } else {
        _goTo(LatLng(loc.latitude, loc.longitude));
        final acc = loc.accuracyMeters;
        if (acc != null && !silent) _snack('Location accuracy ±${acc.round()} m. Move the map to fine-tune.');
      }
    } on PlatformException catch (e) {
      if (!silent) _snack(e.message ?? 'Location error');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _runSearch(String query) async {
    final q = query.trim();
    if (q.isEmpty) return;
    // Pasted coordinates or a maps link: jump straight there.
    final coords = Validators.parseCoordinates(q);
    if (coords != null) {
      _searchFocus.unfocus();
      setState(() => _results = const []);
      _goTo(LatLng(coords.$1, coords.$2));
      return;
    }
    setState(() {
      _searching = true;
      _searchMessage = null;
    });
    try {
      final places = await widget.platform.searchPlaces(q);
      if (!mounted) return;
      setState(() {
        _results = places;
        _searchMessage = places.isEmpty ? 'No places found. Try a nearby landmark or paste coordinates.' : null;
      });
    } on PlatformException catch (e) {
      if (mounted) setState(() => _searchMessage = e.message ?? 'Search failed');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _pick(PlaceMessage p) {
    _searchFocus.unfocus();
    _search.text = p.label;
    setState(() => _results = const []);
    _goTo(LatLng(p.latitude, p.longitude));
  }

  Future<void> _enterCoordinates() async {
    final ctrl = TextEditingController(
      text: _hasPoint ? '${_center.latitude.toStringAsFixed(6)}, ${_center.longitude.toStringAsFixed(6)}' : '',
    );
    String? error;
    final result = await showDialog<(double, double)>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Enter or paste coordinates'),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              hintText: '12.971600, 77.594600',
              helperText: 'Also accepts a Google Maps or geo: link',
              helperMaxLines: 2,
              errorText: error,
              suffixIcon: IconButton(
                tooltip: 'Paste',
                icon: const Icon(Icons.content_paste_rounded),
                onPressed: () async {
                  final data = await Clipboard.getData(Clipboard.kTextPlain);
                  if (data?.text != null) ctrl.text = data!.text!;
                },
              ),
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(
              onPressed: () {
                final c = Validators.parseCoordinates(ctrl.text);
                if (c == null) {
                  setLocal(() => error = 'Couldn’t find a latitude and longitude in that text');
                } else {
                  Navigator.pop(ctx, c);
                }
              },
              child: const Text('Go'),
            ),
          ],
        ),
      ),
    );
    ctrl.dispose();
    if (result != null) _goTo(LatLng(result.$1, result.$2));
  }

  void _zoom(double delta) {
    final cam = _map.camera;
    _map.move(cam.center, (cam.zoom + delta).clamp(3, 19));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Parking location')),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                FlutterMap(
                  mapController: _map,
                  options: MapOptions(
                    initialCenter: _center,
                    initialZoom: _hasPoint ? _detailZoom : 2,
                    minZoom: 2,
                    maxZoom: 19,
                    interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
                    onPositionChanged: (camera, hasGesture) {
                      setState(() {
                        _center = camera.center;
                        if (hasGesture) _hasPoint = true;
                      });
                    },
                    // Tap somewhere to bring it under the pin.
                    onTap: (_, latLng) => _goTo(latLng, zoom: _map.camera.zoom),
                  ),
                  children: [
                    if (widget.showTiles)
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.gatekeeper.app',
                      ),
                    if (_hasPoint)
                      CircleLayer(
                        circles: [
                          CircleMarker(
                            point: _center,
                            radius: widget.radiusMeters.toDouble(),
                            useRadiusInMeter: true,
                            color: scheme.primary.withValues(alpha: 0.16),
                            borderColor: scheme.primary,
                            borderStrokeWidth: 2,
                          ),
                        ],
                      ),
                    if (widget.showTiles)
                      const RichAttributionWidget(
                        alignment: AttributionAlignment.bottomLeft,
                        attributions: [TextSourceAttribution('OpenStreetMap contributors')],
                      ),
                  ],
                ),
                // Fixed centre pin: its tip marks the chosen point.
                IgnorePointer(
                  child: Center(
                    child: Transform.translate(
                      offset: const Offset(0, -22),
                      child: Icon(Icons.location_on, size: 48, color: scheme.primary, shadows: const [
                        Shadow(blurRadius: 6, color: Colors.black38, offset: Offset(0, 2)),
                      ]),
                    ),
                  ),
                ),
                // Search
                Positioned(
                  left: 12,
                  right: 12,
                  top: 12,
                  child: Material(
                    elevation: 3,
                    borderRadius: BorderRadius.circular(28),
                    color: scheme.surfaceContainerHigh,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: _search,
                          focusNode: _searchFocus,
                          textInputAction: TextInputAction.search,
                          onSubmitted: _runSearch,
                          decoration: InputDecoration(
                            hintText: 'Search address or paste coordinates',
                            border: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(vertical: 14),
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _searching
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                                  )
                                : IconButton(
                                    tooltip: 'Search',
                                    icon: const Icon(Icons.arrow_forward_rounded),
                                    onPressed: () => _runSearch(_search.text),
                                  ),
                          ),
                        ),
                        if (_results.isNotEmpty || _searchMessage != null) const Divider(height: 1),
                        if (_searchMessage != null)
                          Padding(
                            padding: const EdgeInsets.all(14),
                            child: Text(_searchMessage!, style: text.bodySmall),
                          ),
                        if (_results.isNotEmpty)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxHeight: 260),
                            child: ListView.builder(
                              shrinkWrap: true,
                              padding: EdgeInsets.zero,
                              itemCount: _results.length,
                              itemBuilder: (_, i) => ListTile(
                                dense: true,
                                leading: const Icon(Icons.place_outlined),
                                title: Text(_results[i].label, maxLines: 2, overflow: TextOverflow.ellipsis),
                                onTap: () => _pick(_results[i]),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                // Map controls
                Positioned(
                  right: 12,
                  bottom: 16,
                  child: Column(
                    children: [
                      FloatingActionButton.small(
                        heroTag: 'zoom_in',
                        tooltip: 'Zoom in',
                        onPressed: () => _zoom(1),
                        child: const Icon(Icons.add),
                      ),
                      const SizedBox(height: 8),
                      FloatingActionButton.small(
                        heroTag: 'zoom_out',
                        tooltip: 'Zoom out',
                        onPressed: () => _zoom(-1),
                        child: const Icon(Icons.remove),
                      ),
                      const SizedBox(height: 12),
                      FloatingActionButton(
                        heroTag: 'my_location',
                        tooltip: 'My location',
                        onPressed: _locating ? null : _useCurrent,
                        child: _locating
                            ? const SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                            : const Icon(Icons.my_location_rounded),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _hasPoint
                        ? 'Drag the map until the pin sits on your parking spot. Radius: ${widget.radiusMeters} m'
                        : 'Search, use your location, or drag the map to your parking spot.',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _hasPoint
                              ? '${_center.latitude.toStringAsFixed(6)}, ${_center.longitude.toStringAsFixed(6)}'
                              : 'No location selected',
                          key: const Key('picker_coordinates'),
                          style: text.titleMedium?.copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _enterCoordinates,
                        icon: const Icon(Icons.edit_location_alt_outlined),
                        label: const Text('Coordinates'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _hasPoint ? () => Navigator.pop(context, _center) : null,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Use this location'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
