//
//  SandBotApp.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//

import SwiftUI
import SwiftData

@main
struct SandBotApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .modelContainer(for: DrawingHistoryEntry.self)
                .preferredColorScheme(.dark)
        }
    }
}
