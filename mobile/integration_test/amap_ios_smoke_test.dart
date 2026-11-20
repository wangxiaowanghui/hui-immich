import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/widgets/map/amap_map.dart';
import 'package:integration_test/integration_test.dart';
import 'package:maplibre_gl/maplibre_gl.dart';

/// 仅使用公开示例点，不登录 NAS、不读取照片、不清空应用数据库。
/// 执行前需已取得高德隐私授权；此冒烟测试不替代照片列表和视觉验收。
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('实体 iOS 原生地图加载、通道、主题与重建冒烟', (tester) async {
    expect(Platform.isIOS, isTrue, reason: '本测试仅用于已签名的 iOS 真机包');
    // 系统权限弹窗会令原生画布无法显示，不应误报成 SDK 鉴权失败。
    final foregroundDeadline = DateTime.now().add(const Duration(seconds: 30));
    while (binding.lifecycleState != AppLifecycleState.resumed && DateTime.now().isBefore(foregroundDeadline)) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(
      binding.lifecycleState,
      AppLifecycleState.resumed,
      reason: '真机应用必须先进入活动前台；请处理系统权限弹窗，这不是地图鉴权结论',
    );
    final configured = await const MethodChannel('immich/amap_config').invokeMethod<bool>('isConfigured');
    expect(configured, isTrue, reason: '需要有效 iOS Key 与匹配的 Bundle ID');
    var ready = false;
    var failed = false;
    late AmapMapController controller;
    Widget map({required String key, bool dark = false}) => MaterialApp(
      home: Scaffold(
        body: AmapMap(
          key: ValueKey(key),
          initialCenter: const LatLng(39.908823, 116.397470),
          zoom: 12,
          showMarkerPin: true,
          darkMode: dark,
          onMapCreated: (value) => controller = value,
          onMapReady: () => ready = true,
          onMapError: () => failed = true,
        ),
      ),
    );
    Future<void> waitReady() async {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (!ready && !failed && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 200));
      }
      if (failed || !ready) {
        await binding.takeScreenshot('ipad-amap-load-failed');
      }
      expect(failed, isFalse, reason: '原生 SDK 不得报告鉴权或加载失败');
      expect(ready, isTrue, reason: '必须收到真实 SDK 加载完成回调');
    }

    await tester.pumpWidget(map(key: 'first'));
    await waitReady();
    final bounds = await controller.getVisibleRegion();
    expect(bounds.southwest.latitude, lessThan(39.908823));
    expect(bounds.northeast.latitude, greaterThan(39.908823));
    expect(bounds.southwest.longitude, lessThan(116.397470));
    expect(bounds.northeast.longitude, greaterThan(116.397470));
    await controller.setGeoJson({
      'features': [
        {
          'geometry': {
            'coordinates': [116.417470, 39.918823],
          },
        },
        {
          'geometry': {
            'coordinates': [116.417480, 39.918833],
          },
        },
      ],
    });
    await tester.pump(const Duration(seconds: 2));
    await binding.takeScreenshot('ipad-amap-light');
    await controller.moveCamera(const LatLng(39.918823, 116.417470), zoom: 14, animated: false);
    await tester.pump(const Duration(seconds: 2));
    final zoomed = await controller.getVisibleRegion();
    expect(
      zoomed.northeast.longitude - zoomed.southwest.longitude,
      lessThan(bounds.northeast.longitude - bounds.southwest.longitude),
      reason: '真实原生地图缩放后视野应缩小',
    );
    await controller.setPin(const LatLng(39.915, 116.415));
    await tester.pumpWidget(map(key: 'first', dark: true));
    await tester.pump(const Duration(seconds: 1));
    expect(failed, isFalse);
    await binding.takeScreenshot('ipad-amap-dark-zoomed');
    await tester.pumpWidget(const SizedBox());
    ready = false;
    await tester.pumpWidget(map(key: 'second'));
    await waitReady();
    await binding.takeScreenshot('ipad-amap-recreated');
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(minutes: 2)));
}
