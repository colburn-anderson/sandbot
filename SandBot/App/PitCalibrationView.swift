//
//  PitCalibrationView.swift
//  SandBot
//
//  Trace the sand pit's rim with the pen to set the drawing boundary.
//  Jog the pen to the inside edge of the rim, record a point, repeat all the
//  way around (both lobes and the notch), then save. The bridge smooths the
//  points into the kidney outline and refuses any move that leaves it.
//

import SwiftUI

private struct PenPosition: Decodable {
    let known: Bool
    let x: Double?
    let y: Double?
    let z: Double?
    let inside: Bool?
    let points: [[Double]]
}

private struct ServerError: Decodable { let error: String }

private struct ViewPosition: Decodable { let x, y, z: Double }

private enum CalibrationAPI {
    static var baseURL: String {
        "http://\(UserDefaults.standard.string(forKey: "robotHost") ?? "100.95.15.84:8080")"
    }

    static func call<T: Decodable>(_ path: String, method: String = "POST", body: [String: Double]? = nil) async throws -> T {
        var request = URLRequest(url: URL(string: baseURL + path)!)
        request.httpMethod = method
        request.timeoutInterval = 15
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        let (data, _) = try await URLSession.shared.data(for: request)
        if let err = try? JSONDecoder().decode(ServerError.self, from: data) {
            throw RobotError.serverError(err.error)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

struct PitCalibrationView: View {
    @ObservedObject private var store = PitBoundaryStore.shared

    @State private var position: PenPosition? = nil
    @State private var step: Double = 5
    @State private var busy = false
    @State private var message = ""
    @State private var isError = false
    @State private var safeZ: Double = 200

    var body: some View {
        ZStack {
            Color.sandBgPrimary.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 20) {
                    Text("Watch the camera and lower the pen just above the sand, then jog it to the inside edge of the rim and tap Record. Work your way all the way around — both lobes and the notch. 12–20 points is plenty.")
                        .font(.sandCaption)
                        .foregroundColor(.sandTextSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    LiveCameraView()
                        .cornerRadius(10)

                    map

                    positionReadout

                    if position?.known == true {
                        jogPad
                        recordControls
                    } else {
                        PrimaryButton(title: "Start Calibration", action: { run { try await start() } }, isDisabled: busy)
                    }

                    safetySettings

                    if !message.isEmpty {
                        Text(message)
                            .font(.sandCaption)
                            .foregroundColor(isError ? .sandError : .sandSuccess)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
            }
        }
        .navigationTitle("Sand Pit Boundary")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await store.refresh()
            safeZ = store.boundary.safeZ
            position = try? await CalibrationAPI.call("/position", method: "GET")
        }
    }

    // MARK: - Map

    /// Current outline, recorded points, and the live pen position.
    private var map: some View {
        let b = store.boundary
        let vp = b.viewport.including((position?.points ?? []) + [[0, 0]] + penPoint, padding: 12)
        return GeometryReader { geo in
            let rect = CGRect(origin: .zero, size: geo.size)
            ZStack {
                PitShape(boundary: b, viewport: vp).fill(Color.sandSurface)
                PitShape(boundary: b, viewport: vp).stroke(Color.sandGold.opacity(0.5), lineWidth: 2)

                // Arm base
                Circle()
                    .fill(Color.sandTextSecondary.opacity(0.4))
                    .frame(width: 14, height: 14)
                    .position(vp.point(x: 0, y: 0, in: rect))

                if let pts = position?.points, !pts.isEmpty {
                    Path { path in
                        path.move(to: vp.point(x: pts[0][0], y: pts[0][1], in: rect))
                        for p in pts.dropFirst() { path.addLine(to: vp.point(x: p[0], y: p[1], in: rect)) }
                    }
                    .stroke(Color.sandOrange, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))

                    ForEach(Array(pts.enumerated()), id: \.offset) { _, p in
                        Circle().fill(Color.sandOrange).frame(width: 7, height: 7)
                            .position(vp.point(x: p[0], y: p[1], in: rect))
                    }
                }

                if let p = penPoint.first {
                    Circle()
                        .stroke(position?.inside == true ? Color.sandSuccess : Color.sandError, lineWidth: 2)
                        .frame(width: 16, height: 16)
                        .position(vp.point(x: p[0], y: p[1], in: rect))
                }
            }
        }
        .aspectRatio(vp.aspectRatio, contentMode: .fit)
    }

    private var penPoint: [[Double]] {
        guard let pos = position, pos.known, let x = pos.x, let y = pos.y else { return [] }
        return [[x, y]]
    }

    private var positionReadout: some View {
        HStack {
            if let pos = position, pos.known, let x = pos.x, let y = pos.y, let z = pos.z {
                Text(String(format: "X %.1f   Y %.1f   Z %.1f", x, y, z))
                    .font(.sandBody.monospacedDigit())
                    .foregroundColor(.sandTextPrimary)
                Spacer()
                Text("\(pos.points.count) pts")
                    .font(.sandCaption)
                    .foregroundColor(.sandGold)
            } else {
                Text("Pen position unknown")
                    .font(.sandBody)
                    .foregroundColor(.sandTextSecondary)
                Spacer()
            }
        }
    }

    // MARK: - Jog pad

    private var jogPad: some View {
        VStack(spacing: 12) {
            Picker("Step", selection: $step) {
                Text("1 mm").tag(1.0)
                Text("5 mm").tag(5.0)
                Text("20 mm").tag(20.0)
            }
            .pickerStyle(.segmented)

            HStack(alignment: .center, spacing: 24) {
                VStack(spacing: 8) {
                    jogButton("arrow.up", dy: step)
                    HStack(spacing: 8) {
                        jogButton("arrow.left", dx: -step)
                        Color.clear.frame(width: 56, height: 56)
                        jogButton("arrow.right", dx: step)
                    }
                    jogButton("arrow.down", dy: -step)
                }
                VStack(spacing: 8) {
                    Text("PEN").font(.sandCaption).foregroundColor(.sandTextSecondary)
                    jogButton("chevron.up.2", dz: step)
                    jogButton("chevron.down.2", dz: -step)
                }
            }
            Text("↑ moves away from the arm base")
                .font(.sandCaption)
                .foregroundColor(.sandTextSecondary)
        }
    }

    private func jogButton(_ icon: String, dx: Double = 0, dy: Double = 0, dz: Double = 0) -> some View {
        Button {
            run { position = try await CalibrationAPI.call("/calibrate/jog", body: ["dx": dx, "dy": dy, "dz": dz]) }
        } label: {
            Image(systemName: icon)
                .font(.title2)
                .frame(width: 56, height: 56)
                .background(Color.sandSurface)
                .foregroundColor(.sandGold)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.sandGold.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.borderless)
        .disabled(busy)
    }

    // MARK: - Record / save

    private var recordControls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                secondaryButton("Record Point", icon: "mappin.and.ellipse") {
                    position = try await CalibrationAPI.call("/calibrate/record")
                }
                secondaryButton("Undo", icon: "arrow.uturn.backward") {
                    position = try await CalibrationAPI.call("/calibrate/undo")
                }
            }
            PrimaryButton(
                title: "Save Boundary (\(position?.points.count ?? 0) pts)",
                action: { run { try await save() } },
                isDisabled: busy || (position?.points.count ?? 0) < 5
            )
            secondaryButton("Save as Camera View", icon: "camera.viewfinder") {
                _ = try await CalibrationAPI.call("/view-position") as ViewPosition
                message = "Saved — the arm parks here after each drawing to take a photo"
            }
            secondaryButton("Done — Park at Camera View", icon: "camera") {
                position = try await CalibrationAPI.call("/calibrate/finish")
                position = nil
            }
        }
    }

    private func secondaryButton(_ title: String, icon: String, action: @escaping () async throws -> Void) -> some View {
        Button { run(action) } label: {
            Label(title, systemImage: icon)
                .font(.sandBody)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.sandSurface)
                .foregroundColor(.sandGold)
                .cornerRadius(8)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.sandGold.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.borderless)
        .disabled(busy)
    }

    // MARK: - Safety settings

    private var safetySettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SAFE HEIGHT")
                .font(.sandCaption)
                .foregroundColor(.sandTextSecondary)
            Text("Below this Z the pen must stay inside the pit. Set it a bit above the rim.")
                .font(.sandCaption)
                .foregroundColor(.sandTextSecondary)
            Stepper(value: $safeZ, in: 80...220, step: 5) {
                Text(String(format: "Z %.0f", safeZ))
                    .font(.sandBody)
                    .foregroundColor(.sandGold)
            }
            if safeZ != store.boundary.safeZ {
                secondaryButton("Save Safe Height", icon: "checkmark") {
                    let b: PitBoundary = try await CalibrationAPI.call("/boundary/settings", body: ["safe_z": safeZ])
                    store.update(b)
                    message = "Safe height set to Z \(Int(safeZ))"
                }
            }
            HStack {
                Text(store.boundary.calibrated ? "Calibrated outline" : "Estimated outline (not calibrated)")
                    .font(.sandCaption)
                    .foregroundColor(store.boundary.calibrated ? .sandSuccess : .sandOrange)
                Spacer()
                Button("Reset") {
                    run {
                        let b: PitBoundary = try await CalibrationAPI.call("/boundary/reset")
                        store.update(b)
                        message = "Boundary reset to the estimated outline"
                    }
                }
                .font(.sandCaption)
                .foregroundColor(.sandTextSecondary)
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Actions

    private func start() async throws {
        try await RobotService.shared.connectArm()
        position = try await CalibrationAPI.call("/calibrate/start")
        message = "Pen is at home, just above the sand"
    }

    private func save() async throws {
        let b: PitBoundary = try await CalibrationAPI.call("/calibrate/save")
        store.update(b)
        message = "Boundary saved — \(b.polygon.count) points after smoothing"
    }

    private func run(_ action: @escaping () async throws -> Void) {
        guard !busy else { return }
        busy = true
        Task {
            do {
                try await action()
                isError = false
            } catch {
                message = error.localizedDescription
                isError = true
            }
            busy = false
        }
    }
}
