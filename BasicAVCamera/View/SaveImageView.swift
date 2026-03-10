//
//  SaveImageView.swift (Updated)
//  BasicAVCamera
//
//  Updated to save calibration data
//

import SwiftUI

struct SaveImageView: View {
    @EnvironmentObject var model: CameraModel
    
    @State private var saved = false
    @State private var calibrationSaved = false
    
    private let headerHeight: CGFloat = 90.0

    var body: some View {
            ImageView(image: model.photoToken?.image )
                .padding(.top, headerHeight)
                    .overlay(alignment: .top) {
                        buttonsView()
                            .frame(height: headerHeight)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .background(.gray.opacity(0.4))
                    }
                .padding(.bottom, 16)
                .background(Color.black)
  
    }
    
    private func buttonsView() -> some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    model.photoToken = nil
                    saved = false
                    calibrationSaved = false
                } label: {
                    Image(systemName: "arrowshape.backward.fill")
                }
                
                Spacer()

                Button {
                    guard let photoToken = model.photoToken else { return }
                    Task {
                        await model.photoLibraryManager?.savePhoto(imageData: photoToken.imageData)
                        
                        // NEW: Save calibration data
                        let fileName = "photo_\(UUID().uuidString).jpg"
                        await model.savePhotoCalibration(for: photoToken, fileName: fileName)
                        
                        withAnimation {
                            self.saved = true
                            self.calibrationSaved = photoToken.calibrationData != nil
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1, execute: {
                                self.saved = false
                                self.calibrationSaved = false
                            })
                        }
                    }

                } label: {
                    Image(systemName: saved ? "checkmark" : "square.and.arrow.down")
                }
            }
            .font(.system(size: 24, weight: .bold))
            .foregroundColor(.white)
            
            // NEW: Calibration status indicator
            if saved && calibrationSaved {
                Text("Photo & calibration data saved")
                    .font(.caption)
                    .foregroundColor(.green)
            } else if saved && !calibrationSaved {
                Text("Photo saved (no calibration data)")
                    .font(.caption)
                    .foregroundColor(.yellow)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.horizontal, 32)
        .padding(.top, 32)
    }
}

#Preview {
    @StateObject var model = CameraModel()
    return SaveImageView()
        .environmentObject(model)
}
