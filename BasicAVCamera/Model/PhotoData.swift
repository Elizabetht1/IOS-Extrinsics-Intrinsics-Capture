//
//  PhotoData.swift (Updated)
//  BasicAVCamera
//
//  Updated to include calibration data
//

import SwiftUI

struct PhotoData {
    var image: Image
    var imageData: Data
    var imageSize: (width: Int, height: Int)
    
    // AR Calibration data
    var calibrationData: CameraCalibrationData?
}
