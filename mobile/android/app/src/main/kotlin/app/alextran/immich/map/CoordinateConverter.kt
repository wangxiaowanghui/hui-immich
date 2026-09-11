package app.alextran.immich.map

import com.amap.api.maps.model.LatLng
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin
import kotlin.math.sqrt

internal object CoordinateConverter {
  private const val A = 6378245.0
  private const val EE = 0.006693421622965943

  fun wgs84ToGcj02(point: LatLng): LatLng {
    if (outsideChina(point.latitude, point.longitude)) {
      return point
    }

    val delta = delta(point.latitude, point.longitude)
    return LatLng(point.latitude + delta.first, point.longitude + delta.second)
  }

  fun gcj02ToWgs84(point: LatLng): LatLng {
    if (outsideChina(point.latitude, point.longitude)) {
      return point
    }

    var estimate = point
    repeat(3) {
      val converted = wgs84ToGcj02(estimate)
      estimate = LatLng(
        estimate.latitude - (converted.latitude - point.latitude),
        estimate.longitude - (converted.longitude - point.longitude),
      )
    }
    return estimate
  }

  private fun outsideChina(latitude: Double, longitude: Double): Boolean =
    longitude < 72.004 || longitude > 137.8347 || latitude < 0.8293 || latitude > 55.8271

  private fun delta(latitude: Double, longitude: Double): Pair<Double, Double> {
    var latitudeDelta = transformLatitude(longitude - 105.0, latitude - 35.0)
    var longitudeDelta = transformLongitude(longitude - 105.0, latitude - 35.0)
    val radianLatitude = latitude / 180.0 * PI
    var magic = sin(radianLatitude)
    magic = 1 - EE * magic * magic
    val sqrtMagic = sqrt(magic)
    latitudeDelta = (latitudeDelta * 180.0) / ((A * (1 - EE)) / (magic * sqrtMagic) * PI)
    longitudeDelta = (longitudeDelta * 180.0) / (A / sqrtMagic * kotlin.math.cos(radianLatitude) * PI)
    return latitudeDelta to longitudeDelta
  }

  private fun transformLatitude(x: Double, y: Double): Double {
    var result = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y + 0.2 * sqrt(abs(x))
    result += (20.0 * sin(6.0 * x * PI) + 20.0 * sin(2.0 * x * PI)) * 2.0 / 3.0
    result += (20.0 * sin(y * PI) + 40.0 * sin(y / 3.0 * PI)) * 2.0 / 3.0
    result += (160.0 * sin(y / 12.0 * PI) + 320.0 * sin(y * PI / 30.0)) * 2.0 / 3.0
    return result
  }

  private fun transformLongitude(x: Double, y: Double): Double {
    var result = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y + 0.1 * sqrt(abs(x))
    result += (20.0 * sin(6.0 * x * PI) + 20.0 * sin(2.0 * x * PI)) * 2.0 / 3.0
    result += (20.0 * sin(x * PI) + 40.0 * sin(x / 3.0 * PI)) * 2.0 / 3.0
    result += (150.0 * sin(x / 12.0 * PI) + 300.0 * sin(x / 30.0 * PI)) * 2.0 / 3.0
    return result
  }
}
