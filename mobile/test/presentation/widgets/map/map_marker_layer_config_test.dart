import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/presentation/widgets/map/map_utils.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void main() {
  test('Android marker source uses supported point clustering options', () {
    const data = {'type': 'FeatureCollection', 'features': <Object>[]};

    final source = const GeojsonSourceProperties(data: data, cluster: true, clusterRadius: 50).toJson();

    expect(source['cluster'], isTrue);
    expect(source['clusterRadius'], 50);
    expect(source, isNot(contains('clusterMinPoints')));
  });

  test('Android marker layers isolate clustered and raw features', () {
    final clusterCircle = MapUtils.defaultClusterCircleLayerProperties.toJson();
    final count = MapUtils.defaultMarkerCountLayerProperties.toJson();
    final point = MapUtils.defaultUnclusteredPointLayerProperties.toJson();

    expect(MapUtils.clusterFilter, [Expressions.has, 'point_count']);
    expect(MapUtils.unclusteredPointFilter, [
      Expressions.not,
      [Expressions.has, 'point_count'],
    ]);
    expect(clusterCircle['circle-blur'], 0);
    expect(clusterCircle['circle-radius'], [
      Expressions.step,
      [Expressions.get, 'point_count'],
      18,
      10,
      20,
      50,
      24,
      100,
      28,
    ]);
    expect(point['circle-blur'], 0);
    expect(point['circle-radius'], 8);
    expect(count['text-field'], [Expressions.get, 'point_count_abbreviated']);
    expect(count['text-font'], ['Noto Sans Medium']);
    expect(count['text-color'], '#FFFFFF');
    expect(count['text-allow-overlap'], isTrue);
  });
}
