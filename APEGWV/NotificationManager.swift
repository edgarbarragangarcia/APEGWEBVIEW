//
//  NotificationManager.swift
//  APEGWV
//
//  Created by Antigravity
//

import Foundation
import Combine
import UserNotifications
import UIKit

class NotificationManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    
    @Published var authorizationStatus: UNAuthorizationStatus = .notDetermined
    @Published var deviceToken: String?
    
    var onStatusChange: (() -> Void)?
    var onTokenReceived: ((String) -> Void)?
    
    override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
        checkAuthorizationStatus()
    }
    
    func checkAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.authorizationStatus = settings.authorizationStatus
                self.onStatusChange?()
            }
        }
    }
    
    func requestAuthorization(completion: ((Bool) -> Void)? = nil) {
        // Si ya está autorizado no hacer nada
        if authorizationStatus == .authorized {
            completion?(true)
            registerForRemoteNotifications()
            return
        }
        
        if authorizationStatus == .denied {
            completion?(false)
            return
        }
        
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                self.authorizationStatus = granted ? .authorized : .denied
                self.onStatusChange?()
                
                if granted {
                    self.registerForRemoteNotifications()
                }
                
                completion?(granted)
            }
        }
    }
    
    private func registerForRemoteNotifications() {
        DispatchQueue.main.async {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
    
    func setDeviceToken(_ token: Data) {
        let tokenString = token.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = tokenString
        self.onTokenReceived?(tokenString)
    }
    
    func getStatusJSON() -> String {
        let status: [String: Any] = [
            "authorized": authorizationStatus == .authorized,
            "status": stringFromAuthStatus(authorizationStatus),
            "deviceToken": deviceToken ?? NSNull()
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: status, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }
    
    private func stringFromAuthStatus(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied: return "denied"
        case .provisional: return "provisional"
        case .ephemeral: return "ephemeral"
        default: return "notDetermined"
        }
    }
    
    // MARK: - UNUserNotificationCenterDelegate
    
    // Handle notification when app is in foreground
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        // Show banner and play sound even when app is in foreground
        completionHandler([.banner, .sound, .badge])
    }
    
    // Handle notification tap (when user taps on notification)
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        
        // Send notification data to web via JavaScript
        if let jsonData = try? JSONSerialization.data(withJSONObject: userInfo, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            // We'll need to call this via a shared webview reference
            NotificationCenter.default.post(
                name: NSNotification.Name("NotificationTapped"),
                object: nil,
                userInfo: ["data": jsonString]
            )
        }
        
        completionHandler()
    }
}
