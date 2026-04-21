//
//  ImageDrawView.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/20/26.
//

import SwiftUI
import PhotosUI

struct ImageDrawView: View {
    @Binding var strokes: [Stroke]

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var selectedImage: UIImage? = nil
    @State private var threshold: Float = 0.5
    @State private var isProcessing: Bool = false
    @State private var showEdges: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Photo picker
            PhotosPicker(
                selection: $selectedItem,
                matching: .images,
                photoLibrary: .shared()
            ) {
                HStack {
                    Image(systemName: "photo.badge.plus")
                        .foregroundColor(.sandGold)
                    Text(selectedImage == nil ? "Choose Photo" : "Change Photo")
                        .font(.sandBody)
                        .foregroundColor(.sandGold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.sandSurface)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.sandGold.opacity(0.5), lineWidth: 1)
                )
                .cornerRadius(8)
            }
            .padding(.horizontal)
            .onChange(of: selectedItem) {
                guard let item = selectedItem else { return }
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        await MainActor.run { selectedImage = image }
                        await runEdgeDetection(on: image)
                    }
                }
            }

            // Image preview
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .cornerRadius(8)
                    .opacity(showEdges ? 0.3 : 1.0)
                    .overlay {
                        if isProcessing {
                            ProgressView().tint(Color.sandGold)
                        }
                    }
                    .padding(.horizontal)

                // Toggle
                Toggle(isOn: $showEdges) {
                    Text("Show Edges")
                        .font(.sandBody)
                        .foregroundColor(.sandTextSecondary)
                }
                .tint(Color.sandGold)
                .padding(.horizontal)

                // Threshold slider
                VStack(alignment: .leading, spacing: 6) {
                    Text("EDGE THRESHOLD")
                        .font(.sandCaption)
                        .foregroundColor(.sandTextSecondary)
                    HStack(spacing: 10) {
                        Text("More")
                            .font(.sandCaption)
                            .foregroundColor(.sandTextSecondary)
                        Slider(value: $threshold, in: 0.1...0.9)
                            .tint(Color.sandGold)
                            .onChange(of: threshold) {
                                guard let image = selectedImage else { return }
                                let capturedImage = image
                                Task {
                                    await runEdgeDetection(on: capturedImage)
                                }
                            }
                        Text("Less")
                            .font(.sandCaption)
                            .foregroundColor(.sandTextSecondary)
                    }
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }

    private func runEdgeDetection(on image: UIImage) async {
        await MainActor.run { isProcessing = true }
        let result = await Task.detached(priority: .userInitiated) {
            EdgeDetectionService.shared.detectEdges(from: image, threshold: self.threshold)
        }.value
        await MainActor.run {
            strokes = result
            isProcessing = false
        }
    }
}
