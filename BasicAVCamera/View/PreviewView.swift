//
//  PreviewView.swift (Updated)
//  BasicAVCamera
//
//  Updated to show AR tracking status
//

import SwiftUI
import ARKit

struct PreviewView: View {
    @EnvironmentObject var model: CameraModel
    @State private var isRecording: Bool = false

    private let footerHeight: CGFloat = 110.0
    private let headerHeight: CGFloat = 50.0

    var body: some View {
        
        ImageView(image: model.previewImage )
            .padding(.bottom, footerHeight)
            .padding(.top, headerHeight)
            .overlay(alignment: .top) {
                // NEW: AR tracking status
                trackingStatusView()
                    .frame(height: headerHeight)
            }
            .overlay(alignment: .bottom) {
                buttonsView()
                    .frame(height: footerHeight)
                    .background(.gray.opacity(0.4))
            }
            .background(Color.black)

    }
    
    // NEW: Tracking status indicator
    private func trackingStatusView() -> some View {
        HStack {
            Circle()
                .fill(trackingStateColor)
                .frame(width: 12, height: 12)
            
            Text(trackingStateText)
                .font(.caption)
                .foregroundColor(.white)
            
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }
    
    private var trackingStateColor: Color {
        switch model.arSession.trackingState {
        case .normal:
            return .green
        case .limited:
            return .yellow
        case .notAvailable:
            return .red
        }
    }
    
    private var trackingStateText: String {
        switch model.arSession.trackingState {
        case .normal:
            return "AR Tracking: Ready"
        case .limited(let reason):
            switch reason {
            case .excessiveMotion:
                return "AR Tracking: Move Slower"
            case .insufficientFeatures:
                return "AR Tracking: Point at Textured Surface"
            case .initializing:
                return "AR Tracking: Initializing..."
            case .relocalizing:
                return "AR Tracking: Relocalizing..."
            @unknown default:
                return "AR Tracking: Limited"
            }
        case .notAvailable:
            return "AR Tracking: Not Available"
        }
    }

    private func buttonsView() -> some View {
        GeometryReader { geometry in
            let frameHeight = geometry.size.height
            HStack {

                Button {
                    model.cameraMode.toggle()
                } label: {
                    Image(systemName: model.cameraMode == .photo ? "video.fill" : "camera.fill")

                }
                
                Spacer()

                if model.cameraMode == .photo {
                    Button {
                        model.camera.takePhoto()
                    } label: {
                        ZStack {
                            Circle()
                                .strokeBorder(.white, lineWidth: 3)
                                .frame(width: frameHeight, height:  frameHeight)
                            Circle()
                                .fill(.white)
                                .frame(width:  frameHeight-10, height: frameHeight-10)

                        }
                    }
                } else {
                    Button {
                        if isRecording {
                            isRecording = false
                            model.stopRecordingVideo()  // UPDATED: Use model method
                        } else {
                            isRecording = true
                            model.startRecordingVideo()  // UPDATED: Use model method
                        }
                    } label: {
                        Image(systemName: "record.circle")
                            .symbolEffect(.pulse, isActive: isRecording)
                            .foregroundStyle(isRecording ? Color.red : Color.white)
                            .font(.system(size: 50))
                    }
                    
                }

                Spacer()

                Button {
                    model.camera.switchCaptureDevice()
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }

            }
            .font(.system(size: 28, weight: .bold))
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .center)
            
        }
        .padding(.vertical, 24)
        .padding(.bottom, 8)
        .padding(.horizontal, 32)

    }
}

#Preview {
    @StateObject var model = CameraModel()
    return PreviewView()
        .environmentObject(model)
}
