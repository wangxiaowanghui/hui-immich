import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/events.model.dart';
import 'package:immich_mobile/domain/utils/event_stream.dart';
import 'package:immich_mobile/extensions/asyncvalue_extensions.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/bottom_sheet/base_bottom_sheet.widget.dart';
import 'package:immich_mobile/presentation/widgets/bottom_sheet/map_bottom_sheet.widget.dart';
import 'package:immich_mobile/presentation/widgets/map/map.state.dart';
import 'package:immich_mobile/presentation/widgets/map/map_utils.dart';
import 'package:immich_mobile/providers/routes.provider.dart';
import 'package:immich_mobile/utils/async_mutex.dart';
import 'package:immich_mobile/utils/debounce.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_mobile/widgets/map/amap_map.dart';
import 'package:immich_mobile/widgets/map/amap_privacy_gate.dart';
import 'package:immich_mobile/widgets/map/map_theme_override.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

class DriftMap extends ConsumerStatefulWidget {
  final LatLng? initialLocation;

  const DriftMap({super.key, this.initialLocation});

  @override
  ConsumerState<DriftMap> createState() => _DriftMapState();
}

class _DriftMapState extends ConsumerState<DriftMap> {
  MapLibreMapController? mapController;
  AmapMapController? amapController;
  final _reloadMutex = AsyncMutex();
  final _debouncer = Debouncer(
      interval: const Duration(milliseconds: 500),
      maxWaitTime: const Duration(seconds: 2));
  final ValueNotifier<double> bottomSheetOffset = ValueNotifier(0.25);
  final GlobalKey _bottomSheetKey = GlobalKey();
  StreamSubscription? _eventSubscription;
  bool _amapInitialLoadPending = false;

  @override
  void initState() {
    super.initState();
    _amapInitialLoadPending = widget.initialLocation == null;
    _eventSubscription =
        EventStream.shared.listen<MapMarkerReloadEvent>(_onEvent);
  }

  @override
  void dispose() {
    _debouncer.dispose();
    bottomSheetOffset.dispose();
    _eventSubscription?.cancel();
    super.dispose();
  }

  void onMapCreated(MapLibreMapController controller) {
    mapController = controller;
    amapController = null;
  }

  void onAmapCreated(AmapMapController controller) {
    amapController = controller;
    mapController = null;
  }

  void _onEvent(_) => _debouncer.run(() => setBounds(forceReload: true));

  Future<void> onMapLibreReady() async {
    final controller = mapController;
    if (controller == null) {
      return;
    }

    await controller.addSource(
      MapUtils.defaultSourceId,
      GeojsonSourceProperties(
        data: const {'type': 'FeatureCollection', 'features': []},
        cluster: Platform.isAndroid,
        clusterRadius: 50,
      ),
    );

    try {
      if (Platform.isAndroid) {
        await controller.addCircleLayer(
          MapUtils.defaultSourceId,
          MapUtils.defaultClusterCircleLayerId,
          MapUtils.defaultClusterCircleLayerProperties,
          filter: MapUtils.clusterFilter,
          enableInteraction: false,
        );
        await controller.addSymbolLayer(
          MapUtils.defaultSourceId,
          MapUtils.defaultMarkerCountLayerId,
          MapUtils.defaultMarkerCountLayerProperties,
          filter: MapUtils.clusterFilter,
          enableInteraction: false,
        );
        await controller.addCircleLayer(
          MapUtils.defaultSourceId,
          MapUtils.defaultUnclusteredPointLayerId,
          MapUtils.defaultUnclusteredPointLayerProperties,
          filter: MapUtils.unclusteredPointFilter,
          enableInteraction: false,
        );
      }

      if (Platform.isIOS) {
        await controller.addHeatmapLayer(
          MapUtils.defaultSourceId,
          MapUtils.defaultHeatMapLayerId,
          MapUtils.defaultHeatmapLayerProperties,
        );
      }
    } finally {
      // A native layer error must not prevent the initial GeoJSON request.
      _debouncer.run(() => setBounds(forceReload: true));
      controller.addListener(onMapMoved);
    }
  }

