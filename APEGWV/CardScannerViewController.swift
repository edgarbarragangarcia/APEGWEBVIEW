
import UIKit
import AVFoundation
import Vision
import CoreImage

class CardScannerViewController: UIViewController {
    
    var onCardScanned: ((_ number: String, _ expiry: String?, _ name: String?) -> Void)?
    
    // MARK: - Camera Properties
    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer!
    private let videoOutput = AVCaptureVideoDataOutput()
    
    // MARK: - Vision Properties
    private var rectangleRequest: VNDetectRectanglesRequest!
    private var isProcessingFrame = false
    private var shouldCaptureNextFrame = false
    private var isScanning = true
    
    // Stability Tracking
    private var lastObservation: VNRectangleObservation?
    private var stabilityCounter = 0
    private let stabilityThreshold = 18 // Incremented to ~0.6s to give more time to align properly
    
    // Web-style visuals
    private var scanningLine: UIView!
    private var maskLayer: CAShapeLayer!
    private var headerLabel: UILabel!
    
    // MARK: - UI
    private var cardGuideView: UIView!
    private var feedbackLabel: UILabel!
    private var processingOverlay: UIView!
    private var closeButton: UIButton!
    private var detectionOverlay: CAShapeLayer!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        
        setupCamera()
        setupVision()
        setupUI()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
        
        // Update Mask
        let path = UIBezierPath(rect: view.bounds)
        let rectPath = UIBezierPath(roundedRect: cardGuideView.frame, cornerRadius: 20)
        path.append(rectPath)
        maskLayer.path = path.cgPath
        
