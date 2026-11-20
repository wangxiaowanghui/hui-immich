import Flutter
import UIKit
import MAMapKit
import AMapFoundationKit

final class AmapMapPlugin: NSObject, FlutterPlugin {
  static var configuredKey: String? {
    guard let key = Bundle.main.object(forInfoDictionaryKey: "AMapApiKey") as? String,
          key.range(of: "^[0-9a-fA-F]{32}$", options: .regularExpression) != nil,
          let expected = Bundle.main.object(forInfoDictionaryKey: "AMapBundleId") as? String,
          expected == Bundle.main.bundleIdentifier else { return nil }
    return key
  }
  static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterMethodChannel(name: "immich/amap_config", binaryMessenger: registrar.messenger())
    registrar.addMethodCallDelegate(AmapMapPlugin(), channel: channel)
    registrar.register(AmapMapFactory(messenger: registrar.messenger()), withId: "immich/amap")
  }
  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    result(call.method == "isConfigured" ? Self.configuredKey != nil : FlutterMethodNotImplemented)
  }
}

private final class AmapMapFactory: NSObject, FlutterPlatformViewFactory {
  let messenger: FlutterBinaryMessenger
  init(messenger: FlutterBinaryMessenger) { self.messenger = messenger }
  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol { FlutterStandardMessageCodec.sharedInstance() }
  func create(withFrame frame: CGRect, viewIdentifier viewId: Int64, arguments args: Any?) -> FlutterPlatformView {
    AmapMapView(frame: frame, id: viewId, arguments: args as? [String: Any] ?? [:], messenger: messenger)
  }
}

private final class AmapContainer: UIView {
  var onResize: (() -> Void)?
  private var previousSize = CGSize.zero
  override func layoutSubviews() {
    super.layoutSubviews()
    if bounds.size != previousSize {
      previousSize = bounds.size
      onResize?()
    }
  }
}

private final class AmapAnnotation: NSObject, MAAnnotation {
  @objc dynamic var coordinate: CLLocationCoordinate2D
  let count: Int
  let isPin: Bool
  init(coordinate: CLLocationCoordinate2D, count: Int = 1, isPin: Bool = false) {
    self.coordinate = coordinate; self.count = count; self.isPin = isPin
  }
}

private final class AmapMapView: NSObject, FlutterPlatformView, MAMapViewDelegate {
  private let container: AmapContainer
  private let channel: FlutterMethodChannel
  private var map: MAMapView?
  private let approval = UILabel()
  private var points: [AmapCoordinate] = []
  private var annotations: [AmapAnnotation] = []
  private var pin: AmapAnnotation?
  private var connected = false
  private var loaded = false
  private var failed = false
  private var disposed = false
  private var fitted = false
  private let autoFit: Bool
  private let selectOnTap: Bool

