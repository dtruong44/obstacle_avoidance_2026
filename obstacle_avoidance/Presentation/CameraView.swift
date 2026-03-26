//
//  CameraView.swift
//  obstacleAvoidance
//
//  Created by Carlos Breach on 12/9/24.
//
import SwiftUI
import RealityKit

struct CameraView: View {
    @StateObject private var model = FrameHandler()

    var body: some View {
        ZStack {
            // 1. The Native AR Camera Feed (Ultra fast, handles itself)
            if model.permissionGranted {
                FrameHandler.CameraPreview(session: model.arSession)
                    .ignoresSafeArea()
            }

            // 2. The Logic & Announcements (Transparent overlay)
            FrameView(image: nil, boundingBoxes: model.boundingBoxes)
            
            // 3. Your Corridor Slices
            CorridorOverlay(corridor: $model.corridorGeometry, stress: model.stress)
        }
        .onAppear {
            model.startCamera()
        }
        .onDisappear {
            model.stopCamera()
        }
    }
}
