//
//  ARManager.swift
//  BasicAVCamera
//
//  Created by Elizabeth Terveen on 2/14/26.
//

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
        print("[DEBUG] initializing session \n")
        self.sessionQueue = DispatchQueue(label: "ar.session.queue")
        super.init()
        arSession.delegate = self
    }
    
    // MARK: - Session Control
    
    /// Start AR session
    func start() {
        print("🔵 starting session manager started")
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
}

// MARK: - ARSessionDelegate

extension ARSessionManager: ARSessionDelegate {
    
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // Update tracking state
        DispatchQueue.main.async { [weak self] in
            self?.trackingState = frame.camera.trackingState
        }
        
        // Create calibration data
        let calibrationData = CameraCalibrationData(from: frame, frameIndex: isRecordingCalibration ? frameCounter : nil)
        
        // Add to stream for real-time monitoring
        addToCalibrationStream?(calibrationData)
        
        // If recording for video, collect frames
        if isRecordingCalibration {
            calibrationFrames.append(calibrationData)
            frameCounter += 1
        }
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
