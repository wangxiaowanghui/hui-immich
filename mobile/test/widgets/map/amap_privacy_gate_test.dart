import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/config/app_config.dart';
import 'package:immich_mobile/domain/models/config/map_config.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/widgets/map/amap_privacy_gate.dart';

void main() {
  final messenger = TestWidgetsFlutterBinding.ensureInitialized().defaultBinaryMessenger;
  const channel = MethodChannel('immich/amap_config');
  Widget host(int consent, {bool fallbackButton = false}) => ProviderScope(
    overrides: [appConfigProvider.overrideWithValue(AppConfig(map: MapConfig(amapPrivacyConsentVersion: consent)))],
    child: MaterialApp(
      home: AmapPrivacyGate(
        inlinePrompt: consent == 0,
        builder: (context, useAmap) {
          if (useAmap && fallbackButton) {
            return TextButton(onPressed: () => AmapPrivacyGate.useFallback(context), child: const Text('原生失败'));
          }
          return Text(useAmap ? '高德' : '备用');
        },
      ),
    ),
  );
  setUp(() => messenger.setMockMethodCallHandler(channel, (_) async => true));
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    testWidgets('配置检查完成前不创建备用地图，避免迟到的创建回调覆盖高德控制器', (tester) async {
      final configured = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (_) => configured.future);
      await tester.pumpWidget(host(1));
      await tester.pump();
      expect(find.text('备用'), findsNothing);
      expect(find.text('高德'), findsNothing);
      configured.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('高德'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(platform));
    testWidgets('配置检查超时后仍可使用备用地图', (tester) async {
      final configured = Completer<bool>();
      messenger.setMockMethodCallHandler(channel, (_) => configured.future);
      await tester.pumpWidget(host(1));
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('备用'), findsOneWidget);
      configured.complete(true);
      await tester.pumpAndSettle();
      expect(find.text('高德'), findsNothing);
    }, variant: TargetPlatformVariant.only(platform));
    testWidgets('已同意才允许创建原生地图', (tester) async {
      await tester.pumpWidget(host(1));
      await tester.pumpAndSettle();
      expect(find.text('高德'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(platform));
    testWidgets('已拒绝使用备用地图', (tester) async {
      await tester.pumpWidget(host(-1));
      await tester.pumpAndSettle();
      expect(find.text('备用'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(platform));
    testWidgets('未配置时即便已同意也不启用高德', (tester) async {
      messenger.setMockMethodCallHandler(channel, (_) async => false);
      await tester.pumpWidget(host(1));
      await tester.pumpAndSettle();
      expect(find.text('备用'), findsOneWidget);
    }, variant: TargetPlatformVariant.only(platform));
    testWidgets('原生失败通过当前门禁回退', (tester) async {
      await tester.pumpWidget(host(1, fallbackButton: true));
      await tester.pumpAndSettle();
      await tester.tap(find.text('原生失败'));
      await tester.pumpAndSettle();
      expect(find.text('备用'), findsOneWidget);
      expect(find.text('原生失败'), findsNothing);
    }, variant: TargetPlatformVariant.only(platform));
    testWidgets('未做选择时显示隐私提示且不创建高德', (tester) async {
      await tester.pumpWidget(host(0));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('高德'), findsNothing);
    }, variant: TargetPlatformVariant.only(platform));
  }
  testWidgets('未实现的平台不查询或启用高德', (tester) async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (_) async {
      calls++;
      return true;
    });
    await tester.pumpWidget(host(1));
    await tester.pumpAndSettle();
    expect(find.text('备用'), findsOneWidget);
    expect(calls, 0);
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));
}
