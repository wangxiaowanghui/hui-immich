import Foundation
var assertions = 0
func check(_ condition: Bool, _ name: String) {
  precondition(condition, "失败：\(name)")
  assertions += 1
}
let beijing = AmapCoordinate(latitude: 39.908823, longitude: 116.397470)
let gcj = beijing.toGcj02()
check(abs(gcj.latitude - 39.91022649807321) < 1e-8, "国内纬度与 Android/Web 一致")
check(abs(gcj.longitude - 116.4037135824225) < 1e-8, "国内经度与 Android/Web 一致")
for point in [beijing, AmapCoordinate(latitude: 31.2304, longitude: 121.4737), AmapCoordinate(latitude: 22.5431, longitude: 114.0579)] {
  let roundTrip = point.toGcj02().toWgs84()
  check(abs(roundTrip.latitude-point.latitude) < 1e-7 && abs(roundTrip.longitude-point.longitude) < 1e-7, "国内坐标往返")
}
for point in [AmapCoordinate(latitude: 0, longitude: 0), AmapCoordinate(latitude: 37.7749, longitude: -122.4194), AmapCoordinate(latitude: 51.5074, longitude: -0.1278)] {
  check(point.toGcj02() == point && point.toWgs84() == point, "海外坐标保持不变")
}
check(!AmapCoordinate(latitude: .nan, longitude: 1).isValid, "拒绝 NaN")
check(!AmapCoordinate(latitude: 91, longitude: 1).isValid, "拒绝无效纬度")
check(!AmapCoordinate(latitude: 1, longitude: .infinity).isValid, "拒绝无穷值")
check(beijing.isValid, "有效坐标")

let inputs = [
  AmapProjectedPoint(coordinate: beijing, x: 10, y: 20),
  AmapProjectedPoint(coordinate: beijing, x: 20, y: 30),
  AmapProjectedPoint(coordinate: beijing, x: 53, y: 30),
  AmapProjectedPoint(coordinate: beijing, x: -1, y: 30),
  AmapProjectedPoint(coordinate: beijing, x: .infinity, y: 30),
  AmapProjectedPoint(coordinate: beijing, x: 100, y: 30),
]
let groups = AmapClustering.groups(inputs, width: 100, height: 100)
check(groups.count == 2, "52 点网格聚合与视野过滤")
check(groups.map { $0.count } == [2, 1], "聚合计数")
check(groups[0].coordinate == beijing, "重合照片坐标不会偏移")
check(AmapClustering.groups(inputs, width: 0, height: 100).isEmpty, "零尺寸不产生聚合")
check(AmapClustering.groups(inputs, width: 100, height: 10).isEmpty, "横竖屏尺寸变化重新过滤")
print("坐标与聚合测试通过：\(assertions) 项")

check(!AmapLoadPolicy.shouldFallback(NSError(domain: NSURLErrorDomain, code: NSURLErrorCancelled)), "缩放取消旧请求不切换地图提供方")
check(AmapLoadPolicy.shouldFallback(NSError(domain: NSURLErrorDomain, code: NSURLErrorCannotConnectToHost)), "真实连接失败仍回退")
check(AmapLoadPolicy.shouldFallback(NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)), "网络超时仍回退")
check(AmapLoadPolicy.shouldFallback(NSError(domain: "amap.authorization", code: 1001)), "鉴权错误仍回退")
check(AmapLoadPolicy.shouldFallback(NSError(domain: "amap.other", code: NSURLErrorCancelled)), "不忽略其他错误域的同码错误")
check(AmapLoadPolicy.shouldFallback(nil), "未知错误仍回退")
print("坐标、聚合与错误策略测试全部通过：\(assertions) 项")
