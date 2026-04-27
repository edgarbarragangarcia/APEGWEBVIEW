import Foundation
import CoreLocation
import AVFoundation
import CoreMotion
import Combine
import UIKit

class PermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = PermissionManager()
    
    private let locationManager = CLLocationManager()
    
    @Published var locationStatus: CLAuthorizationStatus = .notDetermined
    @Published var cameraStatus: AVAuthorizationStatus = .notDetermined
    @Published var microphoneStatus: AVAuthorizationStatus = .notDetermined
    @Published var accuracyAuthorization: CLAccuracyAuthorization = .reducedAccuracy
    
    var onStatusChange: (() -> Void)?
    
    override init() {
        super.init()
        locationManager.delegate = self
        checkInitialStatuses()
    }
    
    func checkInitialStatuses() {
        self.locationStatus = locationManager.authorizationStatus
        self.accuracyAuthorization = locationManager.accuracyAuthorization
        self.cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        self.microphoneStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        self.onStatusChange?()
    }
    
    func requestLocationPermission() {
        if locationStatus == .denied || locationStatus == .restricted {
            // Already denied, do nothing or we could show an alert
            return
        }
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func requestCameraPermission(completion: ((Bool) -> Void)? = nil) {
        if cameraStatus == .authorized {
            completion?(true)
            return
        }
        
        if cameraStatus == .denied || cameraStatus == .restricted {
            completion?(false)
            return
        }
        
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                self.cameraStatus = granted ? .authorized : .denied
                self.onStatusChange?()
                completion?(granted)
            }
        }
    }
    
    func requestMicrophonePermission(completion: ((Bool) -> Void)? = nil) {
        if microphoneStatus == .authorized {
            completion?(true)
            return
        }
        
        if microphoneStatus == .denied || microphoneStatus == .restricted {
            completion?(false)
            return
        }
        
        AVAudioSession.sharedInstance().requestRecordPermission { granted in
            DispatchQueue.main.async {
                self.microphoneStatus = granted ? .authorized : .denied
                self.onStatusChange?()
                completion?(granted)
            }
        }
    }
    
    func requestAllPermissions() {
        // 1. Location (usually the first prompt)
        requestLocationPermission()
        
        // 2. Camera
        requestCameraPermission()
        
        // 3. Microphone
        requestMicrophonePermission()
    }
    
    func requestMotionPermission() {
        // CoreMotion doesn't have a traditional permission prompt.
        // Starting sensors implicitly triggers the "Motion & Fitness" prompt on first use.
        SensorManager.shared.startSensors()
    }
    
    func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            if UIApplication.shared.canOpenURL(url) {
                UIApplication.shared.open(url, options: [:], completionHandler: nil)
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.locationStatus = manager.authorizationStatus
        self.accuracyAuthorization = manager.accuracyAuthorization
        self.onStatusChange?()
    }
    
    func getStatusesJSON() -> String {
        let statuses: [String: Any] = [
            "location": stringFromLocationStatus(locationStatus),
            "preciseLocation": accuracyAuthorization == .fullAccuracy,
            "camera": stringFromCameraStatus(cameraStatus),
            "microphone": stringFromCameraStatus(microphoneStatus),
            "notifications": NotificationManager.shared.authorizationStatus == .authorized ? "authorized" : (NotificationManager.shared.authorizationStatus == .denied ? "denied" : "notDetermined"),
            "deviceToken": NotificationManager.shared.deviceToken ?? NSNull()
        ]
        
        if let jsonData = try? JSONSerialization.data(withJSONObject: statuses, options: []),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        return "{}"
    }
    
    private func stringFromLocationStatus(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: return "authorized"
        case .denied, .restricted: return "denied"
        default: return "notDetermined"
        }
    }
    
    private func stringFromCameraStatus(_ status: AVAuthorizationStatus) -> String {
        switch status {
        case .authorized: return "authorized"
        case .denied, .restricted: return "denied"
        default: return "notDetermined"
        }
    }
}

