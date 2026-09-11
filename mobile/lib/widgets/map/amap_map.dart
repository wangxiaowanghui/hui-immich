import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

typedef AmapMapCreatedCallback = void Function(AmapMapController controller);
typedef AmapCameraIdleCallback = void Function(LatLngBounds bounds);

class AmapMapController {
  final MethodChannel _channel;

  AmapMapController._(int viewId) : _channel = MethodChannel('immich/amap_$viewId');

  Future<void> setGeoJson(Map<String, dynamic> geoJson) async {
    final features = geoJson['features'] as List<dynamic>? ?? const [];
    final markers = <Map<String, double>>[];
    for (final feature in features) {
      final geometry = (feature as Map)['geometry'] as Map?;
      final coordinates = geometry?['coordinates'] as List?;
      if (coordinates == null || coordinates.length < 2) {
        continue;
      }
      markers.add({'longitude': (coordinates[0] as num).toDouble(), 'latitude': (coordinates[1] as num).toDouble()});
    }
    await _channel.invokeMethod<void>('setMarkers', {'markers': markers});
  }

  Future<void> moveCamera(LatLng target, {double? zoom, bool animated = true}) => _channel.invokeMethod<void>(
    'moveCamera',
    {'latitude': target.latitude, 'longitude': target.longitude, 'zoom': zoom, 'animated': animated},
  );

  Future<void> setPin(LatLng target) =>
      _channel.invokeMethod<void>('setPin', {'latitude': target.latitude, 'longitude': target.longitude});

  Future<void> setDarkMode(bool darkMode) => _channel.invokeMethod<void>('setDarkMode', {'darkMode': darkMode});

  Future<LatLngBounds> getVisibleRegion() async {
    final raw = await _channel.invokeMapMethod<String, dynamic>('getVisibleRegion');
    if (raw == null) {
      throw StateError('AMap visible region is unavailable');
    }
    return LatLngBounds(southwest: _latLng(raw['southwest'] as Map), northeast: _latLng(raw['northeast'] as Map));
  }

  static LatLng _latLng(Map raw) => LatLng((raw['latitude'] as num).toDouble(), (raw['longitude'] as num).toDouble());
}

class AmapMap extends StatefulWidget {
  final LatLng initialCenter;
  final double zoom;
  final bool interactive;
  final bool darkMode;
  final bool showMarkerPin;
  final bool selectOnTap;
  final bool showAttribution;
  final bool autoFitMarkers;
  final AmapMapCreatedCallback? onMapCreated;
  final VoidCallback? onMapReady;
  final AmapCameraIdleCallback? onCameraIdle;
  final void Function(Point<double> point, LatLng coordinates)? onMapClick;

  const AmapMap({
    super.key,
    required this.initialCenter,
    required this.zoom,
    this.interactive = true,
    this.darkMode = false,
    this.showMarkerPin = false,
    this.selectOnTap = false,
    this.showAttribution = true,
    this.autoFitMarkers = false,
    this.onMapCreated,
    this.onMapReady,
    this.onCameraIdle,
    this.onMapClick,
  });

  @override
  State<AmapMap> createState() => _AmapMapState();
}

class _AmapMapState extends State<AmapMap> {
  AmapMapController? _controller;

  @override
  void didUpdateWidget(covariant AmapMap oldWidget) {
    super.didUpdateWidget(oldWidget);
    final controller = _controller;
    if (controller == null) {
      return;
    }
    if (oldWidget.initialCenter != widget.initialCenter) {
      unawaited(controller.moveCamera(widget.initialCenter, animated: false));
      if (widget.showMarkerPin) {
        unawaited(controller.setPin(widget.initialCenter));
      }
    }
    if (oldWidget.darkMode != widget.darkMode) {
      unawaited(controller.setDarkMode(widget.darkMode));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'immich/amap',
      creationParamsCodec: const StandardMessageCodec(),
      creationParams: {
        'latitude': widget.initialCenter.latitude,
        'longitude': widget.initialCenter.longitude,
        'zoom': widget.zoom,
        'interactive': widget.interactive,
        'darkMode': widget.darkMode,
        'showMarkerPin': widget.showMarkerPin,
        'selectOnTap': widget.selectOnTap,
        'showAttribution': widget.showAttribution,
        'autoFitMarkers': widget.autoFitMarkers,
        'privacyAccepted': true,
      },
      onPlatformViewCreated: _onPlatformViewCreated,
    );
  }

  void _onPlatformViewCreated(int viewId) {
    final controller = AmapMapController._(viewId);
    _controller = controller;
    controller._channel.setMethodCallHandler((call) async {
      if (!mounted) {
        return;
      }
      switch (call.method) {
        case 'onMapReady':
          widget.onMapReady?.call();
          return;
        case 'onCameraIdle':
          final raw = call.arguments as Map;
          widget.onCameraIdle?.call(
            LatLngBounds(
              southwest: AmapMapController._latLng(raw['southwest'] as Map),
              northeast: AmapMapController._latLng(raw['northeast'] as Map),
            ),
          );
          return;
        case 'onMapClick':
          widget.onMapClick?.call(const Point(0, 0), AmapMapController._latLng(call.arguments as Map));
          return;
      }
    });
    widget.onMapCreated?.call(controller);
  }

  @override
  void dispose() {
    _controller?._channel.setMethodCallHandler(null);
    super.dispose();
  }
}
