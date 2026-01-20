import Foundation
import CoreLocation
import AVFoundation
import CoreMotion
import Combine

class PermissionManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = PermissionManager()
    
    private let locationManager = CLLocationManager()
    private let motionActivityManager = CMMotionActivityManager()
    
    @Published var locationStatus: CLAuthorizationStatus = .notDetermined
    @Published var cameraStatus: AVAuthorizationStatus = .notDetermined
    @Published var motionStatus: String = "notDetermined"
    
    var onStatusChange: (() -> Void)?
    
    override init() {
        super.init()
        locationManager.delegate = self
        checkInitialStatuses()
    }
    
    func checkInitialStatuses() {
        self.locationStatus = locationManager.authorizationStatus
        self.cameraStatus = AVCaptureDevice.authorizationStatus(for: .video)
        checkMotionStatus()
    }
    
    func checkMotionStatus() {
        if CMMotionActivityManager.isActivityAvailable() {
            // Motion status is tricky as there's no direct "status" enum like others
            // but we can try to query it. For now, we'll assume notDetermined until requested.
        } else {
            self.motionStatus = "notAvailable"
        }
    }
    
    func requestLocationPermission() {
        locationManager.requestWhenInUseAuthorization()
        locationManager.startUpdatingLocation()
    }
    
    func requestCameraPermission(completion: @escaping (Bool) -> Void) {
        AVCaptureDevice.requestAccess(for: .video) { granted in
            DispatchQueue.main.async {
                self.cameraStatus = granted ? .authorized : .denied
                completion(granted)
            }
        }
    }
    
    func requestMotionPermission() {
        let now = Date()
        motionActivityManager.queryActivityStarting(from: now, to: now, to: .main) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error = error as NSError? {
                    // CMError.motionNotAuthorized is 105
                    if error.domain == CMErrorDomain && error.code == 105 {
                        self?.motionStatus = "denied"
                    } else {
                        self?.motionStatus = "notDetermined"
                    }
                } else {
                    self?.motionStatus = "authorized"
                }
                self?.onStatusChange?()
            }
        }
    }
    
    // MARK: - CLLocationManagerDelegate
    
    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        self.locationStatus = manager.authorizationStatus
        self.onStatusChange?()
    }
    
    func getStatusesJSON() -> String {
        let statuses: [String: String] = [
            "location": stringFromLocationStatus(locationStatus),
            "camera": stringFromCameraStatus(cameraStatus),
            "motion": motionStatus
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
