//
//  CameraView.swift (Updated)
//  BasicAVCamera
//
//  Updated to start AR session
//

import SwiftUI

struct CameraView: View {
    @StateObject private var model = CameraModel()

    var body: some View {

        ZStack {
            if let _ = model.photoToken {
                SaveImageView()
            } else if let _ = model.movieFileUrl {
                SaveVideoView()
            } else {
                PreviewView()
                    .onAppear {
                        model.camera.isPreviewPaused = false
                    }
                    .onDisappear {
                        model.camera.isPreviewPaused = true
                    }
            }

        }
        .task {
            // Start both camera and AR session
            
            model.arSession.start()  // NEW: Start AR session
//            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 sec
//            await model.camera.start()
        }
        .onDisappear {
            // Stop AR session when view disappears
            model.arSession.stop()  // NEW: Stop AR session
        }
        .ignoresSafeArea(.all)
        .environmentObject(model)
    }
}


#Preview {
    @StateObject var model = CameraModel()
    return SaveImageView()
        .environmentObject(model)
}
