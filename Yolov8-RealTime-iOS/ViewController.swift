import UIKit
import AVFoundation
import Vision
import Speech

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate, AVCapturePhotoCaptureDelegate {
    var isSpeak: Bool = false {
            didSet {
                updateButtonAppearance()
            }
        }
    var isNavigate : Bool = false
    var result2 : String = ""
        let recordButton: UIButton = {
            let button = UIButton(type: .system)
            button.translatesAutoresizingMaskIntoConstraints = false
            button.layer.cornerRadius = 5
            button.titleLabel?.font = UIFont.systemFont(ofSize: 32)
            button.setTitleColor(.white, for: .normal)
            return button
        }()
    var captureSession = AVCaptureSession()
    var previewView = UIImageView()
    var previewLayer: AVCaptureVideoPreviewLayer!
    var videoOutput: AVCaptureVideoDataOutput!
    var frameCounter = 0
    var frameInterval = 1
    var videoSize = CGSize.zero
    let colors: [UIColor] = {
        var colorSet: [UIColor] = []
        for _ in 0...80 {
            let color = UIColor(red: CGFloat.random(in: 0...1), green: CGFloat.random(in: 0...1), blue: CGFloat.random(in: 0...1), alpha: 1)
            colorSet.append(color)
        }
        return colorSet
    }()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    let ciContext = CIContext()
    var classes: [String] = []
    private var speechSynthesizer: AVSpeechSynthesizer?
    var detectedObjects: [Detection] = []
    var timer : Timer?
    lazy var yoloRequest: VNCoreMLRequest! = {
        do {
            let model = try yolov8s().model
            guard let classes = model.modelDescription.classLabels as? [String] else {
                fatalError()
            }
            self.classes = classes
            let vnModel = try VNCoreMLModel(for: model)
            let request = VNCoreMLRequest(model: vnModel)
            return request
        } catch {
            fatalError("mlmodel error.")
        }
    }()
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        timer?.invalidate()
    }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        timer?.invalidate()
    }
    override func viewDidAppear(_ animated: Bool) {
       super.viewDidAppear(animated)
        isNavigate = false
        timer = Timer.scheduledTimer(timeInterval: 3.0, target: self, selector: #selector(announceDetectedObjects), userInfo: nil, repeats: true)
    }
    override func viewDidLoad() {
        super.viewDidLoad()
        setupVideo()
        
        
        recordButton.addTarget(self, action: #selector(startRecording), for: .touchDown)
        recordButton.addTarget(self, action: #selector(stopRecording), for: .touchUpInside)
        recordButton.layer.zPosition = 1
        view.addSubview(recordButton)
        NSLayoutConstraint.activate([
            recordButton.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            recordButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            recordButton.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -16),
            recordButton.heightAnchor.constraint(equalToConstant: 120)
        ])

        updateButtonAppearance()
        speechSynthesizer = AVSpeechSynthesizer()

    }
    func updateButtonAppearance() {
        let backgroundColor = isSpeak ? UIColor.green : UIColor.red
        let title = isSpeak ? "Çek" : "Bas Konuş(Nesne)"

        UIView.animate(withDuration: 0.3) {
            self.recordButton.backgroundColor = backgroundColor
            self.recordButton.setTitle(title, for: .normal)
        }
    }
    func setupVideo() {
        previewView.frame = view.bounds
        view.addSubview(previewView)

        captureSession.beginConfiguration()

        let device = AVCaptureDevice.default(for: AVMediaType.video)
        let deviceInput = try! AVCaptureDeviceInput(device: device!)

        captureSession.addInput(deviceInput)
        videoOutput = AVCaptureVideoDataOutput()

        let queue = DispatchQueue(label: "VideoQueue")
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        captureSession.addOutput(videoOutput)
        if let videoConnection = videoOutput.connection(with: .video) {
            if videoConnection.isVideoOrientationSupported {
                videoConnection.videoOrientation = .portrait
            }
        }
        captureSession.commitConfiguration()

        DispatchQueue.global(qos: .userInitiated).async {
            self.captureSession.startRunning()
        }
    }
    
    func detection(pixelBuffer: CVPixelBuffer) -> UIImage? {
        do {
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer)
            try handler.perform([yoloRequest])
            guard let results = yoloRequest.results as? [VNRecognizedObjectObservation] else {
                return nil
            }
            var detections: [Detection] = []
            for result in results {
                let flippedBox = CGRect(x: result.boundingBox.minX, y: 1 - result.boundingBox.maxY, width: result.boundingBox.width, height: result.boundingBox.height)
                let box = VNImageRectForNormalizedRect(flippedBox, Int(videoSize.width), Int(videoSize.height))

                guard let label = result.labels.first?.identifier,
                      let colorIndex = classes.firstIndex(of: label) else {
                    return nil
                }
                let detection = Detection(box: box, confidence: result.confidence, label: label, color: colors[colorIndex])
                detections.append(detection)
            }
            detectedObjects = detections
            let drawImage = drawRectsOnImage(detections, pixelBuffer)
            return drawImage
        } catch {
            print(error)
            return nil
        }
    }
    
    func drawRectsOnImage(_ detections: [Detection], _ pixelBuffer: CVPixelBuffer) -> UIImage? {
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent)!
        let size = ciImage.extent.size
        guard let cgContext = CGContext(data: nil,
                                        width: Int(size.width),
                                        height: Int(size.height),
                                        bitsPerComponent: 8,
                                        bytesPerRow: 4 * Int(size.width),
                                        space: CGColorSpaceCreateDeviceRGB(),
                                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cgContext.draw(cgImage, in: CGRect(origin: .zero, size: size))
        for detection in detections {
            let invertedBox = CGRect(x: detection.box.minX, y: size.height - detection.box.maxY, width: detection.box.width, height: detection.box.height)
            if let labelText = detection.label {
                cgContext.textMatrix = .identity
                
                let text = "\(labelText) : \(round(detection.confidence * 100))"
                
                let textRect  = CGRect(x: invertedBox.minX + size.width * 0.01, y: invertedBox.minY - size.width * 0.01, width: invertedBox.width, height: invertedBox.height)
                let textStyle = NSMutableParagraphStyle.default.mutableCopy() as! NSMutableParagraphStyle
                
                let textFontAttributes = [
                    NSAttributedString.Key.font: UIFont.systemFont(ofSize: textRect.width * 0.1, weight: .bold),
                    NSAttributedString.Key.foregroundColor: detection.color,
                    NSAttributedString.Key.paragraphStyle: textStyle
                ]
                
                cgContext.saveGState()
                defer { cgContext.restoreGState() }
                let astr = NSAttributedString(string: text, attributes: textFontAttributes)
                let setter = CTFramesetterCreateWithAttributedString(astr)
                let path = CGPath(rect: textRect, transform: nil)
                
                let frame = CTFramesetterCreateFrame(setter, CFRange(), path, nil)
                cgContext.textMatrix = CGAffineTransform.identity
                CTFrameDraw(frame, cgContext)
                
                cgContext.setStrokeColor(detection.color.cgColor)
                cgContext.setLineWidth(9)
                cgContext.stroke(invertedBox)
            }
        }
        
        guard let newImage = cgContext.makeImage() else { return nil }
        return UIImage(ciImage: CIImage(cgImage: newImage))
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        frameCounter += 1
        if videoSize == CGSize.zero {
            guard let width = sampleBuffer.formatDescription?.dimensions.width,
                  let height = sampleBuffer.formatDescription?.dimensions.height else {
                fatalError()
            }
            videoSize = CGSize(width: CGFloat(width), height: CGFloat(height))
        }
        if frameCounter == frameInterval {
            frameCounter = 0
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
            guard let drawImage = detection(pixelBuffer: pixelBuffer) else {
                return
            }
            DispatchQueue.main.async {
                self.previewView.image = drawImage
            }
        }
    }
    func startSpeechRecognition() {
        if recognitionTask != nil {
            recognitionTask?.cancel()
            recognitionTask = nil
        }

        let audioSession = AVAudioSession.sharedInstance()

        do {
            try audioSession.setCategory(.record, mode: .measurement, options: .duckOthers)
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("Error setting up audio session: \(error.localizedDescription)")
            return
        }

        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()

        let inputNode = audioEngine.inputNode

        guard let recognitionRequest = recognitionRequest else {
            fatalError("Unable to create a recognition request")
        }

        recognitionRequest.shouldReportPartialResults = true

        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest) { result, error in
            var isFinal = false

            if let result = result {
                print("Recognized text: \(result.bestTranscription.formattedString)")
                isFinal = result.isFinal
                self.result2 = result.bestTranscription.formattedString.lowercased()
            }

            if error != nil || isFinal {
                self.audioEngine.stop()
                inputNode.removeTap(onBus: 0)

                self.recognitionRequest = nil
                self.recognitionTask = nil

                self.recordButton.isEnabled = true
            }
        }

        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { (buffer, when) in
            self.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()

        do {
            try audioEngine.start()
        } catch {
            print("Error starting audio engine: \(error.localizedDescription)")
        }
    }

    func stopSpeechRecognition() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        if audioEngine.inputNode.numberOfInputs > 0 {
            audioEngine.inputNode.removeTap(onBus: 0)
        }
        recognitionRequest = nil
        recognitionTask = nil
        recordButton.isEnabled = true

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("Error deactivating audio session: \(error.localizedDescription)")
        }
        print(result2)
        if result2 == "karekod" {
            if !self.isNavigate{
                let vc = ScannerViewController()
                self.navigationController?.pushViewController(vc, animated: true)
            }
          
        }
    }
    func translate (name: String) -> String {
        switch name {
        case "Apple":
            return "Elma"
        case "Bell-pepper":
            return "Biber"
        case "Cucumber":
            return "Salatalık"
        case "Lemon":
            return "Limon"
        case "Orange":
            return "Portakal"
        case "Potato":
            return "Patates"
        case "Tomato":
            return "Domates"
        case "Watermelon":
            return "Karpuz"
        default:
            return "Bilinmeyen"
        }
    }
    @objc func startRecording() {
        isSpeak = true
        startSpeechRecognition()
    }

    @objc func stopRecording() {
        isSpeak = false
        stopSpeechRecognition()
    }
    @objc func announceDetectedObjects() {
        let detectedLabels = detectedObjects.map { $0.label ?? "" }.joined(separator: ", ")
        
        if !detectedLabels.isEmpty {
            let first = detectedLabels.split(separator: ", ").first
            let translate = translate(name: String(first!))
            let utterance = AVSpeechUtterance(string: translate )
            utterance.voice = AVSpeechSynthesisVoice(language: "tr-TR")

            // Check if the selected voice is available
            if !AVSpeechSynthesisVoice.speechVoices().contains(utterance.voice!) {
                print("Selected voice not available.")
                return
            }

            let audioSession = AVAudioSession.sharedInstance()
            do {
                try audioSession.setCategory(.playback, mode: .default)
                try audioSession.setActive(true)
            } catch {
                print("Error setting up audio session: \(error.localizedDescription)")
                return
            }

            // Speak the QR code
            if let synthesizer = speechSynthesizer{
                if synthesizer.isSpeaking {
                    synthesizer.stopSpeaking(at: .immediate)
                }
                synthesizer.speak(utterance)
            } else {
                print("Speech synthesizer is not initialized.")
            }
        }
    }

}

struct Detection {
    let box: CGRect
    let confidence: Float
    let label: String?
    let color: UIColor
}