        // Position Scanning Line
        scanningLine.frame = CGRect(x: cardGuideView.frame.minX, y: cardGuideView.frame.minY, width: cardGuideView.frame.width, height: 2)
        startScanningAnimation()
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.captureSession.startRunning()
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession.stopRunning()
    }
    
    // MARK: - Setup
    private func setupCamera() {
        captureSession.sessionPreset = .hd1920x1080 // High enough for OCR
        
        guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera) else {
            return
        }
        
        // Auto-focus setup
        try? camera.lockForConfiguration()
        if camera.isFocusModeSupported(.continuousAutoFocus) {
            camera.focusMode = .continuousAutoFocus
        }
        camera.unlockForConfiguration()
        
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        
        // Video Output
        videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "videoQueue"))
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)]
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        // Preview
        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)
    }
    
    private func setupVision() {
        rectangleRequest = VNDetectRectanglesRequest { [weak self] request, error in
            self?.handleRectangles(request: request, error: error)
        }
        rectangleRequest.minimumSize = 0.3 // Card must be at least 30% of screen width
        rectangleRequest.maximumObservations = 1
        rectangleRequest.minimumConfidence = 0.6
        rectangleRequest.quadratureTolerance = 45 // Allow some perspective skew
        // Credit card ratio is ~1.58. Allow detecting things roughly that shape.
        rectangleRequest.minimumAspectRatio = 0.5
        rectangleRequest.maximumAspectRatio = 1.0
    }
    
    private func setupUI() {
        // Close Button
        closeButton = UIButton(type: .system)
        closeButton.setImage(UIImage(systemName: "xmark.circle.fill"), for: .normal)
        closeButton.tintColor = .white
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.addTarget(self, action: #selector(didTapClose), for: .touchUpInside)
        view.addSubview(closeButton)
        
        // Card Guide (Default state)
        cardGuideView = UIView()
        cardGuideView.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        cardGuideView.layer.borderWidth = 2
        cardGuideView.layer.cornerRadius = 12
        cardGuideView.backgroundColor = .clear
        cardGuideView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(cardGuideView)
        
        NSLayoutConstraint.activate([
            cardGuideView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            cardGuideView.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: -50),
            cardGuideView.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.85),
            cardGuideView.heightAnchor.constraint(equalTo: cardGuideView.widthAnchor, multiplier: 0.63)
        ])
        
        // Visualization layer for dynamic detection
        detectionOverlay = CAShapeLayer()
        detectionOverlay.strokeColor = UIColor.yellow.cgColor
        detectionOverlay.lineWidth = 3
        detectionOverlay.fillColor = UIColor.clear.cgColor
        view.layer.addSublayer(detectionOverlay)
        
        // Header Label ("Web style")
        headerLabel = UILabel()
        headerLabel.text = "ESCANEAR TARJETA"
        headerLabel.textColor = .white
        headerLabel.font = .systemFont(ofSize: 14, weight: .black)
        headerLabel.textAlignment = .center
        view.addSubview(headerLabel)
        headerLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Feedback Label
        feedbackLabel = UILabel()
        feedbackLabel.text = "Ubica tu tarjeta dentro del recuadro"
        feedbackLabel.textColor = .white
        feedbackLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        feedbackLabel.textAlignment = .center
        feedbackLabel.alpha = 0.8
        view.addSubview(feedbackLabel)
        feedbackLabel.translatesAutoresizingMaskIntoConstraints = false
        
        // Background Mask Layer
        maskLayer = CAShapeLayer()
        maskLayer.fillRule = .evenOdd
        maskLayer.fillColor = UIColor.black.withAlphaComponent(0.6).cgColor
        view.layer.addSublayer(maskLayer)
        
        // Scanning Line
        scanningLine = UIView()
        scanningLine.backgroundColor = UIColor(red: 0.64, green: 0.90, blue: 0.21, alpha: 1.0) // var(--secondary)
        scanningLine.layer.shadowColor = scanningLine.backgroundColor?.cgColor
        scanningLine.layer.shadowRadius = 8
        scanningLine.layer.shadowOpacity = 0.8
        view.addSubview(scanningLine)
        
        // Processing Overlay
        processingOverlay = UIView()
        processingOverlay.backgroundColor = UIColor.black.withAlphaComponent(0.8)
        processingOverlay.isHidden = true
        processingOverlay.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(processingOverlay)
        
        let spinner = UIActivityIndicatorView(style: .large)
        spinner.color = UIColor.green
        spinner.startAnimating()
        spinner.translatesAutoresizingMaskIntoConstraints = false
        processingOverlay.addSubview(spinner)
        
        let procLabel = UILabel()
        procLabel.text = "Leyendo tarjeta..."
        procLabel.textColor = .white
        procLabel.font = .systemFont(ofSize: 18, weight: .bold)
        procLabel.translatesAutoresizingMaskIntoConstraints = false
        processingOverlay.addSubview(procLabel)
        
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: processingOverlay.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: processingOverlay.centerYAnchor, constant: -20),
            procLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 20),
            procLabel.centerXAnchor.constraint(equalTo: processingOverlay.centerXAnchor)
        ])
        
        setupConstraints()
    }
    
    private func setupConstraints() {
        NSLayoutConstraint.activate([
            closeButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 20),
            closeButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -20),
            closeButton.widthAnchor.constraint(equalToConstant: 36),
            closeButton.heightAnchor.constraint(equalToConstant: 36),
            
            headerLabel.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 28),
            headerLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            feedbackLabel.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -60),
            feedbackLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            
            processingOverlay.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            processingOverlay.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            processingOverlay.widthAnchor.constraint(equalToConstant: 200),
            processingOverlay.heightAnchor.constraint(equalToConstant: 100)
        ])
    }
    
    private func startScanningAnimation() {
        scanningLine.layer.removeAllAnimations()
        let animation = CABasicAnimation(keyPath: "position.y")
        animation.fromValue = cardGuideView.frame.minY
        animation.toValue = cardGuideView.frame.maxY
        animation.duration = 2.0
        animation.repeatCount = .infinity
        animation.autoreverses = true
        scanningLine.layer.add(animation, forKey: "scan")
    }
    
    // MARK: - Logic
    
    // Process detected rectangles
    private func handleRectangles(request: VNRequest, error: Error?) {
        guard isScanning, let results = request.results as? [VNRectangleObservation], let rect = results.first else {
            resetStability("Ubica tu tarjeta dentro del recuadro")
            return
        }
        
        DispatchQueue.main.async {
            self.drawBoundingBox(rect: rect)
        }
        
        // Check alignment
        let box = rect.boundingBox
        let isCentered = box.midX > 0.3 && box.midX < 0.7 && box.midY > 0.3 && box.midY < 0.7
        let isLargeEnough = box.width > 0.4 
        
        if isCentered && isLargeEnough {
            checkStability(rect)
        } else {
            resetStability("Acércala y céntrala")
        }
    }
    
    private func checkStability(_ currentRect: VNRectangleObservation) {
        guard let last = lastObservation else {
            lastObservation = currentRect
            stabilityCounter = 0
            return
        }
        
        let distance = hypot(currentRect.topLeft.x - last.topLeft.x, currentRect.topLeft.y - last.topLeft.y)
        
        if distance < 0.05 {
            stabilityCounter += 1
            DispatchQueue.main.async {
                self.feedbackLabel.text = "Quieto... \(self.stabilityCounter)/\(self.stabilityThreshold)"
                self.feedbackLabel.textColor = .yellow
                self.cardGuideView.layer.borderColor = UIColor.yellow.cgColor
            }
        } else {
            stabilityCounter = 0
            DispatchQueue.main.async {
                self.feedbackLabel.text = "Manténla quieta"
                self.feedbackLabel.textColor = .white
                self.cardGuideView.layer.borderColor = UIColor.white.withAlphaComponent(0.5).cgColor
            }
        }
        
        lastObservation = currentRect
        
        if stabilityCounter >= stabilityThreshold {
            shouldCaptureNextFrame = true
        }
    }
    
    private func resetStability(_ message: String) {
        stabilityCounter = 0
        lastObservation = nil
        DispatchQueue.main.async {
            self.feedbackLabel.text = message
            self.feedbackLabel.textColor = .white
            self.detectionOverlay.path = nil
            self.cardGuideView.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        }
    }
    
    private func drawBoundingBox(rect: VNRectangleObservation) {
        let convertedRect = previewLayer.layerRectConverted(fromMetadataOutputRect: rect.boundingBox)
        let path = UIBezierPath(rect: convertedRect)
        detectionOverlay.path = path.cgPath
        
        let color = stabilityCounter > 8 ? UIColor.green : (stabilityCounter > 3 ? UIColor.yellow : UIColor.white)
        detectionOverlay.strokeColor = color.cgColor
        cardGuideView.layer.borderColor = color.withAlphaComponent(0.5).cgColor
    }
    
    // MARK: - Capture & Process
    private func captureAndProcess(pixelBuffer: CVPixelBuffer) {
        guard isScanning else { return }
        guard let observation = lastObservation else { return }
        
        isScanning = false 
        
        DispatchQueue.main.async {
            let gen = UINotificationFeedbackGenerator()
            gen.notificationOccurred(.success)
            self.processingOverlay.isHidden = false
            self.feedbackLabel.text = "¡Capturado!"
            self.detectionOverlay.path = nil
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
            let w = ciImage.extent.width
            let h = ciImage.extent.height
            
            let topLeft = CGPoint(x: observation.topLeft.x * w, y: observation.topLeft.y * h)
            let topRight = CGPoint(x: observation.topRight.x * w, y: observation.topRight.y * h)
            let bottomRight = CGPoint(x: observation.bottomRight.x * w, y: observation.bottomRight.y * h)
            let bottomLeft = CGPoint(x: observation.bottomLeft.x * w, y: observation.bottomLeft.y * h)
            
            let filter = CIFilter(name: "CIPerspectiveCorrection")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(CIVector(cgPoint: topLeft), forKey: "inputTopLeft")
            filter?.setValue(CIVector(cgPoint: topRight), forKey: "inputTopRight")
            filter?.setValue(CIVector(cgPoint: bottomRight), forKey: "inputBottomRight")
            filter?.setValue(CIVector(cgPoint: bottomLeft), forKey: "inputBottomLeft")
            
            guard let correctedCIImage = filter?.outputImage else {
                self.handleFailure()
                return
            }
            
            // DUAL-PASS STRATEGY
            self.attemptOCR(with: correctedCIImage, pass: 1) { success in
                if !success {
                    print("🔄 Pass 1 failed, starting Pass 2...")
                    self.attemptOCR(with: correctedCIImage, pass: 2) { success2 in
                        if !success2 {
                            self.handleFailure()
                        }
                    }
                }
            }
        }
    }
    
    private func attemptOCR(with ciImage: CIImage, pass: Int, completion: @escaping (Bool) -> Void) {
        let context = CIContext()
        var processedImage: UIImage?
        
        if pass == 1 {
            // PASS 1: Standard contrast boost
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(1.15, forKey: kCIInputContrastKey)
            filter?.setValue(0.0, forKey: kCIInputSaturationKey)
            
            if let output = filter?.outputImage, let cgImg = context.createCGImage(output, from: output.extent) {
                processedImage = UIImage(cgImage: cgImg)
            }
        } else {
            // PASS 2: Higher contrast + Sharpen
            let filter = CIFilter(name: "CIColorControls")
            filter?.setValue(ciImage, forKey: kCIInputImageKey)
            filter?.setValue(1.4, forKey: kCIInputContrastKey)
            filter?.setValue(-0.1, forKey: kCIInputBrightnessKey)
            filter?.setValue(0.0, forKey: kCIInputSaturationKey)
            
            let sharpen = CIFilter(name: "CISharpenLuminance")
            sharpen?.setValue(filter?.outputImage, forKey: kCIInputImageKey)
            sharpen?.setValue(0.8, forKey: kCIInputSharpnessKey)
            
            if let output = sharpen?.outputImage, let cgImg = context.createCGImage(output, from: output.extent) {
                processedImage = UIImage(cgImage: cgImg)
            }
        }
        
        guard let finalImage = processedImage else {
            completion(false)
            return
        }
        
        OCRManager.shared.performOCR(on: finalImage) { result in
            switch result {
            case .success(let text):
                if let cardData = OCRManager.shared.parseCreditCard(from: text) {
                    DispatchQueue.main.async {
                        self.captureSession.stopRunning()
                        self.onCardScanned?(cardData["number"]!, cardData["expiry"], cardData["name"])
                        self.dismiss(animated: true)
                    }
                    completion(true)
                } else {
                    completion(false)
                }
            case .failure:
                completion(false)
            }
        }
    }
    
    private func handleFailure() {
        DispatchQueue.main.async {
            let feedback = UINotificationFeedbackGenerator()
            feedback.notificationOccurred(.error)
            
            self.processingOverlay.isHidden = true
            self.feedbackLabel.text = "No se pudo leer. Intenta de nuevo."
            self.isScanning = true
            self.shouldCaptureNextFrame = false
            self.stabilityCounter = 0
            self.cardGuideView.layer.borderColor = UIColor.white.withAlphaComponent(0.3).cgColor
        }
    }
    
    @objc private func didTapClose() {
        captureSession.stopRunning()
        dismiss(animated: true)
    }
}

