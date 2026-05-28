//
//  WebView.swift
//  APEGWV
//
//  Created by Edgar A. Barragán G. on 15/01/26.
//

import SwiftUI
import WebKit
import AVFoundation
import CoreLocation

struct WebView: UIViewRepresentable {
    let url: URL
    let permissionManager = PermissionManager.shared
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.websiteDataStore = .default()
        
        // Setup User Content Controller for Bridge
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "permissionHandler")
        controller.add(context.coordinator, name: "notificationHandler")
        controller.add(context.coordinator, name: "sensorHandler")
        controller.add(context.coordinator, name: "cardScannerHandler")
        
        let initialStatuses = permissionManager.getStatusesJSON()
        
        // Inject Script to expose permission status and polyfill APIs
        let scriptSource = """
            window.iOSPermissionStatuses = \(initialStatuses);
            
            window.iOSPermissions = {
                getStatuses: function() {
                    window.webkit.messageHandlers.permissionHandler.postMessage({command: 'getStatuses'});
                },
                request: function(type) {
                    window.webkit.messageHandlers.permissionHandler.postMessage({command: 'request', type: type});
                }
            };
            
            window.iOSNotifications = {
                request: function() {
                    window.webkit.messageHandlers.notificationHandler.postMessage({command: 'request'});
                },
                getStatus: function() {
                    window.webkit.messageHandlers.notificationHandler.postMessage({command: 'getStatus'});
                },
                schedule: function(options) {
                    var opts = options || {};
                    window.webkit.messageHandlers.notificationHandler.postMessage({
                        command: 'schedule',
                        title: opts.title || '',
                        body: opts.body || '',
                        delay: opts.delay || 1,
                        data: opts.data || {}
                    });
                },
                clearBadge: function() {
                    window.webkit.messageHandlers.notificationHandler.postMessage({command: 'clearBadge'});
                }
            };
            
            window.iOSSensors = {
                start: function(interval) {
                    window.webkit.messageHandlers.sensorHandler.postMessage({command: 'start', interval: interval || 0.1});
                },
                stop: function() {
                    window.webkit.messageHandlers.sensorHandler.postMessage({command: 'stop'});
                }
            };
            
            window.iOSCardScanner = {
                scan: function() {
                    window.webkit.messageHandlers.cardScannerHandler.postMessage({command: 'scan'});
                }
            };
            
            // Polyfill navigator.permissions.query
            if (navigator.permissions && navigator.permissions.query) {
                const originalQuery = navigator.permissions.query.bind(navigator.permissions);
                navigator.permissions.query = async function(descriptor) {
                    const status = window.iOSPermissionStatuses;
                    if (status) {
                        if (descriptor.name === 'camera' && status.camera === 'authorized') return { state: 'granted' };
                        if (descriptor.name === 'geolocation' && status.location === 'authorized') return { state: 'granted' };
                        if (descriptor.name === 'microphone' && status.camera === 'authorized') return { state: 'granted' };
                    }
                    return originalQuery(descriptor);
                };
            }
            
            // Notification handler
            window.onPermissionUpdate = function(statuses) {
                window.iOSPermissionStatuses = statuses;
                window.dispatchEvent(new CustomEvent('iosPermissionsUpdated', { detail: statuses }));
            };
            
            // Auto-refresh fallback
            setInterval(() => {
                window.iOSPermissions.getStatuses();
            }, 3000);
        """
        let script = WKUserScript(source: scriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        controller.addUserScript(script)
        
        configuration.userContentController = controller
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.uiDelegate = context.coordinator
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        
        // Start GPS if authorized
        if permissionManager.locationStatus == CLAuthorizationStatus.authorizedWhenInUse || permissionManager.locationStatus == CLAuthorizationStatus.authorizedAlways {
            permissionManager.requestLocationPermission() // This starts updates
        }
        
        // Listen for notification taps
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleNotificationTap(_:)),
            name: NSNotification.Name("NotificationTapped"),
            object: nil
        )
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        uiView.load(request)
    }
    
    class Coordinator: NSObject, WKUIDelegate, WKNavigationDelegate, WKScriptMessageHandler {
        var parent: WebView
        weak var webView: WKWebView?
        
        init(_ parent: WebView) {
            self.parent = parent
            super.init()
            self.parent.permissionManager.onStatusChange = { [weak self] in
                self?.sendStatusesToWeb()
            }
            
            // Sensor updates
            SensorManager.shared.onSensorUpdate = { [weak self] data in
                self?.sendSensorData(data)
            }
            
            // Notification token
            NotificationManager.shared.onTokenReceived = { [weak self] token in
                self?.sendNotificationToken(token)
            }
        }
        
        // Handle messages from JavaScript
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any],
                  let command = dict["command"] as? String else { return }
            
            switch message.name {
            case "permissionHandler":
                handlePermissionMessage(command: command, dict: dict)
            case "notificationHandler":
                handleNotificationMessage(command: command, dict: dict)
            case "sensorHandler":
                handleSensorMessage(command: command, dict: dict)
            case "cardScannerHandler":
                handleCardScannerMessage(command: command)
            default:
                break
            }
        }
        
        // MARK: - Permission Messages
        private func handlePermissionMessage(command: String, dict: [String: Any]) {
            switch command {
            case "getStatuses":
                sendStatusesToWeb()
            case "request":
                if let type = dict["type"] as? String {
                    handleRequest(type: type)
                }
            default:
                break
            }
        }
        
        private func handleRequest(type: String) {
            switch type {
            case "camera":
                parent.permissionManager.requestCameraPermission { _ in
                    self.sendStatusesToWeb()
                }
            case "location":
                parent.permissionManager.requestLocationPermission()
            case "motion":
                parent.permissionManager.requestMotionPermission()
            default:
                break
            }
        }
        
        // MARK: - Notification Messages
        private func handleNotificationMessage(command: String, dict: [String: Any]) {
            switch command {
            case "request":
                NotificationManager.shared.requestAuthorization { granted in
                    self.sendStatusesToWeb()
                }
            case "getStatus":
                let json = NotificationManager.shared.getStatusJSON()
                let js = "if (window.onNotificationStatusUpdate) { window.onNotificationStatusUpdate(\(json)); }"
                webView?.evaluateJavaScript(js, completionHandler: nil)
            case "schedule":
                let title = dict["title"] as? String ?? ""
                let body = dict["body"] as? String ?? ""
                let delay = dict["delay"] as? Double ?? 1.0
                let data = dict["data"] as? [String: Any]
                NotificationManager.shared.scheduleLocalNotification(
                    title: title,
                    body: body,
                    delaySeconds: delay,
                    data: data
                )
            case "clearBadge":
                NotificationManager.shared.clearBadge()
            default:
                break
            }
        }
        
        // MARK: - Sensor Messages
        private func handleSensorMessage(command: String, dict: [String: Any]) {
            switch command {
            case "start":
                let interval = dict["interval"] as? Double ?? 0.1
                SensorManager.shared.startSensors(updateInterval: interval)
            case "stop":
                SensorManager.shared.stopSensors()
            default:
                break
            }
        }
        
        // MARK: - Card Scanner
        private func handleCardScannerMessage(command: String) {
            guard command == "scan" else { return }
            DispatchQueue.main.async {
                guard let topVC = UIApplication.shared.topMostViewController() else { return }
                let scanner = CardScannerViewController()
                scanner.modalPresentationStyle = .fullScreen
                scanner.onCardScanned = { [weak self] number, expiry, name in
                    let result: [String: Any] = [
                        "number": number,
                        "expiry": expiry ?? "",
                        "name": name ?? ""
                    ]
                    if let jsonData = try? JSONSerialization.data(withJSONObject: result, options: []),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        let js = "if (window.onCardScanned) { window.onCardScanned(\(jsonString)); }"
                        self?.webView?.evaluateJavaScript(js, completionHandler: nil)
                    }
                }
                topVC.present(scanner, animated: true)
            }
        }
        
        // MARK: - Send Data to Web
        func sendStatusesToWeb() {
            let json = parent.permissionManager.getStatusesJSON()
            let js = "if (window.onPermissionUpdate) { window.onPermissionUpdate(\(json)); }"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
        
        private func sendSensorData(_ data: [String: Any]) {
            if let jsonData = try? JSONSerialization.data(withJSONObject: data, options: []),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                let js = "if (window.onSensorUpdate) { window.onSensorUpdate(\(jsonString)); }"
                webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }
        
        private func sendNotificationToken(_ token: String) {
            let js = "if (window.onDeviceTokenReceived) { window.onDeviceTokenReceived('\(token)'); }"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
        
        @objc func handleNotificationTap(_ notification: Notification) {
            if let data = notification.userInfo?["data"] as? String {
                let js = "if (window.onNotificationTapped) { window.onNotificationTapped(\(data)); }"
                webView?.evaluateJavaScript(js, completionHandler: nil)
            }
        }
        
        // MARK: - WKUIDelegate (Camera/Media Permissions)
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, decideMediaCapturePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            let cameraAuth = AVCaptureDevice.authorizationStatus(for: .video)
            let micAuth = AVCaptureDevice.authorizationStatus(for: .audio)
            
            if type == .camera && cameraAuth == .authorized {
                decisionHandler(.grant)
            } else if type == .microphone && micAuth == .authorized {
                decisionHandler(.grant)
            } else if type == .cameraAndMicrophone && cameraAuth == .authorized && micAuth == .authorized {
                decisionHandler(.grant)
            } else {
                decisionHandler(.prompt)
            }
        }
        
        // MARK: - WKNavigationDelegate (Handle external links)
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            if let url = navigationAction.request.url {
                // Open external links in Safari
                if url.scheme == "tel" || url.scheme == "mailto" {
                    UIApplication.shared.open(url)
                    decisionHandler(.cancel)
                    return
                }
            }
            decisionHandler(.allow)
        }
    }
}
