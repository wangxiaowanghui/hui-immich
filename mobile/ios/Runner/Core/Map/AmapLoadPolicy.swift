import Foundation

/// 只忽略视野变化产生的请求取消；真正的连接、鉴权和未知错误仍触发回退。
enum AmapLoadPolicy {
  static func shouldFallback(_ error: NSError?) -> Bool {
    guard let error else { return true }
    return error.domain != NSURLErrorDomain || error.code != NSURLErrorCancelled
  }
}
