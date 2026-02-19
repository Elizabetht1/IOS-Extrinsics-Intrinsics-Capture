# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

iOS camera app that captures photos/video **with ARKit camera calibration data** (intrinsics and extrinsics). Built with SwiftUI and AVFoundation, extended with ARKit to record per-frame camera matrices alongside media. The calibration data is exported as JSON.

- **Bundle ID**: `lpwm-extriniscs-intrinsics-capture`
- **Deployment target**: iOS 17.4
- **Swift**: 5.0
- **Frameworks**: SwiftUI, AVFoundation, ARKit, Photos, Combine

## Build & Run

This is an Xcode project (`BasicAVCamera.xcodeproj`) with no SPM dependencies or CocoaPods. Build and run via Xcode or:

```bash
xcodebuild -project BasicAVCamera.xcodeproj -scheme BasicAVCamera -destination 'platform=iOS,name=<DEVICE_NAME>' build
```

**Must run on a physical device** — ARKit (ARWorldTrackingConfiguration) requires real hardware, not the simulator.

There are no tests configured.

## Architecture

### Data Flow (active branch: ARSession)

The app is transitioning from `CameraManager` (AVCaptureSession) to `ARSessionManager` (ARSession) as the sole capture source. Currently, video recording and preview use the AR session; photo capture still goes through the legacy `CameraManager`.

```
CameraView (root)
  └─ CameraModel (@StateObject, acts as ViewModel)
       ├─ ARSessionManager — AR session, preview frames, video recording, calibration capture
       ├─ CameraManager — legacy AVCaptureSession (still used for photo capture)
       └─ PhotoLibraryManager — saves media to photo library
```

### Key data paths

- **Preview**: `ARSessionManager.previewStream` (AsyncStream<CIImage>) → `CameraModel.handleARPreviews()` → `previewImage` → `PreviewView` → `ImageView`
- **Video recording**: `ARSessionManager` uses `AVAssetWriter` to encode `ARFrame.capturedImage` pixel buffers. On stop, the video URL is yielded through `videoStream` → `CameraModel.handleCameraMovie()` → `SaveVideoView`
- **Calibration**: Each `ARFrame` is converted to `CameraCalibrationData` (intrinsics matrix, extrinsics/transform, euler angles, projection matrix, tracking state). During video recording, frames are accumulated and saved as `<videoname>_calibration.json`.
- **Photo**: `CameraManager.photoStream` → `CameraModel.handleCameraPhotos()` (attaches current AR calibration snapshot) → `SaveImageView`

### Models

- `CameraCalibrationData` — Codable struct holding intrinsic matrix (fx, fy, cx, cy), extrinsic 4x4 transform, rotation, translation, euler angles, projection matrix, tracking state. Initialized from `ARFrame`.
- `VideoCalibrationData` — wraps an array of `CameraCalibrationData` frames for a video recording session.
- `PhotoData` — image + optional calibration snapshot.
- `CameraMode` — enum toggling between `.photo` and `.video`.

### Threading

- `ARSessionManager` and `CameraManager` each use their own serial `DispatchQueue` ("ar.session.queue" / "session queue").
- `ARSessionDelegate` callbacks arrive on the session queue; UI updates are dispatched to `@MainActor`.
- Video frame writing (`AVAssetWriter`) happens synchronously within the AR delegate callback.
