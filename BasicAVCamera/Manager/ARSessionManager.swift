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
    private var isRecording = false
    private var videoStartTime: CMTime?
    private var videoOutputURL: URL?

    // Stream for video URLs
    private var addToVideoStream: ((URL) -> Void)?

    lazy var videoStream: AsyncStream<URL> = {
        AsyncStream { continuation in
            addToVideoStream = { url in
                continuation.yield(url)
            }
        }
    }()

    // Preview stream — buffers only the latest frame to avoid retaining ARFrames
    private let previewCIContext = CIContext()
    private var addToPreviewStream: ((CGImage) -> Void)?

    lazy var previewStream: AsyncStream<CGImage> = {
        AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            addToPreviewStream = { cgImage in
                continuation.yield(cgImage)
            }
        }
    }()

    // MARK: - Calibration Data Streams

    private var addToCalibrationStream: ((CameraCalibrationData) -> Void)?

    lazy var calibrationStream: AsyncStream<CameraCalibrationData> = {
        AsyncStream { continuation in
            addToCalibrationStream = { calibrationData in
                continuation.yield(calibrationData)
            }
        }
    }()

    // MARK: - Recording State (accessed only on sessionQueue)

    private var calibrationFrames: [CameraCalibrationData] = []
    private var writtenVideoFrameCount = 0

    // MARK: - Initialization

    override init() {
        self.sessionQueue = DispatchQueue(label: "ar.session.queue")
        super.init()
        arSession.delegate = self
    }

    // MARK: - Session Control

    func start() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }

            let configuration = ARWorldTrackingConfiguration()

            if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                configuration.frameSemantics.insert(.sceneDepth)
            }

            configuration.worldAlignment = .gravity

            self.arSession.run(configuration, options: [.resetTracking, .removeExistingAnchors])

            DispatchQueue.main.async {
                self.isRunning = true
            }
        }
    }

    func pause() {
        sessionQueue.async { [weak self] in
            self?.arSession.pause()
            DispatchQueue.main.async {
                self?.isRunning = false
            }
        }
    }

    func stop() {
        pause()
    }

    // MARK: - Unified Recording (video + calibration)

    /// Start recording video and calibration data atomically
    func startRecording() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard !self.isRecording else { return }

            guard let currentFrame = self.arSession.currentFrame else {
                print("No AR frame available")
                return
            }

            let pixelBuffer = currentFrame.capturedImage
            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)

            // Reset state
            self.calibrationFrames.removeAll()
            self.writtenVideoFrameCount = 0

            // Create output URL
            guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
                print("Cannot access documents directory")
                return
            }

            let fileName = UUID().uuidString + ".mp4"
            let url = directory.appendingPathComponent(fileName)
            self.videoOutputURL = url

            do {
                let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

                let videoSettings: [String: Any] = [
                    AVVideoCodecKey: AVVideoCodecType.h264,
                    AVVideoWidthKey: width,
                    AVVideoHeightKey: height,
                    AVVideoCompressionPropertiesKey: [
                        AVVideoAverageBitRateKey: 6000000
                    ]
                ]

                let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
                writerInput.expectsMediaDataInRealTime = true
                writerInput.transform = CGAffineTransform(rotationAngle: .pi / 2)

                let sourcePixelBufferAttributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: Int(CVPixelBufferGetPixelFormatType(pixelBuffer)),
                    kCVPixelBufferWidthKey as String: width,
                    kCVPixelBufferHeightKey as String: height
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

                writer.startWriting()

                let currentTimestamp = CMTime(seconds: currentFrame.timestamp, preferredTimescale: 600)
                writer.startSession(atSourceTime: currentTimestamp)
                self.videoStartTime = currentTimestamp

                // Mark as recording last so delegate callback sees consistent state
                self.isRecording = true

                print("Recording started - \(width)x\(height)")

            } catch {
                print("Failed to create AVAssetWriter: \(error)")
            }
        }
    }

    /// Stop recording video and calibration. Calls completion with the video URL and calibration frames once the video file is finalized.
    func stopRecording(completion: @escaping (URL?, [CameraCalibrationData]) -> Void) {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            guard self.isRecording else {
                completion(nil, [])
                return
            }

            // Stop recording so no more frames are written or calibration entries added
            self.isRecording = false

            let frames = self.calibrationFrames

            guard let writer = self.videoWriter,
                  let writerInput = self.videoWriterInput else {
                completion(nil, frames)
                return
            }

            writerInput.markAsFinished()

            writer.finishWriting { [weak self] in
                guard let self = self else { return }

                var completedURL: URL? = nil
                if writer.status == .completed,
                   let outputURL = self.videoOutputURL {
                    print("Video recorded to \(outputURL)")
                    completedURL = outputURL
                    self.addToVideoStream?(outputURL)
                } else if let error = writer.error {
                    print("Video writing failed: \(error)")
                }

                // Cleanup
                self.videoWriter = nil
                self.videoWriterInput = nil
                self.pixelBufferAdaptor = nil
                self.videoStartTime = nil
                self.videoOutputURL = nil

                completion(completedURL, frames)
            }
        }
    }

    // MARK: - Photo Calibration

    func getCurrentCalibrationData() -> CameraCalibrationData? {
        guard let currentFrame = arSession.currentFrame else { return nil }
        return CameraCalibrationData(from: currentFrame)
    }

    // MARK: - Export Methods

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
        let pixelBuffer = frame.capturedImage
        let timestamp = frame.timestamp

        // Update tracking state
        DispatchQueue.main.async { [weak self] in
            self?.trackingState = frame.camera.trackingState
        }

        // Preview — convert to CGImage immediately to release the pixel buffer
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer).oriented(.right)
        if let cgImage = previewCIContext.createCGImage(ciImage, from: ciImage.extent) {
            addToPreviewStream?(cgImage)
        }

        // Create calibration data (always, for the live stream)
        var calibrationData = CameraCalibrationData(from: frame)
        addToCalibrationStream?(calibrationData)

        // Recording: write video frame and collect calibration.
        // Only append calibration when the frame is actually written to the video file,
        // so calibrationFrames[i] corresponds exactly to video frame i.
        if isRecording {
            let cmTimestamp = CMTime(seconds: timestamp, preferredTimescale: 600)
            let written = writeVideoFrame(pixelBuffer: pixelBuffer, timestamp: cmTimestamp)

            if written {
                calibrationData.frameIndex = writtenVideoFrameCount
                writtenVideoFrameCount += 1
                calibrationFrames.append(calibrationData)

                if writtenVideoFrameCount % 30 == 0 {
                    print("Recording: \(writtenVideoFrameCount) frames written to video")
                }
            }
        }
    }

    /// Returns true if the frame was successfully written
    private func writeVideoFrame(pixelBuffer: CVPixelBuffer, timestamp: CMTime) -> Bool {
        guard let writerInput = videoWriterInput,
              let adaptor = pixelBufferAdaptor else {
            return false
        }

        guard writerInput.isReadyForMoreMediaData else {
            return false
        }

        return adaptor.append(pixelBuffer, withPresentationTime: timestamp)
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        print("AR Session failed: \(error.localizedDescription)")
    }

    func sessionWasInterrupted(_ session: ARSession) {
        print("AR Session was interrupted")
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        print("AR Session interruption ended")
        start()
    }
}
