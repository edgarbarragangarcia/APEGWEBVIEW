//
//  WebView.swift
//  APEGWV
//
//  Created by Antigravity on 15/01/26.
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
                
                // HACK: Try to force UI update if the web app uses common patterns
                if (statuses.camera === 'authorized') {
                    // Try to find elements with "PENDIENTE" related to camera and change them
                    document.querySelectorAll('*').forEach(el => {
                        if (el.innerText === 'PENDIENTE' && el.closest('.camera-card')) {
                             // This is specific, but informative
                        }
                    });
                }
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
        context.coordinator.webView = webView
        
        // Start GPS if authorized
        if permissionManager.locationStatus == CLAuthorizationStatus.authorizedWhenInUse || permissionManager.locationStatus == CLAuthorizationStatus.authorizedAlways {
            permissionManager.requestLocationPermission() // This starts updates
        }
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        let request = URLRequest(url: url)
        uiView.load(request)
    }
    
    class Coordinator: NSObject, WKUIDelegate, WKScriptMessageHandler {
        var parent: WebView
        weak var webView: WKWebView?
        
        init(_ parent: WebView) {
            self.parent = parent
            super.init()
            self.parent.permissionManager.onStatusChange = { [weak self] in
                self?.sendStatusesToWeb()
            }
        }
        
        // Handle messages from JavaScript
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard let dict = message.body as? [String: Any],
                  let command = dict["command"] as? String else { return }
            
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
                // Location update is async via delegate
            case "motion":
                parent.permissionManager.requestMotionPermission()
            default:
                break
            }
        }
        
        func sendStatusesToWeb() {
            let json = parent.permissionManager.getStatusesJSON()
            let js = "if (window.onPermissionUpdate) { window.onPermissionUpdate(\(json)); }"
            webView?.evaluateJavaScript(js, completionHandler: nil)
        }
        
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
        
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, decidePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKMediaCaptureType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            // Some environments use the same method for everything, but let's be safe.
            decisionHandler(.prompt)
        }
        
        // This is the correct one for newer systems, but if WKPermissionType is not found,
        // we might have to use a more generic approach or ignore it if not needed for this build.
        /*
        @available(iOS 15.0, *)
        func webView(_ webView: WKWebView, decidePermissionFor origin: WKSecurityOrigin, initiatedByFrame frame: WKFrameInfo, type: WKPermissionType, decisionHandler: @escaping (WKPermissionDecision) -> Void) {
            if type == .geolocation {
                let status = parent.permissionManager.locationStatus
                if status == .authorizedWhenInUse || status == .authorizedAlways {
                    decisionHandler(.grant)
                    return
                }
            }
            decisionHandler(.prompt)
        }
        */
    }
}
