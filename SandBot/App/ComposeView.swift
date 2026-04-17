//
//  ComposeView.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//


import SwiftUI

struct ComposeView: View {
    @EnvironmentObject var statusMonitor: RobotStatusMonitor

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sandBgPrimary.ignoresSafeArea()
                Text("Compose")
                    .font(.sandDisplay)
                    .foregroundColor(.sandTextPrimary)
            }
            .navigationTitle("SandBot")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    StatusPill(status: statusMonitor.connectionStatus)
                }
            }
        }
    }
}