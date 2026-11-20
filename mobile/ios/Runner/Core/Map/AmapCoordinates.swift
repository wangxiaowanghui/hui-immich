import Foundation

/// 与 Android/Web 相同的渲染坐标约定；不修改照片的 WGS-84 数据。
struct AmapCoordinate: Equatable {
  let latitude: Double
  let longitude: Double
  var isValid: Bool {
    latitude.isFinite && longitude.isFinite && (-90...90).contains(latitude) && (-180...180).contains(longitude)
  }
  private var outsideChina: Bool {
    longitude < 72.004 || longitude > 137.8347 || latitude < 0.8293 || latitude > 55.8271
  }
  func toGcj02() -> AmapCoordinate {
    guard !outsideChina else { return self }
    let x = longitude - 105, y = latitude - 35, pi = Double.pi
    var lat = -100 + 2*x + 3*y + 0.2*y*y + 0.1*x*y + 0.2*sqrt(abs(x))
    lat += (20*sin(6*x*pi) + 20*sin(2*x*pi))*2/3
    lat += (20*sin(y*pi) + 40*sin(y*pi/3))*2/3
    lat += (160*sin(y*pi/12) + 320*sin(y*pi/30))*2/3
    var lon = 300 + x + 2*y + 0.1*x*x + 0.1*x*y + 0.1*sqrt(abs(x))
    lon += (20*sin(6*x*pi) + 20*sin(2*x*pi))*2/3
    lon += (20*sin(x*pi) + 40*sin(x*pi/3))*2/3
    lon += (150*sin(x*pi/12) + 300*sin(x*pi/30))*2/3
    let rad = latitude*pi/180, a = 6378245.0, ee = 0.006693421622965943
    let magic = 1 - ee*sin(rad)*sin(rad), root = sqrt(magic)
    lat = lat*180 / ((a*(1-ee))/(magic*root)*pi)
    lon = lon*180 / (a/root*cos(rad)*pi)
    return AmapCoordinate(latitude: latitude + lat, longitude: longitude + lon)
  }
  func toWgs84() -> AmapCoordinate {
    guard !outsideChina else { return self }
    var estimate = self
    for _ in 0..<3 {
      let projected = estimate.toGcj02()
      estimate = AmapCoordinate(latitude: estimate.latitude - projected.latitude + latitude,
                                longitude: estimate.longitude - projected.longitude + longitude)
    }
    return estimate
  }
  var message: [String: Double] { ["latitude": latitude, "longitude": longitude] }
}

struct AmapProjectedPoint {
  let coordinate: AmapCoordinate
  let x: Double
  let y: Double
}
struct AmapCluster {
  let coordinate: AmapCoordinate
  let count: Int
}
enum AmapClustering {
  /// 屏幕网格使用逻辑点，不随 iPad 像素密度改变；只聚合当前可见点。
  static func groups(_ points: [AmapProjectedPoint], width: Double, height: Double) -> [AmapCluster] {
    guard width.isFinite, height.isFinite, width > 0, height > 0 else { return [] }
    var cells: [String: [AmapCoordinate]] = [:]
    for point in points {
      guard point.coordinate.isValid, point.x.isFinite, point.y.isFinite,
            point.x >= 0, point.x < width, point.y >= 0, point.y < height else { continue }
      let key = "\(Int(floor(point.x/52))):\(Int(floor(point.y/52)))"
      cells[key, default: []].append(point.coordinate)
    }
    return cells.keys.sorted().map { key in
      let group = cells[key]!, count = Double(cells[key]!.count)
      return AmapCluster(coordinate: AmapCoordinate(
        latitude: group.reduce(0) { $0 + $1.latitude }/count,
        longitude: group.reduce(0) { $0 + $1.longitude }/count), count: group.count)
    }
  }
}
