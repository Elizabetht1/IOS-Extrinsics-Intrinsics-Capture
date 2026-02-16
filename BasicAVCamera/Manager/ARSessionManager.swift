//
//  ARSessionManager.swift
//  BasicAVCamera
//
//  Created for AR Integration
//

import Foundation
import ARKit
import Combine

class ARSessionManager: NSObject, ObservableObject {
    
    // MARK: - Properties
    
    private let arSession = ARSession()
    private var sessionQueue: DispatchQueue
    
    @Published var isRunning = false
    @Published var trackingState: ARCamera.TrackingState = .notAvailable
    
    // Video recording properties
    private var videoWriter: AVAssetWriter?
    private var videoWriterInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var isRecordingVideo = false
    private var videoStartTime: CMTime?
    private var videoOutputURL: URL?
    
    // Stream for video URLs (replaces movieFileStream from CameraManager)
    private var addToVideoStream: ((URL) -> Void)?
    
    lazy var videoStream: AsyncStream<URL> = {
        AsyncStream { continuation in
            addToVideoStream = { url in
                continuation.yield(url)
            }
        }
    }()

    // MARK: - Calibration Data Streams
    
    private var addToCalibrationStream: ((CameraCalibrationData) -> Void)?
    
    /// Stream of calibration data for each AR frame
    lazy var calibrationStream: AsyncStream<CameraCalibrationData> = {
        AsyncStream { continuation in
            addToCalibrationStream = { calibrationData in
                continuation.yield(calibrationData)
            }
        }
    }()
    
    // MARK: - Video Recording Support
    
    private var isRecordingCalibration = false
    private var calibrationFrames: [CameraCalibrationData] = []
    private var videoRecordingStartTime: TimeInterval?
    private var frameCounter = 0
    
    // MARK: - Initialization
    
    override init() {
        self.sessionQueue = DispatchQueue(label: "ar.session.queue")
        super.init()
        arSession.delegate = self
    }
    
    // MARK: - Session Control
    
    /// Start AR session
    func start() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            let configuration = ARWorldTrackingConfiguration()
            
