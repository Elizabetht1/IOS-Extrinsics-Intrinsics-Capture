//
//  CameraModel.swift
//  BasicAVCamera
//

import AVFoundation
import SwiftUI
import Photos


class CameraModel: ObservableObject {

    let camera = CameraManager()
    let arSession = ARSessionManager()
    var photoLibraryManager: PhotoLibraryManager?

    @Published var cameraMode: CameraMode = .photo

    @Published var previewImage: Image?
    @Published var photoToken: PhotoData?
    @Published var movieFileUrl: URL?

    @Published var currentCalibrationData: CameraCalibrationData?

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

        Task {
            await handleARCalibration()
        }

        Task {
            await handleARPreviews()
        }
    }

    // MARK: - Preview Handlers

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
                var updatedPhotoData = photoData
                updatedPhotoData.calibrationData = arSession.getCurrentCalibrationData()
                photoToken = updatedPhotoData
            }
        }
    }

    // MARK: - Video Handling

    func handleCameraMovie() async {
        for await url in arSession.videoStream {
            Task { @MainActor in
                movieFileUrl = url
            }
        }
    }

    // MARK: - Calibration Stream

    @MainActor
    func handleARCalibration() async {
        for await calibrationData in arSession.calibrationStream {
            self.currentCalibrationData = calibrationData
        }
    }

    // MARK: - Video Recording

    func startRecordingVideo() {
        arSession.startRecording()
    }

    func stopRecordingVideo() {
        arSession.stopRecording { [weak self] url, frames in
            guard let self = self, let url = url else { return }
            Task { @MainActor in
                await self.saveVideoCalibration(for: url, frames: frames)
            }
        }
    }

    // MARK: - Save Methods

    private func saveVideoCalibration(for videoURL: URL, frames: [CameraCalibrationData]) async {
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

    // MARK: - Helper Methods

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
