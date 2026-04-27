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
    @State private var showSplashScreen = true
    
    var body: some Scene {
        WindowGroup {
            ZStack {
                // WebView always underneath, ready
                ContentView()
                    .opacity(showSplashScreen ? 0 : 1)
                
                // Splash on top
                if showSplashScreen {
                    SplashScreenView(isFinished: $showSplashScreen)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.6), value: showSplashScreen)
        }
    }
}

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .portrait
    }
    
    // MARK: - Remote Notifications
    
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        NotificationManager.shared.setDeviceToken(deviceToken)
    }
    
    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Failed to register for remote notifications: \(error.localizedDescription)")
    }
    
    // Handle remote notification received when app is in background
    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        completionHandler(.newData)
    }
}
