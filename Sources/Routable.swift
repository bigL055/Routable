//
//  Router.swift
//  Router
//
//  Created by BigL on 2017/3/21.
//  Copyright © 2017年 fun.bigl.com. All rights reserved.
//

import Foundation
import UIKit

public struct Routable {
  /// 命名空间
  fileprivate static let namespace = Bundle.main.infoDictionary?["CFBundleExecutable"] as! String
  /// 类名前缀
  public static var classPrefix = "Router_"
  /// 方法名前缀
  public static var funcPrefix = "router_"
  /// 参数名
  public static var paramName = "Params"
  /// 指定协议头, ""则为任意格式
  public static var scheme = ""
  /// 缓存
  static var cache = [String: Any]()
  /// 通知缓存
  static var notice = [String:[String]]()
  /// 代理缓存
  static var delegate = [String: String]()
  
  static var blockCache = [String: (_: [String: Any])->()]()
  
}

public extension Routable {
  
  /// 解析viewController类型
  ///
  /// - Parameter url: viewController 路径
  /// - Returns: viewController 或者 nil
  public static func viewController(url: URLProtocol,params:[String: Any] = [:]) -> UIViewController? {
    if let vc = object(url: url, params: params) as UIViewController? { return vc }
    return nil
  }
  
  
  public static func object(url: URLProtocol, params:[String: Any] = [:], call: @escaping (_: [String: Any])->()) {
    guard let path = urlFormat(url: url, params: params) else { return }
    guard let value = getPathValues(url: path) else { return }
    let id = "blockCache\(blockCache.count)"
    blockCache[id] = call
    _ = target(name: value.class, actionName: value.function, params: value.params, callId: id)
  }
  
  public static func runBlock(id:String, params:[String: Any] = [:],isRemove: Bool = true) {
    blockCache[id]?(params)
    if isRemove { blockCache[id] = nil }
  }
  
  /// 解析view类型
  ///
  /// - Parameter url: view 路径
  /// - Returns: view 或者 nil
  public static func view(url: URLProtocol,params:[String: Any] = [:]) -> UIView? {
    if let vc = object(url: url, params: params) as UIView? { return vc }
    return nil
  }
  
  /// 解析AnyObject类型
  ///
  /// - Parameter url: view 路径
  /// - Returns: view 或者 nil
  public static func object<T: Any>(url: URLProtocol,params:[String: Any] = [:]) -> T? {
    guard let path = urlFormat(url: url, params: params) else { return nil }
    guard let value = getPathValues(url: path) else { return nil }
    guard let result = target(name: value.class, actionName: value.function, params: value.params) else { return nil }
    switch result.type {
    case .void: return nil
    case .object:
      return result.unmanaged.takeUnretainedValue() as? T
    case .longlong,.point,.int:
      return result.unmanaged.toOpaque().hashValue as? T
    case .double:
//     let element = result.unmanaged.toOpaque().assumingMemoryBound(to: Double.self)
//     return element.pointee as? T
      return nil
    default: return nil
    }
  }
  
  /// 通知所有已缓存类型函数
  ///
  /// - Parameter url: 函数路径
  public static func notice(url: URLProtocol,params:[String: Any] = [:]) {
    guard let path = urlFormat(url: url, params: params) else { return }
    if path.host != "notice" {
      assert(false, "检查 URL host: " + (path.host ?? "") + "🌰: http://notice/path")
      return
    }
    
    cache.keys.forEach({ (item) in
      //TODO: 不太严谨
      let name = item.replacingOccurrences(of: classPrefix, with: "")
      let path = path.asString().replacingOccurrences(of: "://notice/", with: "://\(name)/")
      if let endURL = path.asURL() {
        _ = object(url: endURL) as Any?
      }
    })
  }
  
  
  /// 执行路径指定函数
  ///
  /// - Parameter url: 函数路径
  public static func executing(url: URLProtocol, params:[String: Any] = [:]) {
    _ = object(url: url, params: params) as Any?
  }
  
}

public extension Routable {
  
  /// 清除指定缓存
  ///
  /// - Parameter name: key
  public static func cache(remove name: String) {
    let targetName = classPrefix + name
    cache.removeValue(forKey: targetName)
  }
  
  public static func urlFormat(url: URLProtocol,params:[String: Any]) -> URL?{
    if params.isEmpty { return url.asURL() }
    guard var components = URLComponents(string: url.asString()) else { return nil }
    var querys = components.queryItems ?? []
    let newQuerys = params.map { (item) -> URLQueryItem in
      switch item.value {
      case let v as String:
        return URLQueryItem(name: item.key, value: v)
      case let v as [String:Any]:
        return URLQueryItem(name: item.key, value: RoutableHelp.formatJSON(data: v))
      case let v as [Any]:
        return URLQueryItem(name: item.key, value: RoutableHelp.formatJSON(data: v))
      default:
        return URLQueryItem(name: item.key, value: String(describing: item.value))
      }
    }
    querys += newQuerys
    components.queryItems = querys
    return components.url
  }
  
}