            // Enable features if available
            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }
            
            // Run at high quality for better tracking
            configuration.worldAlignment = .gravity
            
            self.arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])
            
            DispatchQueue.main.async {
                self.isRunning = true
            }
        }
    }
    
    /// Pause AR session
    func pause() {
        sessionQueue.async { [weak self] in
            self?.arSession.pause()
            DispatchQueue.main.async {
                self?.isRunning = false
            }
        }
    }
    
    /// Stop AR session
    func stop() {
        pause()
    }
    
    // MARK: - Video Calibration Recording
    
    /// Start recording calibration data for video
    func startRecordingCalibration() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.isRecordingCalibration = true
            self.calibrationFrames.removeAll()
            self.videoRecordingStartTime = Date().timeIntervalSince1970
            self.frameCounter = 0
            print("Started recording AR calibration data")
        }
    }
    
    /// Stop recording and return collected calibration data
    func stopRecordingCalibration() -> [CameraCalibrationData] {
        var frames: [CameraCalibrationData] = []
        sessionQueue.sync { [weak self] in
            guard let self = self else { return }
            self.isRecordingCalibration = false
            frames = self.calibrationFrames
            print("Stopped recording AR calibration data. Captured \(frames.count) frames")
        }
        return frames
    }
    
    /// Get current calibration data snapshot
    func getCurrentCalibrationData() -> CameraCalibrationData? {
        guard let currentFrame = arSession.currentFrame else { return nil }
        return CameraCalibrationData(from: currentFrame)
    }
    
    // MARK: - Export Methods
    
    /// Save video calibration data to JSON file
    func saveVideoCalibrationData(
        frames: [CameraCalibrationData],
        videoFileName: String,
        to directory: URL
    ) async throws {
        guard !frames.isEmpty else {
            print("No calibration frames to save")
            return
        }
        
        let startTime = frames.first?.timestamp ?? 0
        let endTime = frames.last?.timestamp ?? 0
        
        let videoCalibration = VideoCalibrationData(
            frames: frames,
            videoFileName: videoFileName,
            recordingStartTime: startTime,
            recordingEndTime: endTime,
            totalFrames: frames.count
        )
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(videoCalibration)
        
        let baseFileName = (videoFileName as NSString).deletingPathExtension
        let jsonFileName = "\(baseFileName)_calibration.json"
        let fileURL = directory.appendingPathComponent(jsonFileName)
        
        try data.write(to: fileURL)
        print("Saved calibration data to: \(fileURL.path)")
    }
    
    /// Save single photo calibration data to JSON file
    func savePhotoCalibrationData(
        _ calibrationData: CameraCalibrationData,
        photoFileName: String,
        to directory: URL
    ) async throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(calibrationData)
        
        let baseFileName = (photoFileName as NSString).deletingPathExtension
        let jsonFileName = "\(baseFileName)_calibration.json"
        let fileURL = directory.appendingPathComponent(jsonFileName)
        
        try data.write(to: fileURL)
        print("Saved calibration data to: \(fileURL.path)")
    }
    
    // MARK: - Video Recording
        
    func startRecordingVideo() {
        guard !isRecordingVideo else { return }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            // Create output URL
            guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                print("❌ Cannot access documents directory")
                return
            }
            
            let fileName = UUID().uuidString + ".mp4"
            let url = directory.appendingPathComponent(fileName)
            self.videoOutputURL = url
            
            // Setup AVAssetWriter
            do {
                let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
                
                // Video settings - match AR camera resolution
                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: 1920,
                    AVVideoHeightKey: 1440,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: 6000000
                    ]
                ]
                
                let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                writerInput.expectsMediaDataInRealTime = true
                
                // Pixel buffer adaptor
                let sourcePixelBufferAttributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                    kCVPixelBufferWidthKey as String: 1920,
                    kCVPixelBufferHeightKey as String: 1440
                ]
                
                let adaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: writerInput,
                    sourcePixelBufferAttributes: sourcePixelBufferAttributes
                )
                
                if writer.canAdd(writerInput) {
                    writer.add(writerInput)
                }
                
                self.videoWriter = writer
                self.videoWriterInput = writerInput
                self.pixelBufferAdaptor = adaptor
                self.isRecordingVideo = true
                self.videoStartTime = nil
                
                writer.startWriting()
                
                print("✅ AR video recording started")
                
            } catch {
                print("❌ Failed to create AVAssetWriter: \(error)")
            }
        }
    }
    
    func stopRecordingVideo() {
        guard isRecordingVideo else { return }
        
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            
            self.isRecordingVideo = false
            
            guard let writer = self.videoWriter,
                  let writerInput = self.videoWriterInput else {
                print("❌ No video writer to stop")
                return
            }
            
            writerInput.markAsFinished()
            
            writer.finishWriting { [weak self] in
                guard let self = self else { return }
                
                if writer.status == .completed,
                   let outputURL = self.videoOutputURL {
                    print("✅ AR video recorded to \(outputURL)")
                    self.addToVideoStream?(outputURL)
                } else if let error = writer.error {
                    print("❌ Video writing failed: \(error)")
                } else {
                    print("❌ Video writing failed with status: \(writer.status.rawValue)")
                }
                
                // Cleanup
                self.videoWriter = nil
                self.videoWriterInput = nil
                self.pixelBufferAdaptor = nil
                self.videoStartTime = nil
                self.videoOutputURL = nil
            }
        }
    }
}

// MARK: - ARSessionDelegate

extension ARSessionManager: ARSessionDelegate {
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
            if frameCounter == 0 && isRecordingCalibration {
                print("✅ First AR frame received while recording!")
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.trackingState = frame.camera.trackingState
            }
            
            let calibrationData = CameraCalibrationData(from: frame, frameIndex: isRecordingCalibration ? frameCounter : nil)
            
            addToCalibrationStream?(calibrationData)
            
            if isRecordingCalibration {
                calibrationFrames.append(calibrationData)
                frameCounter += 1
                
                if frameCounter % 30 == 0 {
                    print("📊 AR Recording: \(frameCounter) frames captured")
                }
            }
            
            // NEW: Write video frame if recording
            if isRecordingVideo {
                writeVideoFrame(frame)
            }
        }
        
        private func writeVideoFrame(_ frame: ARFrame) {
            guard let writerInput = videoWriterInput,
                  let adaptor = pixelBufferAdaptor,
                  writerInput.isReadyForMoreMediaData else {
                return
            }
            
            let pixelBuffer = frame.capturedImage
            let timestamp = CMTime(seconds: frame.timestamp, preferredTimescale: 600)
            
            // Start session on first frame
            if videoStartTime == nil {
                videoWriter?.startSession(atSourceTime: timestamp)
                videoStartTime = timestamp
            }
            
            // Append pixel buffer
            adaptor.append(pixelBuffer, withPresentationTime: timestamp)
        }
    func session(_ session: ARSession, didFailWithError error: Error) {
        print("AR Session failed: \(error.localizedDescription)")
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        print("AR Session was interrupted")
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        print("AR Session interruption ended")
        // Optionally restart with reset
        start()
    }
}
