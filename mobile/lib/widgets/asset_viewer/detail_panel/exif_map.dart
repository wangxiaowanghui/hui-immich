import 'dart:io';

import 'package:flutter/material.dart';
import 'package:immich_mobile/domain/models/exif.model.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:immich_mobile/widgets/map/map_thumbnail.dart';
import 'package:maplibre_gl/maplibre_gl.dart';
import 'package:url_launcher/url_launcher.dart';

class ExifMap extends StatelessWidget {
  final ExifInfo exifInfo;
  // TODO: Pass in a BaseAsset instead of the ID and thumbhash when removing old timeline
  // This is currently structured this way because of the old timeline implementation
  // reusing this component
  final String? markerId;
  final String? markerAssetThumbhash;
  final MapCreatedCallback? onMapCreated;

  const ExifMap({
    super.key,
    required this.exifInfo,
    this.markerAssetThumbhash,
    this.markerId = 'marker',
    this.onMapCreated,
  });

  @override
  Widget build(BuildContext context) {
    final hasCoordinates = exifInfo.hasCoordinates;
    Future<void> openCoordinates() async {
      if (!hasCoordinates) {
        return;
      }

      final double latitude = exifInfo.latitude!;
      final double longitude = exifInfo.longitude!;
      const zoomLevel = 16;

      if (Platform.isAndroid) {
        if (await _tryLaunch(buildAmapCoordinatesUri(latitude, longitude))) {
          return;
        }
        if (await _tryLaunch(buildGeoCoordinatesUri(latitude, longitude))) {
          return;
        }
      } else if (Platform.isIOS) {
        final params = {'ll': '$latitude,$longitude', 'q': '$latitude,$longitude', 'z': '$zoomLevel'};
        Uri uri = Uri.https('maps.apple.com', '/', params);
        if (await _tryLaunch(uri)) {
          return;
        }
      }

      await _tryLaunch(
        Uri(
          scheme: 'https',
          host: 'www.openstreetmap.org',
          queryParameters: {'mlat': '$latitude', 'mlon': '$longitude'},
          fragment: 'map=$zoomLevel/$latitude/$longitude',
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return MapThumbnail(
          centre: LatLng(exifInfo.latitude ?? 0, exifInfo.longitude ?? 0),
          height: 150,
          width: constraints.maxWidth,
          zoom: 12.0,
          assetMarkerRemoteId: markerId,
          assetThumbhash: markerAssetThumbhash,
          onTap: (tapPosition, latLong) async {
            await openCoordinates();
          },
          onCreated: onMapCreated,
        );
      },
    );
  }
}

Uri buildAmapCoordinatesUri(double latitude, double longitude) => Uri(
  scheme: 'androidamap',
  host: 'viewMap',
  queryParameters: {
    'sourceApplication': 'Immich',
    'poiname': '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}',
    'lat': '$latitude',
    'lon': '$longitude',
    'dev': '1',
  },
);

Uri buildGeoCoordinatesUri(double latitude, double longitude) =>
    Uri.parse('geo:$latitude,$longitude?z=16&q=$latitude,$longitude');

Future<bool> _tryLaunch(Uri uri) async {
  try {
    if (!await canLaunchUrl(uri)) {
      return false;
    }
    dPrint(() => 'Opening Map Uri: $uri');
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  } catch (error) {
    dPrint(() => 'Cannot open Map Uri: $uri ($error)');
    return false;
  }
}