extension CardScannerViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        if shouldCaptureNextFrame {
            shouldCaptureNextFrame = false
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            captureAndProcess(pixelBuffer: pixelBuffer)
            return
        }
        
        guard isScanning else { return }
        guard !isProcessingFrame, let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        isProcessingFrame = true
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .right, options: [:])
        
        do {
            try handler.perform([rectangleRequest])
            isProcessingFrame = false
        } catch {
            isProcessingFrame = false
        }
    }
}

class CardOverlayView: UIView {
    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
    }
    required init?(coder: NSCoder) { fatalError() }
    override func draw(_ rect: CGRect) {
        guard let context = UIGraphicsGetCurrentContext() else { return }
        context.setFillColor(UIColor.black.withAlphaComponent(0.6).cgColor)
        context.fill(rect)
        let cardWidth = rect.width * 0.85
        let cardHeight = cardWidth * 0.63
        let cardX = (rect.width - cardWidth) / 2
        let cardY = (rect.height - cardHeight) / 2 - 50 
        let cardRect = CGRect(x: cardX, y: cardY, width: cardWidth, height: cardHeight)
        let cardPath = UIBezierPath(roundedRect: cardRect, cornerRadius: 12)
        context.setBlendMode(.clear)
        context.addPath(cardPath.cgPath)
        context.fillPath()
    }
}