  init(frame: CGRect, id: Int64, arguments: [String: Any], messenger: FlutterBinaryMessenger) {
    container = AmapContainer(frame: frame)
    channel = FlutterMethodChannel(name: "immich/amap_\(id)", binaryMessenger: messenger)
    autoFit = arguments["autoFitMarkers"] as? Bool ?? false
    selectOnTap = arguments["selectOnTap"] as? Bool ?? false
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self, !self.disposed else {
        result(FlutterError(code: "map_disposed", message: "地图已释放", details: nil)); return
      }
      self.handle(call, result: result)
    }
    // 配置检查与隐私选择必须先于创建任何高德实例。
    guard arguments["privacyAccepted"] as? Bool == true, let key = AmapMapPlugin.configuredKey else {
      failed = true; return
    }
    MAMapView.updatePrivacyShow(.didShow, privacyInfo: .didContain)
    MAMapView.updatePrivacyAgree(.didAgree)
    AMapServices.shared().apiKey = key
    AMapServices.shared().enableHTTPS = true
    AMapServices.shared().regionLanguageType = .zhHans
    let native = MAMapView(frame: container.bounds)
    map = native
    native.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    native.delegate = self
    native.showsUserLocation = false
    native.isRotateEnabled = false
    native.isRotateCameraEnabled = false
    native.showsCompass = false
    native.showsScale = true
    native.isZoomEnabled = arguments["interactive"] as? Bool ?? true
    native.isScrollEnabled = native.isZoomEnabled
    native.touchPOIEnabled = false
    native.mapType = arguments["darkMode"] as? Bool == true ? .standardNight : .standard
    if let initial = Self.point(arguments) {
      native.setCenter(initial.toGcj02().clLocation, animated: false)
    }
    native.setZoomLevel(CGFloat(Self.zoom(arguments["zoom"] as? Double ?? 3)), animated: false)
    container.addSubview(native)
    // 高德 Logo 由 SDK 保留；额外展示审图号，不受缩略图 attribution 开关影响。
    approval.font = .systemFont(ofSize: 8)
    approval.numberOfLines = 0
    approval.textAlignment = .right
    approval.textColor = .darkGray
    approval.backgroundColor = UIColor.white.withAlphaComponent(0.85)
    approval.translatesAutoresizingMaskIntoConstraints = false
    container.addSubview(approval)
    NSLayoutConstraint.activate([
      approval.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -4),
      approval.leadingAnchor.constraint(greaterThanOrEqualTo: container.leadingAnchor, constant: 4),
      approval.topAnchor.constraint(equalTo: container.safeAreaLayoutGuide.topAnchor, constant: 4),
    ])
    if arguments["showMarkerPin"] as? Bool == true, let initial = Self.point(arguments) { setPin(initial) }
    container.onResize = { [weak self] in
      DispatchQueue.main.async { [weak self] in self?.cameraIdle() }
    }
  }
  func view() -> UIView { container }
  deinit { disposeMap() }

  private func disposeMap() {
    guard !disposed else { return }
    disposed = true
    channel.setMethodCallHandler(nil)
    container.onResize = nil
    map?.delegate = nil
    map?.showsUserLocation = false
    map?.removeFromSuperview()
    map = nil
    points = []; annotations = []; pin = nil
  }
  private static func point(_ args: [String: Any]) -> AmapCoordinate? {
    guard let lat = args["latitude"] as? Double, let lon = args["longitude"] as? Double else { return nil }
    let point = AmapCoordinate(latitude: lat, longitude: lon)
    return point.isValid ? point : nil
  }
  private static func zoom(_ value: Double) -> Double { value.isFinite ? min(18, max(3, value)) : 3 }
  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if call.method == "dispose" { disposeMap(); result(nil); return }
    if call.method == "initialize" {
      connected = true
      result(nil)
      DispatchQueue.main.async { [weak self] in
        guard let self else { return }
        if self.failed { self.emitFailure() }
        else if self.loaded { self.emitReady() }
      }
      return
    }
    guard let map, !failed else {
      result(FlutterError(code: "map_unavailable", message: "高德地图不可用", details: nil)); return
    }
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "setMarkers":
      points = (args["markers"] as? [[String: Any]] ?? []).compactMap(Self.point).map { $0.toGcj02() }
      if autoFit && !fitted && !points.isEmpty {
        fitted = true
        let all = points.map { AmapAnnotation(coordinate: $0.clLocation) }
        map.showAnnotations(all, edgePadding: UIEdgeInsets(top: 50, left: 50, bottom: 50, right: 50), animated: false)
        if map.zoomLevel > 15 { map.setZoomLevel(15, animated: false) }
      }
      refreshMarkers(); result(nil)
    case "moveCamera", "setPin":
      guard let point = Self.point(args) else {
        result(FlutterError(code: "invalid_coordinate", message: "坐标无效", details: nil)); return
      }
      if call.method == "setPin" { setPin(point) }
      else {
        let animated = args["animated"] as? Bool ?? true
        if let zoom = args["zoom"] as? Double { map.setZoomLevel(CGFloat(Self.zoom(zoom)), animated: animated) }
        map.setCenter(point.toGcj02().clLocation, animated: animated)
      }
      result(nil)
    case "setDarkMode":
      map.mapType = args["darkMode"] as? Bool == true ? .standardNight : .standard
      result(nil)
    case "getVisibleRegion": result(visibleRegion())
    default: result(FlutterMethodNotImplemented)
    }
  }
  private func setPin(_ wgs84: AmapCoordinate) {
    guard let map else { return }
    if let pin { map.removeAnnotation(pin) }
    let annotation = AmapAnnotation(coordinate: wgs84.toGcj02().clLocation, isPin: true)
    pin = annotation
    map.addAnnotation(annotation)
  }
  private func visibleRegion() -> [String: [String: Double]]? {
    guard let map, map.bounds.width > 0, map.bounds.height > 0 else { return nil }
    let sw = map.convert(CGPoint(x: 0, y: map.bounds.height), toCoordinateFrom: map)
    let ne = map.convert(CGPoint(x: map.bounds.width, y: 0), toCoordinateFrom: map)
    return ["southwest": AmapCoordinate(sw).toWgs84().message, "northeast": AmapCoordinate(ne).toWgs84().message]
  }
  private func refreshMarkers() {
    guard let map, loaded, !disposed else { return }
    map.removeAnnotations(annotations)
    annotations = []
    let projected = points.map { point -> AmapProjectedPoint in
      let pixel = map.convert(point.clLocation, toPointTo: map)
      return AmapProjectedPoint(coordinate: point, x: Double(pixel.x), y: Double(pixel.y))
    }
    annotations = AmapClustering.groups(projected, width: Double(map.bounds.width), height: Double(map.bounds.height))
      .map { AmapAnnotation(coordinate: $0.coordinate.clLocation, count: $0.count) }
    map.addAnnotations(annotations)
  }
  private func emitReady() {
    guard connected, !failed, !disposed else { return }
    channel.invokeMethod("onMapReady", arguments: nil)
    cameraIdle()
  }
  private func emitFailure() {
    failed = true
    guard connected, !disposed else { return }
    // 不转发 SDK 错误字符串，防止其中夹带 Key 或请求 URL。
    channel.invokeMethod("onMapError", arguments: ["code": "ios_map_unavailable"])
  }
  private func cameraIdle() {
    guard loaded, !failed, !disposed else { return }
    refreshMarkers()
    if connected, let region = visibleRegion() { channel.invokeMethod("onCameraIdle", arguments: region) }
  }
  func mapViewDidFinishLoadingMap(_ mapView: MAMapView!) {
    guard !loaded else { return }
    loaded = true
    approval.text = mapView.mapContentApprovalNumber()
    emitReady()
  }
  func mapViewDidFailLoadingMap(_ mapView: MAMapView!, withError error: Error!) {
    // 缩放会取消旧瓦片请求；取消不是初始化或鉴权失败，保留当前地图及加载超时兜底。
    guard AmapLoadPolicy.shouldFallback(error as NSError?) else { return }
    emitFailure()
  }
  func mapView(_ mapView: MAMapView!, regionDidChangeAnimated animated: Bool) { cameraIdle() }
  func mapView(_ mapView: MAMapView!, didSingleTappedAt coordinate: CLLocationCoordinate2D) {
    guard connected, !failed else { return }
    let wgs84 = AmapCoordinate(coordinate).toWgs84()
    if selectOnTap { setPin(wgs84) }
    channel.invokeMethod("onMapClick", arguments: wgs84.message)
  }
  func mapView(_ mapView: MAMapView!, viewFor annotation: MAAnnotation!) -> MAAnnotationView! {
    guard let item = annotation as? AmapAnnotation else { return nil }
    let view = MAAnnotationView(annotation: item, reuseIdentifier: "immich-marker")!
    let size: CGFloat = item.isPin ? 26 : item.count > 1 ? 40 : 18
    view.image = UIGraphicsImageRenderer(size: CGSize(width: size, height: size)).image { ctx in
      let rect = CGRect(x: 1, y: 1, width: size-2, height: size-2)
      (item.isPin ? UIColor.systemTeal : UIColor(red: 0.25, green: 0.32, blue: 0.71, alpha: 1)).setFill()
      ctx.cgContext.fillEllipse(in: rect)
      UIColor.white.setStroke(); ctx.cgContext.setLineWidth(2); ctx.cgContext.strokeEllipse(in: rect)
      if item.count > 1 {
        let text = "\(item.count)" as NSString
        let attributes: [NSAttributedString.Key: Any] = [.font: UIFont.boldSystemFont(ofSize: 13), .foregroundColor: UIColor.white]
        let textSize = text.size(withAttributes: attributes)
        text.draw(at: CGPoint(x: (size-textSize.width)/2, y: (size-textSize.height)/2), withAttributes: attributes)
      }
    }
    view.canShowCallout = false
    return view
  }
  func mapView(_ mapView: MAMapView!, didSelect view: MAAnnotationView!) {
    guard let item = view.annotation as? AmapAnnotation, !item.isPin else { return }
    mapView.deselectAnnotation(item, animated: false)
    if item.count > 1 {
      mapView.setCenter(item.coordinate, animated: true)
      mapView.setZoomLevel(min(mapView.zoomLevel+2, 18), animated: true)
    }
  }
}

private extension AmapCoordinate {
  init(_ point: CLLocationCoordinate2D) { self.init(latitude: point.latitude, longitude: point.longitude) }
  var clLocation: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}
