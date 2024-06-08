//
//  ScannerViewController.swift
//  Yolov8-RealTime-iOS
//
//  Created by Erdoğan Kayalı on 22.05.2024.
//

import UIKit
import AVFoundation
import Speech

class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var isSpeak: Bool = false {
        didSet {
            updateButtonAppearance()
        }
    }

    let recordButton: UIButton = {
        let button = UIButton(type: .system)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.layer.cornerRadius = 5
        button.titleLabel?.font = UIFont.systemFont(ofSize: 32)
        button.setTitleColor(.white, for: .normal)
        return button
    }()

    var captureSession: AVCaptureSession!
    var previewLayer: AVCaptureVideoPreviewLayer!
    var qrText: String = ""
    var isScanningAllowed = true
    var scanInterval: TimeInterval = 3.0
    var result2 : String = ""
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "tr-TR"))!
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()
    private var speechSynthesizer: AVSpeechSynthesizer?
    private var speechSynthesizer2: AVSpeechSynthesizer?

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black
        captureSession = AVCaptureSession()

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
        speechSynthesizer2 = AVSpeechSynthesizer()

        SFSpeechRecognizer.requestAuthorization { authStatus in
            OperationQueue.main.addOperation {
                switch authStatus {
                case .authorized:
                    self.recordButton.isEnabled = true
                case .denied, .restricted, .notDetermined:
                    self.recordButton.isEnabled = false
                default:
                    break
                }
            }
        }

        setupCaptureSession()

        // Start a timer to allow scanning at intervals
        Timer.scheduledTimer(withTimeInterval: scanInterval, repeats: true) { timer in
            self.isScanningAllowed = true
        }
    }

    func setupCaptureSession() {
        guard let videoCaptureDevice = AVCaptureDevice.default(for: .video) else { return }
        let videoInput: AVCaptureDeviceInput

        do {
            videoInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
        } catch {
            return
        }

        if captureSession.canAddInput(videoInput) {
            captureSession.addInput(videoInput)
        } else {
            failed()
            return
        }

        let metadataOutput = AVCaptureMetadataOutput()

        if captureSession.canAddOutput(metadataOutput) {
            captureSession.addOutput(metadataOutput)

            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]
        } else {
            failed()
            return
        }

        previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        previewLayer.frame = view.layer.bounds
        previewLayer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(previewLayer)

        captureSession.startRunning()
    }

    func failed() {
        let ac = UIAlertController(title: "Scanning not supported", message: "Your device does not support scanning a code from an item. Please use a device with a camera.", preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default))
        present(ac, animated: true)
        captureSession = nil
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        qrText = "Karekod okuma aktif"
        announceDetectedObjects()
        if captureSession?.isRunning == false {
            captureSession.startRunning()
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)

        if captureSession?.isRunning == true {
            captureSession.stopRunning()
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard isScanningAllowed else { return }
        isScanningAllowed = false

        if let metadataObject = metadataObjects.first {
            guard let readableObject = metadataObject as? AVMetadataMachineReadableCodeObject else { return }
            guard let stringValue = readableObject.stringValue else { return }
            AudioServicesPlaySystemSound(SystemSoundID(kSystemSoundID_Vibrate))
            found(code: stringValue)
        }
    }

    func found(code: String) {
        print("QR Code: \(code)")
        if qrText != code{
            qrText = code
            announceDetectedObjects()
        }
        
    }

    func updateButtonAppearance() {
        let backgroundColor = isSpeak ? UIColor.green : UIColor.red
        let title = isSpeak ? "Çek" : "Bas Konuş(Karekod)"

        UIView.animate(withDuration: 0.3) {
            self.recordButton.backgroundColor = backgroundColor
            self.recordButton.setTitle(title, for: .normal)
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
        if result2 == "geri" {
            qrText = "Karekod okuma deaktif, nesne tanıma aktif"
            announceDetectedObjects()
            self.navigationController?.popViewController(animated: true)
        }

    }

    @objc func announceDetectedObjects() {
        print("Announcing detected QR code: \(qrText)")
        if qrText != "" {
            let utterance = AVSpeechUtterance(string: qrText)
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
            if let synthesizer = speechSynthesizer2 {
                if synthesizer.isSpeaking {
                    synthesizer.stopSpeaking(at: .immediate)
                }
                synthesizer.speak(utterance)
            } else {
                print("Speech synthesizer is not initialized.")
            }
        }
    }

    @objc func startRecording() {
        print("Start recording button pressed.")
        isSpeak = true
        startSpeechRecognition()
    }

    @objc func stopRecording() {
        print("Stop recording button pressed.")
        isSpeak = false
        stopSpeechRecognition()
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
}
