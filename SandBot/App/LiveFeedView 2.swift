//
//  LiveFeedView 2.swift
//  SandBot
//
//  Created by Anderson Colburn on 9/13/26.
//


//
//  LiveFeedView.swift
//  SandBot
//
//  Camera feed view — snapshots and progress checks from the Pi camera.
//

import SwiftUI

struct LiveFeedView: View {
    @EnvironmentObject var statusMonitor: RobotStatusMonitor
    @State private var currentImage: UIImage? = nil
    @State private var isLoading: Bool = false
    @State private var errorMessage: String? = nil
    @State private var lastCaptureTime: String = ""

    private var baseURL: String {
        let host = UserDefaults.standard.string(forKey: "robotHost") ?? "100.95.15.84:8080"
        return "http://\(host)"
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sandBgPrimary.ignoresSafeArea()
                VStack(spacing: 16) {

                    // Image display
                    ZStack {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.sandSurface)

                        if let image = currentImage {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                                .cornerRadius(8)
                                .padding(4)
                        } else if isLoading {
                            VStack(spacing: 12) {
                                ProgressView()
                                    .tint(Color.sandGold)
                                    .scaleEffect(1.5)
                                Text("Capturing...")
                                    .font(.sandCaption)
                                    .foregroundColor(.sandTextSecondary)
                            }
                        } else {
                            VStack(spacing: 12) {
                                Image(systemName: "camera")
                                    .font(.system(size: 48))
                                    .foregroundColor(.sandTextSecondary.opacity(0.5))
                                Text("No image yet")
                                    .font(.sandBody)
                                    .foregroundColor(.sandTextSecondary)
                                Text("Take a snapshot or check progress")
                                    .font(.sandCaption)
                                    .foregroundColor(.sandTextSecondary.opacity(0.7))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 300)
                    .padding(.horizontal)

                    // Timestamp
                    if !lastCaptureTime.isEmpty {
                        Text("Captured: \(lastCaptureTime)")
                            .font(.sandCaption)
                            .foregroundColor(.sandTextSecondary)
                    }

                    // Error
                    if let error = errorMessage {
                        Text(error)
                            .font(.sandCaption)
                            .foregroundColor(.sandError)
                            .padding(.horizontal)
                    }

                    Spacer()

                    // Action buttons
                    VStack(spacing: 12) {
                        // Snapshot — just takes a photo from wherever the arm is
                        Button(action: { Task { await takeSnapshot() } }) {
                            HStack {
                                Image(systemName: "camera.fill")
                                Text("Take Snapshot")
                            }
                            .font(.sandBody)
                            .foregroundColor(.sandBgPrimary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.sandGold)
                            .cornerRadius(8)
                        }
                        .disabled(isLoading || statusMonitor.connectionStatus == .offline)
                        .buttonStyle(.borderless)

                        // Progress check — lifts arm, takes photo, returns
                        Button(action: { Task { await checkProgress() } }) {
                            HStack {
                                Image(systemName: "eye.fill")
                                Text("Show Me Progress")
                            }
                            .font(.sandBody)
                            .foregroundColor(.sandGold)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color.sandSurface)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.sandGold.opacity(0.5), lineWidth: 1)
                            )
                            .cornerRadius(8)
                        }
                        .disabled(isLoading || statusMonitor.connectionStatus == .offline)
                        .buttonStyle(.borderless)

                        // Save to photos
                        if currentImage != nil {
                            Button(action: saveToPhotos) {
                                HStack {
                                    Image(systemName: "square.and.arrow.down")
                                    Text("Save to Photos")
                                }
                                .font(.sandBody)
                                .foregroundColor(.sandTextSecondary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.sandSurface)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.sandBorder, lineWidth: 1)
                                )
                                .cornerRadius(8)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
            }
            .navigationTitle("Camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    StatusPill(status: statusMonitor.connectionStatus)
                }
            }
        }
    }

    // MARK: - Actions

    private func takeSnapshot() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let url = URL(string: "\(baseURL)/camera/snapshot")!
            let (data, response) = try await URLSession.shared.data(from: url)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let image = UIImage(data: data) else {
                throw CameraError.captureFailed
            }

            await MainActor.run {
                currentImage = image
                lastCaptureTime = formatTime()
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Snapshot failed: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private func checkProgress() async {
        await MainActor.run {
            isLoading = true
            errorMessage = nil
        }

        do {
            let url = URL(string: "\(baseURL)/camera/progress")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.timeoutInterval = 20

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200,
                  let image = UIImage(data: data) else {
                throw CameraError.captureFailed
            }

            await MainActor.run {
                currentImage = image
                lastCaptureTime = formatTime()
                isLoading = false
            }
        } catch {
            await MainActor.run {
                errorMessage = "Progress check failed: \(error.localizedDescription)"
                isLoading = false
            }
        }
    }

    private func saveToPhotos() {
        guard let image = currentImage else { return }
        UIImageWriteToSavedPhotosAlbum(image, nil, nil, nil)
        errorMessage = nil
        lastCaptureTime = "\(lastCaptureTime) — Saved!"
    }

    private func formatTime() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm:ss a"
        return formatter.string(from: Date())
    }
}

enum CameraError: LocalizedError {
    case captureFailed

    var errorDescription: String? {
        switch self {
        case .captureFailed: return "Could not capture image from camera"
        }
    }
}