  void onAmapReady() => unawaited(_initializeAmap());

  Future<void> _initializeAmap() async {
    if (widget.initialLocation != null) {
      await setBounds(forceReload: true);
      return;
    }

    // AMap starts at (0, 0) when no initial location is available. Loading that
    // viewport first would produce an empty result and could race with the
    // marker-driven camera fit. The repository's null-bounds query is the
    // canonical way to load all located assets for this one-time bootstrap.
    await _reloadMutex.run(() async {
      if (!mounted || amapController == null) {
        return;
      }
      final markers = await ref.read(mapMarkerProvider(null).future);
      await reloadMarkers(markers);
    });

    if (!mounted || amapController == null) {
      return;
    }
    _amapInitialLoadPending = false;
    final fittedBounds = await amapController!.getVisibleRegion();
    await setBounds(forceReload: true, boundsOverride: fittedBounds);
  }

  void onAmapCameraIdle(LatLngBounds bounds) {
    if (_amapInitialLoadPending) {
      return;
    }
    _debouncer.run(() => setBounds(boundsOverride: bounds));
  }

  void onMapMoved() {
    if (mapController!.isCameraMoving || !mounted) {
      return;
    }

    _debouncer.run(setBounds);
  }

  Future<void> setBounds(
      {bool forceReload = false, LatLngBounds? boundsOverride}) async {
    if ((mapController == null && amapController == null) || !mounted) {
      return;
    }

    // When the AssetViewer is open, the DriftMap route stays alive in the background.
    // If we continue to update bounds, the map-scoped timeline service gets recreated and the previous one disposed,
    // which can invalidate the TimelineService instance that was passed into AssetViewerRoute (causing "loading forever").
    if (ref.read(isAssetViewerOpenProvider)) {
      return;
    }

    final bounds = boundsOverride ??
        (amapController != null
            ? await amapController!.getVisibleRegion()
            : await mapController!.getVisibleRegion());
    await _reloadMutex.run(() async {
      if (mounted &&
          (ref.read(mapStateProvider.notifier).setBounds(bounds) ||
              forceReload)) {
        final markers = await ref.read(mapMarkerProvider(bounds).future);
        await reloadMarkers(markers);
      }
    });
  }

  Future<void> reloadMarkers(Map<String, dynamic> markers) async {
    if ((mapController == null && amapController == null) || !mounted) {
      return;
    }

    if (amapController != null) {
      await amapController!.setGeoJson(markers);
    } else {
      await mapController!.setGeoJsonSource(MapUtils.defaultSourceId, markers);
    }
  }

