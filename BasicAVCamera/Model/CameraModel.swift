//
//  CameraModel.swift (Updated)
//  BasicAVCamera
//
//  Updated to integrate ARKit calibration
//

import AVFoundation
import SwiftUI
import Photos


class CameraModel: ObservableObject {
    
    let camera = CameraManager()
    let arSession = ARSessionManager()  // NEW: AR Session Manager
    var photoLibraryManager: PhotoLibraryManager?
    
    @Published var cameraMode: CameraMode = .photo
    
    @Published var previewImage: Image?
    @Published var photoToken: PhotoData?
    @Published var movieFileUrl: URL?
    
    // Add new property
    @Published var useARPreview = false
    
    // NEW: Current calibration data
    @Published var currentCalibrationData: CameraCalibrationData?
    
    // NEW: Video calibration tracking
    var videoCalibrationFrames: [CameraCalibrationData] = []
    
    
    

    // Add new handler in init()
    


    
    init() {
        Task {
            self.photoLibraryManager = await PhotoLibraryManager()
        }
        
        Task {
            await handleCameraPreviews()
        }
        
        Task {
            await handleCameraPhotos()
        }
        
        Task {
            await handleCameraMovie()
        }
        
        // NEW: Handle AR calibration stream
        Task {
            await handleARCalibration()
        }
        
        Task {
            await handleARPreviews()
        }
    }
    
    // MARK: - Existing Handlers
    
    // for preview camera output
    func handleCameraPreviews() async {
        let imageStream = camera.previewStream
            .map { $0.image }

        for await image in imageStream {
            Task { @MainActor in
                previewImage = image
            }
        }
    }
    
    // NEW method
    func handleARPreviews() async {
        for await ciImage in arSession.previewStream {
            guard useARPreview else { continue }
            Task { @MainActor in
                let ciContext = CIContext()
                guard let cgImage = ciContext.createCGImage(ciImage, from: ciImage.extent) else { return }
                self.previewImage = Image(decorative: cgImage, scale: 1, orientation: .up)
            }
        }
    }

    
    // for photo token
    func handleCameraPhotos() async {
        let unpackedPhotoStream = camera.photoStream
            .compactMap { self.unpackPhoto($0) }
        
        for await photoData in unpackedPhotoStream {
            Task { @MainActor in
                // NEW: Attach current calibration data to photo
                var updatedPhotoData = photoData
                updatedPhotoData.calibrationData = arSession.getCurrentCalibrationData()
                photoToken = updatedPhotoData
            }
        }
    }
    
    // for movie recorded
    func handleCameraMovie() async {
        print("🎬 handleCameraMovie() started - listening for video files")
        let fileUrlStream = arSession.videoStream  // CHANGED
        
        for await url in fileUrlStream {
            print("🎬 Received video URL from stream: \(url)")
            Task { @MainActor in
                movieFileUrl = url
                
                print("🎥 Video saved to: \(url)")
                print("📊 Calibration frames available: \(videoCalibrationFrames.count)")
                
                await saveVideoCalibration(for: url, frames: videoCalibrationFrames)
                
                videoCalibrationFrames.removeAll()
            }
        }
    }
    
    // NEW: Handle AR calibration stream
    func handleARCalibration() async {
        for await calibrationData in arSession.calibrationStream {
            Task { @MainActor [weak self] in
                self?.currentCalibrationData = calibrationData
            }
        }
    }
    
    // MARK: - Video Recording with Calibration
    
    func startRecordingVideo() {
//        camera.startRecordingVideo()
        arSession.startRecordingCalibration()  // NEW: Start AR calibration recording
        arSession.startRecordingVideo()  // NEW: Start AR calibration recording
    }
    
    func stopRecordingVideo() {
//        camera.stopRecordingVideo()
        arSession.stopRecordingVideo()
//        arSession.stopRecordingCalibration()
        // Calibration stop is handled in handleCameraMovie when URL arrives
    }
    
    // MARK: - Save Methods
    
    private func saveVideoCalibration(for videoURL: URL, frames: [CameraCalibrationData]) async {
        
        print("[DEBUG] attempting to save calibratio ndata.")
        guard !frames.isEmpty else {
            print("No calibration data to save for video")
            return
        }
        
        let directory = videoURL.deletingLastPathComponent()
        let fileName = videoURL.lastPathComponent
        
        do {
            try await arSession.saveVideoCalibrationData(
                frames: frames,
                videoFileName: fileName,
                to: directory
            )
        } catch {
            print("Failed to save video calibration: \(error)")
        }
    }
    
    func savePhotoCalibration(for photoData: PhotoData, fileName: String) async {
        guard let calibrationData = photoData.calibrationData else {
            print("No calibration data available for photo")
            return
        }
        
        guard let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            print("Cannot access documents directory")
            return
        }
        
        do {
            try await arSession.savePhotoCalibrationData(
                calibrationData,
                photoFileName: fileName,
                to: directory
            )
        } catch {
            print("Failed to save photo calibration: \(error)")
        }
    }

    // MARK: - Existing Helper Methods
    
    private func unpackPhoto(_ photo: AVCapturePhoto) -> PhotoData? {
        guard let imageData = photo.fileDataRepresentation() else { return nil }
        guard let cgImage = photo.cgImageRepresentation(),
              let metadataOrientation = photo.metadata[String(kCGImagePropertyOrientation)] as? UInt32,
              let cgImageOrientation = CGImagePropertyOrientation(rawValue: metadataOrientation)
        else { return nil }
        
        let imageOrientation = UIImage.Orientation(cgImageOrientation)
        let image = Image(uiImage: UIImage(cgImage: cgImage, scale: 1, orientation: imageOrientation))
        
        let photoDimensions = photo.resolvedSettings.photoDimensions
        let imageSize = (width: Int(photoDimensions.width), height: Int(photoDimensions.height))

        return PhotoData(image: image, imageData: imageData, imageSize: imageSize, calibrationData: nil)
    }
}


fileprivate extension CIImage {
    var image: Image? {
        let ciContext = CIContext()
        guard let cgImage = ciContext.createCGImage(self, from: self.extent) else { return nil }
        return Image(decorative: cgImage, scale: 1, orientation: .up)
    }
}


fileprivate extension UIImage.Orientation {

    init(_ cgImageOrientation: CGImagePropertyOrientation) {
        switch cgImageOrientation {
        case .up: self = .up
        case .upMirrored: self = .upMirrored
        case .down: self = .down
        case .downMirrored: self = .downMirrored
        case .left: self = .left
        case .leftMirrored: self = .leftMirrored
        case .right: self = .right
        case .rightMirrored: self = .rightMirrored
        }
    }
}
