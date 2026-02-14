//
//  BasicAVCameraApp.swift
//  BasicAVCamera
//
//  Created by Itsuki on 2024/05/19.
//

import SwiftUI

@main
struct BasicAVCameraApp: App {
    init() {
        print("========================================")
                print("🚀 APP LAUNCHED")
                print("========================================")
    }
    var body: some Scene {
        WindowGroup {
            CameraView()

        }
    }
}
