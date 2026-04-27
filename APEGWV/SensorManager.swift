import Foundation
import CoreMotion
import CoreLocation
import Combine

class SensorManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = SensorManager()
    
    private let motionManager = CMMotionManager()
    private let altimeter = CMAltimeter()
    private let locationManager = CLLocationManager()
    
    var onSensorUpdate: (([String: Any]) -> Void)?
    
    override init() {
        super.init()
    }
    
    func startSensors(updateInterval: TimeInterval = 0.1) {
        // Motion Data (Accelerometer, Gyroscope, Magnetometer)
        if motionManager.isDeviceMotionAvailable {
            motionManager.deviceMotionUpdateInterval = updateInterval
            motionManager.startDeviceMotionUpdates(to: .main) { [weak self] (data, error) in
                guard let data = data else { return }
                self?.sendUpdate(type: "motion", data: [
                    "acceleration": [
                        "x": data.userAcceleration.x,
                        "y": data.userAcceleration.y,
                        "z": data.userAcceleration.z
                    ],
                    "gravity": [
                        "x": data.gravity.x,
                        "y": data.gravity.y,
                        "z": data.gravity.z
                    ],
                    "rotation": [
                        "alpha": data.attitude.yaw,
                        "beta": data.attitude.pitch,
                        "gamma": data.attitude.roll
                    ],
                    "rotationRate": [
                        "x": data.rotationRate.x,
                        "y": data.rotationRate.y,
                        "z": data.rotationRate.z
                    ]
                ])
            }
        }
        
        // Altimeter
        if CMAltimeter.isRelativeAltitudeAvailable() {
            altimeter.startRelativeAltitudeUpdates(to: .main) { [weak self] (data, error) in
                guard let data = data else { return }
                self?.sendUpdate(type: "altimeter", data: [
                    "relativeAltitude": data.relativeAltitude.doubleValue,
                    "pressure": data.pressure.doubleValue
                ])
            }
        }
        
        // Heading (Compass)
        if CLLocationManager.headingAvailable() {
            locationManager.delegate = self
            locationManager.startUpdatingHeading()
        }
    }
    
    func stopSensors() {
        motionManager.stopDeviceMotionUpdates()
        altimeter.stopRelativeAltitudeUpdates()
        locationManager.stopUpdatingHeading()
    }
    
    private func sendUpdate(type: String, data: [String: Any]) {
        let update: [String: Any] = ["type": type, "data": data, "timestamp": Date().timeIntervalSince1970]
        onSensorUpdate?(update)
    }
}

extension SensorManager {
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        sendUpdate(type: "heading", data: [
            "magneticHeading": newHeading.magneticHeading,
            "trueHeading": newHeading.trueHeading,
            "headingAccuracy": newHeading.headingAccuracy,
            "x": newHeading.x,
            "y": newHeading.y,
            "z": newHeading.z
        ])
    }
}
