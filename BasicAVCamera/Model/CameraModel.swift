//
//  CameraModel.swift
//  SwiftUIDemo2
//
//  Created by Itsuki on 2024/05/18.
//

import AVFoundation
import SwiftUI
import Photos


class CameraModel: ObservableObject {

    let camera = CameraManager()
    var photoLibraryManager: PhotoLibraryManager?

    @Published var cameraMode: CameraMode = .photo

    @Published var previewImage: Image?
    @Published var photoToken: PhotoData?
    @Published var movieFileUrl: URL?

    
    init() {
        print("🔵 CameraModel init started")
        
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

    }
    
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

    @MainActor
    func handleARPreviews() async {
        for await cgImage in arSession.previewStream {
            self.previewImage = Image(decorative: cgImage, scale: 1, orientation: .up)
        }
    }

    // MARK: - Photo Handling

    func handleCameraPhotos() async {
        let unpackedPhotoStream = camera.photoStream
            .compactMap { self.unpackPhoto($0) }

        for await photoData in unpackedPhotoStream {
            Task { @MainActor in
                photoToken = photoData
            }
        }
    }

    // MARK: - Video Handling

    func handleCameraMovie() async {
        for await url in arSession.videoStream {
            Task { @MainActor in
                movieFileUrl = url
                
                // NEW: Stop recording calibration when video stops
                let frames = arSession.stopRecordingCalibration()
                videoCalibrationFrames = frames
                
                // Save calibration data alongside video
                await saveVideoCalibration(for: url, frames: frames)
            }
        }
    }
    

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