  Future<void> onZoomToLocation() async {
    final (location, error) =
        await MapUtils.checkPermAndGetLocation(context: context);
    if (error != null) {
      if (error == LocationPermission.unableToDetermine && context.mounted) {
        ImmichToast.show(
          context: context,
          gravity: ToastGravity.BOTTOM,
          toastType: ToastType.error,
          msg: "map_cannot_get_user_location".t(context: context),
        );
      }
      return;
    }

    if (location != null) {
      final target = LatLng(location.latitude, location.longitude);
      if (amapController != null) {
        await amapController!
            .moveCamera(target, zoom: MapUtils.mapZoomToAssetLevel);
      } else if (mapController != null) {
        await mapController!.animateCamera(
          CameraUpdate.newLatLngZoom(target, MapUtils.mapZoomToAssetLevel),
          duration: const Duration(milliseconds: 800),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<bool>(isAssetViewerOpenProvider, (previous, current) {
      if (previous == true && !current) {
        _debouncer.run(() => setBounds(forceReload: true));
      }
    });
    return Stack(
      children: [
        _Map(
          initialLocation: widget.initialLocation,
          onMapCreated: onMapCreated,
          onMapLibreReady: onMapLibreReady,
          onAmapCreated: onAmapCreated,
          onAmapReady: onAmapReady,
          onAmapCameraIdle: onAmapCameraIdle,
        ),
        _DynamicBottomSheet(
            bottomSheetOffset: bottomSheetOffset, sheetKey: _bottomSheetKey),
        _DynamicMyLocationButton(
            onZoomToLocation: onZoomToLocation,
            bottomSheetOffset: bottomSheetOffset),
      ],
    );
  }
}

class _Map extends StatelessWidget {
  final LatLng? initialLocation;

  const _Map({
    this.initialLocation,
    required this.onMapCreated,
    required this.onMapLibreReady,
    required this.onAmapCreated,
    required this.onAmapReady,
    required this.onAmapCameraIdle,
  });

  final MapCreatedCallback onMapCreated;

  final VoidCallback onMapLibreReady;
  final AmapMapCreatedCallback onAmapCreated;
  final VoidCallback onAmapReady;
  final AmapCameraIdleCallback onAmapCameraIdle;

  @override
  Widget build(BuildContext context) {
    final initialLocation = this.initialLocation;
    return MapThemeOverride(
      mapBuilder: (style) => AmapPrivacyGate(
        builder: (context, useAmap) {
          final center = initialLocation ?? const LatLng(0, 0);
          final zoom =
              initialLocation == null ? 3.0 : MapUtils.mapZoomToAssetLevel;
          if (useAmap) {
            return AmapMap(
              initialCenter: center,
              zoom: zoom,
              autoFitMarkers: initialLocation == null,
              darkMode: Theme.of(context).brightness == Brightness.dark,
              onMapCreated: onAmapCreated,
              onMapReady: onAmapReady,
              onCameraIdle: onAmapCameraIdle,
            );
          }
          return style.widgetWhen(
            onData: (style) => MapLibreMap(
              initialCameraPosition: CameraPosition(target: center, zoom: zoom),
              compassEnabled: false,
              rotateGesturesEnabled: false,
              styleString: style,
              onMapCreated: onMapCreated,
              onStyleLoadedCallback: onMapLibreReady,
              attributionButtonPosition: AttributionButtonPosition.topRight,
              attributionButtonMargins: const Point(8, kToolbarHeight),
            ),
          );
        },
      ),
    );
  }
}

class _DynamicBottomSheet extends StatefulWidget {
  final ValueNotifier<double> bottomSheetOffset;
  final GlobalKey sheetKey;

  const _DynamicBottomSheet(
      {required this.bottomSheetOffset, required this.sheetKey});

  @override
  State<_DynamicBottomSheet> createState() => _DynamicBottomSheetState();
}

class _DynamicBottomSheetState extends State<_DynamicBottomSheet> {
  @override
  Widget build(BuildContext context) {
    return NotificationListener<DraggableScrollableNotification>(
      onNotification: (notification) {
        final sheet = notification.context
            .findAncestorWidgetOfExactType<BaseBottomSheet>();
        if (sheet?.key == widget.sheetKey) {
          widget.bottomSheetOffset.value = notification.extent;
        }
        return false;
      },
      child: MapBottomSheet(sheetKey: widget.sheetKey),
    );
  }
}

class _DynamicMyLocationButton extends StatelessWidget {
  const _DynamicMyLocationButton(
      {required this.onZoomToLocation, required this.bottomSheetOffset});

  final VoidCallback onZoomToLocation;
  final ValueNotifier<double> bottomSheetOffset;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: bottomSheetOffset,
      builder: (context, offset, child) {
        return Positioned(
          right: 20,
          bottom: context.height * (offset - 0.02) + context.padding.bottom,
          child: AnimatedOpacity(
            opacity: offset < 0.8 ? 1 : 0,
            duration: const Duration(milliseconds: 150),
            child: ElevatedButton(
              onPressed: onZoomToLocation,
              style: ElevatedButton.styleFrom(shape: const CircleBorder()),
              child: const Icon(Icons.my_location),
            ),
          ),
        );
      },
    );
  }
}
