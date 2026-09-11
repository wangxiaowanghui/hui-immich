package app.alextran.immich.map

import android.content.Context
import app.alextran.immich.BuildConfig
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

object AmapMapPlugin {
  private const val CONFIG_CHANNEL = "immich/amap_config"
  private const val VIEW_TYPE = "immich/amap"

  fun register(context: Context, flutterEngine: FlutterEngine) {
    val messenger = flutterEngine.dartExecutor.binaryMessenger
    MethodChannel(messenger, CONFIG_CHANNEL).setMethodCallHandler { call, result ->
      when (call.method) {
        "isConfigured" -> result.success(BuildConfig.AMAP_CONFIGURED)
        else -> result.notImplemented()
      }
    }
    flutterEngine.platformViewsController.registry.registerViewFactory(
      VIEW_TYPE,
      AmapMapViewFactory(context, messenger),
    )
  }
}
