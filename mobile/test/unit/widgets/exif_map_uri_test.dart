import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/widgets/asset_viewer/detail_panel/exif_map.dart';

void main() {
  test('AMap URI uses WGS84 coordinates and the official Android scheme', () {
    final uri = buildAmapCoordinatesUri(39.908823, 116.397470);

    expect(uri.scheme, 'androidamap');
    expect(uri.host, 'viewmap');
    expect(uri.queryParameters['lat'], '39.908823');
    expect(uri.queryParameters['lon'], '116.39747');
    expect(uri.queryParameters['dev'], '1');
  });

  test('geo fallback does not create an invalid authority URI', () {
    final uri = buildGeoCoordinatesUri(39.908823, 116.397470);

    expect(uri.scheme, 'geo');
    expect(uri.hasAuthority, isFalse);
    expect(uri.path, '39.908823,116.39747');
    expect(uri.queryParameters['z'], '16');
    expect(uri.queryParameters['q'], '39.908823,116.39747');
  });
}
