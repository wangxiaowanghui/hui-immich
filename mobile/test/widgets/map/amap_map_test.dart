import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/widgets/map/amap_map.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

void iosTest(String name, WidgetTesterCallback callback) =>
    testWidgets(name, callback, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  const codec = StandardMethodCodec();
  late int id;
  late Map creation;
  late List<MethodCall> commands;
  Future<void> emit(String method, [dynamic arguments]) async {
    final done = Completer<void>();
    await binding.defaultBinaryMessenger.handlePlatformMessage(
      'immich/amap_$id',
      codec.encodeMethodCall(MethodCall(method, arguments)),
      (_) => done.complete(),
    );
    await done.future;
  }

  setUp(() {
    commands = [];
    binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, (call) async {
      if (call.method == 'create') {
        id = call.arguments['id'] as int;
        creation =
            const StandardMessageCodec().decodeMessage(ByteData.sublistView(call.arguments['params'] as Uint8List))
                as Map;
        binding.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel('immich/amap_$id'), (call) async {
          commands.add(call);
          if (call.method == 'getVisibleRegion') {
            return {
              'southwest': {'latitude': 30.0, 'longitude': 110.0},
              'northeast': {'latitude': 40.0, 'longitude': 120.0},
            };
          }
          return null;
        });
      }
      return null;
    });
  });
  tearDown(() {
    binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform_views, null);
    binding.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel('immich/amap_$id'), null);
  });
  Widget host({AmapMapCreatedCallback? created, VoidCallback? ready, VoidCallback? error, bool dark = false}) =>
      MaterialApp(
        home: AmapMap(
          initialCenter: const LatLng(39.9, 116.4),
          zoom: 12,
          darkMode: dark,
          onMapCreated: created,
          onMapReady: ready,
          onMapError: error,
        ),
      );
  iosTest('iOS 使用 UiKitView，通道建立后才握手，且只报告一次就绪', (tester) async {
    var readyCount = 0;
    await tester.pumpWidget(host(ready: () => readyCount++));
    await tester.pump();
    expect(find.byType(UiKitView), findsOneWidget);
    expect(find.byType(AndroidView), findsNothing);
    expect(creation['privacyAccepted'], isTrue);
    expect(creation['latitude'], 39.9);
    expect(commands.map((call) => call.method), contains('initialize'));
    await emit('onMapReady');
    await emit('onMapReady');
    expect(readyCount, 1);
    await tester.pumpWidget(const SizedBox());
    expect(commands.map((call) => call.method), contains('dispose'));
  });
  iosTest('通道保留 WGS-84，标记、视野、主题更新均正确', (tester) async {
    late AmapMapController controller;
    await tester.pumpWidget(host(created: (value) => controller = value));
    await tester.pump();
    await emit('onMapReady');
    await controller.setGeoJson({
      'features': [
        {
          'geometry': {
            'coordinates': [116.4, 39.9],
          },
        },
      ],
    });
    expect(commands.last.arguments, {
      'markers': [
        {'latitude': 39.9, 'longitude': 116.4},
      ],
    });
    final bounds = await controller.getVisibleRegion();
    expect(bounds.southwest, const LatLng(30, 110));
    expect(bounds.northeast, const LatLng(40, 120));
    await tester.pumpWidget(host(dark: true));
    await tester.pump();
    expect(commands.last.method, 'setDarkMode');
    expect(commands.last.arguments, {'darkMode': true});
    await tester.pumpWidget(const SizedBox());
  });
  iosTest('原生错误只触发一次回退，失败后不会再报告就绪', (tester) async {
    var errors = 0, ready = 0;
    await tester.pumpWidget(host(error: () => errors++, ready: () => ready++));
    await tester.pump();
    await emit('onMapError');
    await emit('onMapError');
    await emit('onMapReady');
    expect(errors, 1);
    expect(ready, 0);
    await tester.pumpWidget(const SizedBox());
  });
  iosTest('加载超时触发回退，销毁后不会再触发回调', (tester) async {
    var errors = 0;
    await tester.pumpWidget(host(error: () => errors++));
    await tester.pump();
    await tester.pump(const Duration(seconds: 31));
    expect(errors, 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 31));
    expect(errors, 1);
  });
  iosTest('通道异常回退且不会向上抛出未处理异常', (tester) async {
    var errors = 0;
    late AmapMapController controller;
    await tester.pumpWidget(host(created: (value) => controller = value, error: () => errors++));
    await tester.pump();
    await emit('onMapReady');
    binding.defaultBinaryMessenger.setMockMethodCallHandler(MethodChannel('immich/amap_$id'), (_) async {
      throw PlatformException(code: 'not_ready');
    });
    await controller.moveCamera(const LatLng(1, 2));
    expect(errors, 1);
    expect((await controller.getVisibleRegion()).southwest, const LatLng(39.9, 116.4));
    await tester.pumpWidget(const SizedBox());
  });
}
