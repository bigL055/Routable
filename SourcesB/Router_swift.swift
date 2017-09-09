//
//  Router_b.swift
//  Routable
//
//  Created by BigL on 2017/9/8.
//  Copyright © 2017年 CocoaPods. All rights reserved.
//

import UIKit

@objc(Router_swift)
class Router_swift: NSObject {

  func router_a(params:[String: Any]) -> UIViewController {
    let vc = UIViewController()
    vc.view.backgroundColor = UIColor.blue
    return vc
  }

  func router_b() -> UIViewController {
    let vc = UIViewController()
    vc.view.backgroundColor = UIColor.red
    return vc
  }

  func router_c(params: [String: Any] = [:]) {
    print(#function)
  }

}
