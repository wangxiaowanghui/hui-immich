package app.alextran.immich.map

import com.amap.api.maps.model.LatLng
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class CoordinateConverterTest {
  @Test
  fun `converts mainland WGS84 coordinates and round trips`() {
    val wgs84 = LatLng(39.908823, 116.397470)

    val gcj02 = CoordinateConverter.wgs84ToGcj02(wgs84)
    val roundTrip = CoordinateConverter.gcj02ToWgs84(gcj02)

    assertTrue(gcj02.latitude > wgs84.latitude)
    assertTrue(gcj02.longitude > wgs84.longitude)
    assertEquals(wgs84.latitude, roundTrip.latitude, 0.000001)
    assertEquals(wgs84.longitude, roundTrip.longitude, 0.000001)
  }

  @Test
  fun `does not convert coordinates outside mainland China`() {
    val london = LatLng(51.5074, -0.1278)

    assertEquals(london, CoordinateConverter.wgs84ToGcj02(london))
    assertEquals(london, CoordinateConverter.gcj02ToWgs84(london))
  }
}
