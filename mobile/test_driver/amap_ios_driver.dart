import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

/// 保存真机 SDK 画布截图；仅接收公开示例点，不输出凭据或截图字节。
Future<void> main() async {
  final output = Platform.environment['IMMICH_IOS_EVIDENCE_DIR'];
  if (output == null || !output.startsWith('/')) {
    throw StateError('请用 IMMICH_IOS_EVIDENCE_DIR 指定绝对路径证据目录');
  }
  final directory = Directory(output);
  await directory.create(recursive: true);
  await integrationDriver(
    onScreenshot: (name, bytes, [args]) async {
      if (!RegExp(r'^ipad-amap-[a-z-]+$').hasMatch(name) || bytes.isEmpty) {
        return false;
      }
      await File('${directory.path}/$name.png').writeAsBytes(bytes, flush: true);
      return true;
    },
    responseDataCallback: (_) async {},
    writeResponseOnFailure: true,
  );
}
