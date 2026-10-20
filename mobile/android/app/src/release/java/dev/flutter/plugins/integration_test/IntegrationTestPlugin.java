package dev.flutter.plugins.integration_test;

import io.flutter.embedding.engine.plugins.FlutterPlugin;

/**
 * The Flutter tool emits the integration_test registrant for this workspace,
 * although dev-dependencies are intentionally absent from release APKs.
 * Keep the release registrant linkable without shipping test functionality.
 */
public final class IntegrationTestPlugin implements FlutterPlugin {
  @Override
  public void onAttachedToEngine(FlutterPluginBinding binding) {}

  @Override
  public void onDetachedFromEngine(FlutterPluginBinding binding) {}
}
