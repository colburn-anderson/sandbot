//
//  RobotStatusMonitor.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//

import Foundation
import Combine

@MainActor
final class RobotStatusMonitor: ObservableObject {
    @Published var connectionStatus: RobotConnectionStatus = .connecting
    @Published var robotState: RobotState = .idle

    private var pollTask: Task<Void, Never>?

    init() {
        startPolling()
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task {
            while !Task.isCancelled {
                do {
                    let status = try await RobotService.shared.fetchStatus()
                    connectionStatus = .online
                    robotState = status.state
                } catch {
                    connectionStatus = .offline
                }
                try? await Task.sleep(nanoseconds: 5_000_000_000)
            }
        }
    }
}
