//
//  LiveCameraView.swift
//  SandBot
//
//  MJPEG client for the Pi camera (camera_stream.py on port 8000). Frames are
//  split out of the multipart stream by JPEG start/end markers.
//

import SwiftUI
import Combine

@MainActor
final class MJPEGStream: NSObject, ObservableObject {
    @Published private(set) var image: UIImage? = nil
    @Published private(set) var fps: Double = 0
    @Published private(set) var error: String? = nil

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var buffer = Data()
    private var frameTimes: [Date] = []
    private var retryTask: Task<Void, Never>?

    /// Camera stream lives on the same host as the bridge, port 8000.
    nonisolated static var defaultURL: URL {
        let host = UserDefaults.standard.string(forKey: "robotHost") ?? "100.95.15.84:8080"
        let ip = host.split(separator: ":").first.map(String.init) ?? host
        return URL(string: "http://\(ip):8000/video")!
    }

    func start(url: URL = MJPEGStream.defaultURL) {
        stop()
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config, delegate: self, delegateQueue: .main)
        task = session?.dataTask(with: url)
        task?.resume()
    }

    func stop() {
        retryTask?.cancel()
        task?.cancel()
        session?.invalidateAndCancel()
        task = nil
        session = nil
        buffer.removeAll()
    }

    fileprivate func receive(_ data: Data) {
        buffer.append(data)
        // Pull every complete JPEG (FFD8 … FFD9) out of the buffer, keep the newest.
        var newest: Data? = nil
        while let soi = buffer.firstRange(of: Data([0xFF, 0xD8])),
              let eoi = buffer.firstRange(of: Data([0xFF, 0xD9]), in: soi.upperBound..<buffer.endIndex) {
            newest = buffer.subdata(in: soi.lowerBound..<eoi.upperBound)
            buffer.removeSubrange(buffer.startIndex..<eoi.upperBound)
        }
        if buffer.count > 5_000_000 { buffer.removeAll() }  // never grow unbounded
        guard let jpeg = newest, let frame = UIImage(data: jpeg) else { return }
        image = frame
        error = nil
        let now = Date()
        frameTimes = frameTimes.filter { now.timeIntervalSince($0) < 2 } + [now]
        fps = Double(frameTimes.count) / 2
    }

    fileprivate func finished(_ ended: URLSessionTask, with err: Error?) {
        guard ended === task else { return }  // an old or deliberately stopped connection
        error = err?.localizedDescription ?? "Stream ended"
        fps = 0
        retryTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            self?.start()
        }
    }
}

extension MJPEGStream: URLSessionDataDelegate {
    nonisolated func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        MainActor.assumeIsolated {
            guard dataTask === task else { return }
            receive(data)
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        MainActor.assumeIsolated { finished(task, with: error) }
    }
}

/// Live camera frame, auto-starting/stopping with visibility and reconnecting on drops.
struct LiveCameraView: View {
    @StateObject private var stream = MJPEGStream()
    var showsFPS = true

    var body: some View {
        ZStack {
            Color(hex: "#0A0A0A")
            if let image = stream.image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                VStack(spacing: 10) {
                    if stream.error == nil {
                        ProgressView().tint(Color.sandGold)
                        Text("Connecting to camera…")
                    } else {
                        Image(systemName: "video.slash").font(.system(size: 32))
                        Text("Camera unavailable")
                        Text("Is camera_stream.py running on the Pi?")
                            .font(.sandCaption)
                    }
                }
                .font(.sandBody)
                .foregroundColor(.sandTextSecondary)
                .multilineTextAlignment(.center)
            }
            if showsFPS, stream.image != nil {
                VStack {
                    HStack {
                        Spacer()
                        HStack(spacing: 6) {
                            Circle().fill(stream.error == nil ? Color.sandError : Color.sandTextSecondary)
                                .frame(width: 8, height: 8)
                            Text(stream.error == nil ? String(format: "LIVE  %.0f fps", stream.fps) : "RECONNECTING")
                                .font(.sandCaption)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.black.opacity(0.5))
                        .cornerRadius(6)
                    }
                    Spacer()
                }
                .padding(10)
            }
        }
        .aspectRatio(16 / 9, contentMode: .fit)
        .onAppear { stream.start() }
        .onDisappear { stream.stop() }
    }
}
