//
//  CameraCalibrationData.swift
//  BasicAVCamera
//
//  Created by Elizabeth Terveen on 2/14/26.
//


//
//  CameraCalibrationData.swift
//  BasicAVCamera
//
//  Created for AR Integration
//

import Foundation
import simd
import ARKit

struct FocalLength: Codable {
    var fx: Float
    var fy: Float
}

struct PrincipalPoint: Codable {
    var cx: Float
    var cy: Float
}

struct ImageResolution: Codable {
    var width: Float
    var height: Float
}

struct EulerAngles: Codable {
    var roll: Float
    var pitch: Float
    var yaw: Float
}

/// Complete camera calibration data including intrinsics and extrinsics
struct CameraCalibrationData: Codable {
    
    // MARK: - Intrinsic Parameters
    
    /// 3x3 intrinsic camera matrix
    /// [[fx, 0, cx],
    ///  [0, fy, cy],
    ///  [0,  0,  1]]
    var intrinsicMatrix: [[Float]]
    
    /// Focal lengths in pixels
    var focalLength: FocalLength
    
    /// Principal point (optical center) in pixels
    var principalPoint: PrincipalPoint
    
    /// Image resolution that intrinsics correspond to
    var imageResolution: ImageResolution
    
    // MARK: - Extrinsic Parameters
    
    /// 4x4 transformation matrix (camera pose in world coordinates)
    /// Represents position and orientation of camera in 3D space
    var transformMatrix: [[Float]]
    
    /// 3x3 rotation matrix extracted from transform
    var rotationMatrix: [[Float]]
    
    /// Translation vector (camera position in world) [x, y, z]
    var translationVector: [Float]
    
    /// Euler angles (roll, pitch, yaw) in radians
    var eulerAngles: EulerAngles
    
    // MARK: - Additional Information
    
    /// 4x4 projection matrix
    var projectionMatrix: [[Float]]
    
    /// Timestamp of the frame
    var timestamp: TimeInterval
    
    /// Frame index (if recording video)
    var frameIndex: Int?
    
    /// Tracking state quality
    var trackingState: String
    
    /// Tracking state reason (if limited)
    var trackingStateReason: String?
    
    // MARK: - Initializer from ARFrame
    
    init(from arFrame: ARFrame, frameIndex: Int? = nil) {
        let camera = arFrame.camera
        
        // Intrinsics
        let intrinsics = camera.intrinsics
        self.intrinsicMatrix = [
            [intrinsics[0, 0], intrinsics[0, 1], intrinsics[0, 2]],
            [intrinsics[1, 0], intrinsics[1, 1], intrinsics[1, 2]],
            [intrinsics[2, 0], intrinsics[2, 1], intrinsics[2, 2]]
        ]
        
        self.focalLength = FocalLength(fx: intrinsics[0, 0], fy: intrinsics[1, 1])
        self.principalPoint = PrincipalPoint(cx: intrinsics[2, 0], cy: intrinsics[2, 1])
        
        let resolution = camera.imageResolution
        self.imageResolution = ImageResolution(width: Float(resolution.width), height: Float(resolution.height))
        
        // Extrinsics
        let transform = camera.transform
        self.transformMatrix = [
            [transform[0, 0], transform[0, 1], transform[0, 2], transform[0, 3]],
            [transform[1, 0], transform[1, 1], transform[1, 2], transform[1, 3]],
            [transform[2, 0], transform[2, 1], transform[2, 2], transform[2, 3]],
            [transform[3, 0], transform[3, 1], transform[3, 2], transform[3, 3]]
        ]
        
        // Extract rotation (upper-left 3x3)
        self.rotationMatrix = [
            [transform[0, 0], transform[0, 1], transform[0, 2]],
            [transform[1, 0], transform[1, 1], transform[1, 2]],
            [transform[2, 0], transform[2, 1], transform[2, 2]]
        ]
        
        // Extract translation (4th column, first 3 rows)
        self.translationVector = [transform[3, 0], transform[3, 1], transform[3, 2]]
        
        // Euler angles
        let eulerAngles = camera.eulerAngles
        self.eulerAngles = EulerAngles(roll: eulerAngles.x, pitch: eulerAngles.y, yaw: eulerAngles.z)
        
        // Projection matrix
        let projection = camera.projectionMatrix
        self.projectionMatrix = [
            [projection[0, 0], projection[0, 1], projection[0, 2], projection[0, 3]],
            [projection[1, 0], projection[1, 1], projection[1, 2], projection[1, 3]],
            [projection[2, 0], projection[2, 1], projection[2, 2], projection[2, 3]],
            [projection[3, 0], projection[3, 1], projection[3, 2], projection[3, 3]]
        ]
        
        // Metadata
        self.timestamp = arFrame.timestamp
        self.frameIndex = frameIndex
        
        // Tracking state
        switch camera.trackingState {
        case .normal:
            self.trackingState = "normal"
            self.trackingStateReason = nil
        case .limited(let reason):
            self.trackingState = "limited"
            switch reason {
            case .excessiveMotion:
                self.trackingStateReason = "excessiveMotion"
            case .insufficientFeatures:
                self.trackingStateReason = "insufficientFeatures"
            case .initializing:
                self.trackingStateReason = "initializing"
            case .relocalizing:
                self.trackingStateReason = "relocalizing"
            @unknown default:
                self.trackingStateReason = "unknown"
            }
        case .notAvailable:
            self.trackingState = "notAvailable"
            self.trackingStateReason = nil
        }
    }
    
    // MARK: - Helper Methods
    
    /// Export as JSON string
    func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
    
    /// Export as dictionary
    func toDictionary() -> [String: Any] {
        return [
            "intrinsics": [
                "matrix": intrinsicMatrix,
                "focal_length": ["fx": focalLength.fx, "fy": focalLength.fy],
                "principal_point": ["cx": principalPoint.cx, "cy": principalPoint.cy],
                "image_resolution": ["width": imageResolution.width, "height": imageResolution.height]
            ],
            "extrinsics": [
                "transform_matrix": transformMatrix,
                "rotation_matrix": rotationMatrix,
                "translation_vector": translationVector,
                "euler_angles": ["roll": eulerAngles.roll, "pitch": eulerAngles.pitch, "yaw": eulerAngles.yaw]
            ],
            "projection_matrix": projectionMatrix,
            "timestamp": timestamp,
            "frame_index": frameIndex as Any,
            "tracking_state": trackingState,
            "tracking_state_reason": trackingStateReason as Any
        ]
    }
}

/// Collection of calibration data for video (multiple frames)
struct VideoCalibrationData: Codable {
    var frames: [CameraCalibrationData]
    var videoFileName: String
    var recordingStartTime: TimeInterval
    var recordingEndTime: TimeInterval
    var totalFrames: Int
    
    /// Export as JSON string
    func toJSON() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self),
              let json = String(data: data, encoding: .utf8) else {
            return nil
        }
        return json
    }
}
