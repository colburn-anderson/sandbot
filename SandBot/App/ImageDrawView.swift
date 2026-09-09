//
//  ImageDrawView.swift
//  SandBot
//
//  Rewritten for Freenove bridge integration.
//  Image processing now happens on the Pi, not on-device.
//

import SwiftUI
import PhotosUI

struct ImageDrawView: View {
    @Binding var previewImage: UIImage?
    @Binding var selectedImage: UIImage?

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var isLoadingPreview: Bool = false

    // Processing sliders (matching the Freenove GUI defaults)
    @Binding var threshold: Double
    @Binding var gauss: Double
    @Binding var sharpen: Double

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
                        await MainActor.run {
                            selectedImage = image
                        }
                        await fetchPreview()
                    }
                }
            }

            if let image = selectedImage {
                // Show original or contour preview
                ZStack {
                    if let preview = previewImage {
                        Image(uiImage: preview)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(8)
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(8)
                            .opacity(0.5)
                    }

                    if isLoadingPreview {
                        ProgressView()
                            .tint(Color.sandGold)
                            .scaleEffect(1.5)
                    }
                }
                .padding(.horizontal)

                // Processing sliders
                VStack(alignment: .leading, spacing: 12) {
                    sliderRow(label: "THRESHOLD", value: $threshold, range: 50...255, step: 1)
                    sliderRow(label: "BLUR", value: $gauss, range: 1...15, step: 2)
                    sliderRow(label: "SHARPEN", value: $sharpen, range: 1...15, step: 1)
                }
                .padding(.horizontal)
                .onChange(of: threshold) { _ in Task { await fetchPreview() } }
                .onChange(of: gauss) { _ in Task { await fetchPreview() } }
                .onChange(of: sharpen) { _ in Task { await fetchPreview() } }
            }
        }
        .padding(.vertical)
    }

    private func sliderRow(label: String, value: Binding<Double>, range: ClosedRange<Double>, step: Double) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                    .font(.sandCaption)
                    .foregroundColor(.sandTextSecondary)
                Spacer()
                Text("\(Int(value.wrappedValue))")
                    .font(.sandCaption)
                    .foregroundColor(.sandGold)
            }
            Slider(value: value, in: range, step: step)
                .tint(Color.sandGold)
        }
    }

    private func fetchPreview() async {
        guard let image = selectedImage else { return }
        await MainActor.run { isLoadingPreview = true }

        do {
            let result = try await RobotService.shared.fetchPreview(
                image,
                threshold: Int(threshold),
                gauss: Int(gauss),
                sharpen: Int(sharpen)
            )
            await MainActor.run {
                previewImage = result
                isLoadingPreview = false
            }
        } catch {
            print("Preview fetch failed: \(error)")
            await MainActor.run { isLoadingPreview = false }
        }
    }
}
