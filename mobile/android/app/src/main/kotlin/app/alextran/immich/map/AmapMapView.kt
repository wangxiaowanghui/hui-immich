package app.alextran.immich.map

import android.content.Context
import android.graphics.Color
import android.graphics.Typeface
import android.graphics.drawable.GradientDrawable
import android.os.Bundle
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import com.amap.api.maps.AMap
import com.amap.api.maps.CameraUpdateFactory
import com.amap.api.maps.MapView
import com.amap.api.maps.MapsInitializer
import com.amap.api.maps.model.BitmapDescriptorFactory
import com.amap.api.maps.model.CameraPosition
import com.amap.api.maps.model.LatLng
import com.amap.api.maps.model.LatLngBounds
import com.amap.api.maps.model.Marker
import com.amap.api.maps.model.MarkerOptions
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import kotlin.math.max

internal class AmapMapView(
  context: Context,
  messenger: BinaryMessenger,
  viewId: Int,
  private val creationParams: Map<String, Any?>,
) : PlatformView, MethodChannel.MethodCallHandler {
  private data class PhotoPoint(val wgs84: LatLng, val gcj02: LatLng)
  private data class Cluster(val points: List<PhotoPoint>)

  private val density = context.resources.displayMetrics.density
  private val container = FrameLayout(context)
  private val channel = MethodChannel(messenger, "immich/amap_$viewId")
  private val mapView: MapView
  private val map: AMap
  private val markers = mutableListOf<PhotoPoint>()
  private val renderedMarkers = mutableListOf<Marker>()
  private var pin: Marker? = null
  private var didAutoFitMarkers = false
  private var disposed = false

  init {
    check(creationParams["privacyAccepted"] == true) { "AMap must not initialize before privacy consent" }
    MapsInitializer.updatePrivacyShow(context, true, true)
    MapsInitializer.updatePrivacyAgree(context, true)

    mapView = MapView(context)
    mapView.onCreate(Bundle())
    mapView.onResume()
    container.addView(mapView, FrameLayout.LayoutParams(FrameLayout.LayoutParams.MATCH_PARENT, FrameLayout.LayoutParams.MATCH_PARENT))
    map = mapView.map
    channel.setMethodCallHandler(this)

    configureMap()
    configureListeners()
    moveCamera(
      latitude = creationParams.double("latitude"),
      longitude = creationParams.double("longitude"),
      zoom = creationParams.double("zoom").toFloat(),
      animated = false,
    )
    if (creationParams["showMarkerPin"] == true) {
      setPin(creationParams.double("latitude"), creationParams.double("longitude"))
    }
  }

  override fun getView(): View = container

  override fun dispose() {
    if (disposed) return
    disposed = true
    channel.setMethodCallHandler(null)
    renderedMarkers.forEach(Marker::remove)
    renderedMarkers.clear()
    pin?.remove()
    pin = null
    mapView.onPause()
    mapView.onDestroy()
  }

  override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
    try {
      when (call.method) {
        "setMarkers" -> {
          setMarkers(call.argument<List<Map<String, Number>>>("markers").orEmpty())
          result.success(null)
        }
        "moveCamera" -> {
          moveCamera(
            latitude = call.argument<Number>("latitude")!!.toDouble(),
            longitude = call.argument<Number>("longitude")!!.toDouble(),
            zoom = call.argument<Number>("zoom")?.toFloat(),
            animated = call.argument<Boolean>("animated") != false,
          )
          result.success(null)
        }
        "setPin" -> {
          setPin(call.argument<Number>("latitude")!!.toDouble(), call.argument<Number>("longitude")!!.toDouble())
          result.success(null)
        }
        "setDarkMode" -> {
          map.mapType = if (call.argument<Boolean>("darkMode") == true) AMap.MAP_TYPE_NIGHT else AMap.MAP_TYPE_NORMAL
          result.success(null)
        }
        "getVisibleRegion" -> result.success(visibleRegion())
        else -> result.notImplemented()
      }
    } catch (error: Throwable) {
      result.error("AMAP_NATIVE_ERROR", error.message, null)
    }
  }

  private fun configureMap() {
    val interactive = creationParams["interactive"] == true
    map.mapType = if (creationParams["darkMode"] == true) AMap.MAP_TYPE_NIGHT else AMap.MAP_TYPE_NORMAL
    map.setMapLanguage(AMap.CHINESE)
    map.setShowsLocalLanguage(true)
    map.showMapText(true)
    map.showBuildings(true)
    map.showIndoorMap(true)
    map.uiSettings.apply {
      isZoomControlsEnabled = false
      isCompassEnabled = false
      isScaleControlsEnabled = false
      isMyLocationButtonEnabled = false
      setAllGesturesEnabled(interactive)
      isRotateGesturesEnabled = false
      isTiltGesturesEnabled = false
    }
  }

  private fun configureListeners() {
    map.setOnMapLoadedListener {
      if (creationParams["showAttribution"] != false) {
        showApprovalNumber()
      }
      channel.invokeMethod("onMapReady", null)
      redrawClusters()
    }
    map.setOnCameraChangeListener(
      object : AMap.OnCameraChangeListener {
        override fun onCameraChange(position: CameraPosition?) = Unit

        override fun onCameraChangeFinish(position: CameraPosition?) {
          redrawClusters()
          channel.invokeMethod("onCameraIdle", visibleRegion())
        }
      },
    )
    map.setOnMapClickListener { gcj02 ->
      val wgs84 = CoordinateConverter.gcj02ToWgs84(gcj02)
      if (creationParams["selectOnTap"] == true) {
        setPin(wgs84.latitude, wgs84.longitude)
      }
      channel.invokeMethod("onMapClick", latLngMap(wgs84))
    }
    map.setOnMarkerClickListener { marker ->
      val cluster = marker.`object` as? Cluster
      if (cluster != null && cluster.points.size > 1) {
        val zoom = max(map.cameraPosition.zoom + 2f, 3f).coerceAtMost(map.maxZoomLevel)
        map.animateCamera(CameraUpdateFactory.newLatLngZoom(marker.position, zoom))
        true
      } else {
        false
      }
    }
  }

  private fun showApprovalNumber() {
    val approvalNumber = map.mapContentApprovalNumber?.takeIf(String::isNotBlank) ?: return
    val label = TextView(container.context).apply {
      text = "审图号：$approvalNumber"
      textSize = 9f
      setTextColor(Color.DKGRAY)
      setBackgroundColor(0xCCFFFFFF.toInt())
      setPadding(dp(4), dp(2), dp(4), dp(2))
    }
    val params = FrameLayout.LayoutParams(FrameLayout.LayoutParams.WRAP_CONTENT, FrameLayout.LayoutParams.WRAP_CONTENT).apply {
      gravity = Gravity.END or Gravity.BOTTOM
      setMargins(dp(8), dp(8), dp(8), dp(4))
    }
    container.addView(label, params)
  }

  private fun setMarkers(rawMarkers: List<Map<String, Number>>) {
    markers.clear()
    rawMarkers.forEach { marker ->
      val wgs84 = LatLng(marker.getValue("latitude").toDouble(), marker.getValue("longitude").toDouble())
      markers += PhotoPoint(wgs84, CoordinateConverter.wgs84ToGcj02(wgs84))
    }
    redrawClusters()
    autoFitMarkersIfNeeded()
  }

  private fun autoFitMarkersIfNeeded() {
    if (creationParams["autoFitMarkers"] != true || didAutoFitMarkers || markers.isEmpty()) return
    didAutoFitMarkers = true
    val points = markers.map(PhotoPoint::gcj02)
    val update = if (points.size == 1) {
      CameraUpdateFactory.newLatLngZoom(points.single(), 12f)
    } else {
      val bounds = LatLngBounds.Builder().apply {
        points.forEach(::include)
      }.build()
      CameraUpdateFactory.newLatLngBounds(bounds, dp(48))
    }
    // setMarkers is invoked after onMapLoaded, so the view already has a size.
    // Move synchronously so Flutter can read the fitted visible region only
    // after the bootstrap camera state is authoritative.
    map.moveCamera(update)
    redrawClusters()
  }

  private fun redrawClusters() {
    if (disposed || container.width == 0 || container.height == 0) return
    renderedMarkers.forEach(Marker::remove)
    renderedMarkers.clear()
    if (markers.isEmpty()) return

    val visibleBounds = map.projection.visibleRegion.latLngBounds
    val cellSize = dp(52).coerceAtLeast(1)
    val grouped = markers
      .asSequence()
      .filter { visibleBounds.contains(it.gcj02) }
      .groupBy { point ->
        val screen = map.projection.toScreenLocation(point.gcj02)
        (screen.x / cellSize) to (screen.y / cellSize)
      }

    grouped.values.forEach { points ->
      val latitude = points.sumOf { it.gcj02.latitude } / points.size
      val longitude = points.sumOf { it.gcj02.longitude } / points.size
      val marker = map.addMarker(
        MarkerOptions()
          .position(LatLng(latitude, longitude))
          .anchor(0.5f, 0.5f)
          .icon(clusterIcon(points.size))
          .zIndex(10f),
      )
      marker.`object` = Cluster(points)
      renderedMarkers += marker
    }
  }

  private fun clusterIcon(count: Int) = BitmapDescriptorFactory.fromView(
    TextView(container.context).apply {
      val size = if (count == 1) dp(18) else dp(40)
      layoutParams = FrameLayout.LayoutParams(size, size)
      gravity = Gravity.CENTER
      text = if (count == 1) "" else if (count > 999) "999+" else count.toString()
      textSize = if (count > 999) 11f else 14f
      typeface = Typeface.DEFAULT_BOLD
      setTextColor(Color.WHITE)
      background = GradientDrawable().apply {
        shape = GradientDrawable.OVAL
        setColor(Color.rgb(63, 81, 181))
        setStroke(dp(2), Color.WHITE)
      }
    },
  )

  private fun setPin(latitude: Double, longitude: Double) {
    val point = CoordinateConverter.wgs84ToGcj02(LatLng(latitude, longitude))
    val current = pin
    if (current == null) {
      pin = map.addMarker(
        MarkerOptions()
          .position(point)
          .icon(BitmapDescriptorFactory.defaultMarker(BitmapDescriptorFactory.HUE_AZURE))
          .anchor(0.5f, 1f)
          .zIndex(20f),
      )
    } else {
      current.position = point
    }
  }

  private fun moveCamera(latitude: Double, longitude: Double, zoom: Float?, animated: Boolean) {
    val target = CoordinateConverter.wgs84ToGcj02(LatLng(latitude, longitude))
    val safeZoom = zoom?.coerceIn(map.minZoomLevel, map.maxZoomLevel)
    val update = if (safeZoom == null) {
      CameraUpdateFactory.newLatLng(target)
    } else {
      CameraUpdateFactory.newLatLngZoom(target, safeZoom)
    }
    if (animated) map.animateCamera(update) else map.moveCamera(update)
  }

  private fun visibleRegion(): Map<String, Map<String, Double>> {
    val bounds = map.projection.visibleRegion.latLngBounds
    return mapOf(
      "southwest" to latLngMap(CoordinateConverter.gcj02ToWgs84(bounds.southwest)),
      "northeast" to latLngMap(CoordinateConverter.gcj02ToWgs84(bounds.northeast)),
    )
  }

  private fun latLngMap(point: LatLng) = mapOf("latitude" to point.latitude, "longitude" to point.longitude)

  private fun dp(value: Int): Int = (value * density).toInt()

  private fun Map<String, Any?>.double(key: String): Double = (get(key) as? Number)?.toDouble() ?: 0.0
}
