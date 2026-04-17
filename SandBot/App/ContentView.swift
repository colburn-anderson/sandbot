//
//  ContentView.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var statusMonitor = RobotStatusMonitor()

    var body: some View {
        TabView {
            ComposeView()
                .tabItem {
                    Label("Compose", systemImage: "pencil.and.outline")
                }
            HistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }
            LiveFeedView()
                .tabItem {
                    Label("Live Feed", systemImage: "video")
                }
            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
        .tint(Color.sandGold)
        .preferredColorScheme(.dark)
        .environmentObject(statusMonitor)
    }
}
