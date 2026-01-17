//
//  APEGWVApp.swift
//  APEGWV
//
//  Created by Edgar A. Barragán G. on 15/01/26.
//

import SwiftUI

@main
struct APEGWVApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
}