extension Routable {
  
  /// 获取类对象
  ///
  /// - Parameter name: 类名
  /// - Returns: 类对象
  static func getClass(name: String) -> NSObject? {
    func target(name: String) -> NSObject? {
      if let targetClass = cache[name] as? NSObject { return targetClass }
      guard let targetClass = NSClassFromString(name) as? NSObject.Type else { return nil }
      let target = targetClass.init()
      cache[name] = target
      return target
    }
    
    if let value = target(name: classPrefix + name) { return value }
    if let value = target(name: namespace + "." + classPrefix + name) { return value }
    return nil
  }
  
  struct Function {
    /// 函数
    let sel: Selector
    /// 函数参数数量
    let argumentCount: UInt32
    /// 返回值类型
    let returnType: ObjectType
    /// 参数类型数组
    let argumentTypes: [ObjectType]
  }
  
  struct Result {
    /// 返回值
    let unmanaged: Unmanaged<AnyObject>
    /// 返回值类型
    let type: ObjectType
  }
  
  /// 获取指定类指定函数
  ///
  /// - Parameters:
  ///   - target: 指定类
  ///   - name: 指定函数名
  /// - Returns: 指定函数
  static func getSEL(target: NSObject, name: String) -> Function? {
    var methodNum: UInt32 = 0
    let methods = class_copyMethodList(type(of: target), &methodNum)
    for index in 0..<numericCast(methodNum) {
      guard let method = methods?[index] else { continue }
      let sel: Selector = method_getName(method)
      let description = sel.description.replacingOccurrences(of: "With" + paramName, with: ":") + ":"
      if !description.hasPrefix(funcPrefix + name + ":") { continue }
      free(methods)
      var dst: CChar = 0
      method_getReturnType(method, &dst, MemoryLayout<CChar>.size)
      let returnType = ObjectType(char: dst)
      
      let argumentsCount = method_getNumberOfArguments(method)
      let types = (0..<UInt32(argumentsCount)).map({ (index) -> ObjectType in
         method_getArgumentType(method,index,&dst,MemoryLayout<CChar>.size)
        return ObjectType(char: dst)
      })
      
      return Function(sel: sel,
                      argumentCount: argumentsCount - 2,
                      returnType: returnType,
                      argumentTypes: types)
    }
    free(methods)
    return nil
  }
  
  /// 获取指定对象
  ///
  /// - Parameters:
  ///   - name: 类名
  ///   - actionName: 函数名
  ///   - params: 函数参数
  ///   - isCacheTarget: 是否缓存
  /// - Returns: 对象
   static func target(name: String, actionName: String, params: [String: Any] = [:], callId: String = "") -> Result? {
    guard let target = getClass(name: name) else { return nil }
    guard let function = getSEL(target: target, name: actionName) else { return nil }
    switch function.argumentCount {
    case 0:
      guard let value = target.perform(function.sel) else { return nil }
      return Result(unmanaged: value, type: function.returnType)
    case 1:
      guard let value = target.perform(function.sel, with: params) else { return nil }
      return Result(unmanaged: value, type: function.returnType)
    case 2:
      guard let value = target.perform(function.sel, with: params, with: callId) else { return nil }
      return Result(unmanaged: value, type: function.returnType)
    default:
      assert(false)
      return nil
    }
  }
  
  /// 获取路径所需参数
  ///
  /// - Parameter url: 路径
  /// - Returns: 所需参数
  static func getPathValues(url: URL) -> (class: String,function: String,params: [String: Any])?{
    /// 处理参数类型
    ///
    /// - Parameter string: 需要处理的参数字符
    /// - Returns: 处理后类型
    func dealValueType(string: String?) -> Any? {
      guard var str = string?.removingPercentEncoding else { return string }
      guard !str.isEmpty else { return str }
      str = str.trimmingCharacters(in: CharacterSet.whitespaces)
      guard str.hasPrefix("[") || str.hasPrefix("{") else { return str }
      let dict = RoutableHelp.dictionary(string: str)
      if !dict.isEmpty { return dict }
      let array = RoutableHelp.array(string: str)
      if !array.isEmpty { return array }
      return str
    }
    
    /// 处理协议头合法
    guard (scheme.isEmpty || url.scheme == scheme),
      let function = url.path.components(separatedBy: "/").last,
      let className = url.host else { return nil }
    
    /// 处理参数
    var params = [String: Any]()
    if let urlstr = url.query {
      urlstr.components(separatedBy: "&").forEach { (item) in
        let list = item.components(separatedBy: "=")
        if list.count == 2 {
          params[list.first!] = dealValueType(string: list.last)
        }else if list.count > 2 {
          params[list.first!] = dealValueType(string: list.dropFirst().joined())
        }
      }
    }
    
    return (className,function,params)
  }
  
}





