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
    @Binding var selectedImage: UIImage?
    @Binding var layout: DrawingLayout

    @State private var selectedItem: PhotosPickerItem? = nil
    @State private var imageID = UUID()  // changes per picked photo, so the preview refetches
    @State private var autoState: AutoState = .idle

    enum AutoState { case idle, tuning, tuned, offline }

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
                            imageID = UUID()
                            layout = DrawingLayout()  // new photo starts centred and straight
                        }
                        await autoTune(image)  // never reuse the last picture's filters
                    }
                }
            }

            if let image = selectedImage {
                // Exactly what will be drawn, over the real pit
                VStack(alignment: .leading, spacing: 6) {
                    PitLayoutPreview(
                        requestKey: "\(imageID)|\(Int(threshold))|\(Int(gauss))|\(Int(sharpen))",
                        layout: $layout,
                        fetch: { [threshold, gauss, sharpen] layout in
                            try await RobotService.shared.fetchImagePreview(
                                image, threshold: Int(threshold), gauss: Int(gauss),
                                sharpen: Int(sharpen), layout: layout)
                        },
                        fallback: {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .opacity(0.4)
                                .padding(24)
                        }
                    )
                    PreviewHint(layout: $layout)
                }
                .padding(.horizontal)

                LayoutControls(layout: $layout, showsScale: true)
                    .padding(.horizontal)

                // Processing sliders (auto-tuned per picture, adjustable)
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text(autoCaption)
                            .font(.sandCaption)
                            .foregroundColor(autoState == .offline ? .sandOrange : .sandTextSecondary)
                        Spacer()
                        Button {
                            Task { await autoTune(image) }
                        } label: {
                            Label("Auto", systemImage: "wand.and.stars")
                                .font(.sandCaption)
                                .foregroundColor(.sandGold)
                        }
                        .buttonStyle(.borderless)
                        .disabled(autoState == .tuning)
                    }
                    sliderRow(label: "THRESHOLD", value: $threshold, range: 50...255, step: 1)
                    sliderRow(label: "BLUR", value: $gauss, range: 1...15, step: 2)
                    sliderRow(label: "SHARPEN", value: $sharpen, range: 1...15, step: 1)
                }
                .padding(.horizontal)
            }
        }
        .padding(.vertical)
    }

    private var autoCaption: String {
        switch autoState {
        case .idle: return "FILTERS"
        case .tuning: return "Finding the best settings…"
        case .tuned: return "Auto-tuned for this picture"
        case .offline: return "Robot offline: using default settings"
        }
    }

    /// Ask the Pi for the best filter settings for this picture; fall back
    /// to the defaults (not the last picture's) if it can't be reached.
    private func autoTune(_ image: UIImage) async {
        await MainActor.run { autoState = .tuning }
        let settings: ImageSettings
        let state: AutoState
        if let tuned = try? await RobotService.shared.fetchAutoSettings(image) {
            settings = tuned
            state = .tuned
        } else {
            settings = .defaults
            state = .offline
        }
        await MainActor.run {
            threshold = Double(settings.threshold)
            gauss = Double(settings.gauss)
            sharpen = Double(settings.sharpen)
            autoState = state
        }
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
}
