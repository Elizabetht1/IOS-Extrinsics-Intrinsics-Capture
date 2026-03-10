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
            }

        }
        .task {
            model.arSession.start()
        }
        .onDisappear {
            model.arSession.stop()
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
