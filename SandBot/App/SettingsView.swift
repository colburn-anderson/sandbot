//
//  SettingsView.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//


import SwiftUI

struct SettingsView: View {
    @AppStorage("robotHost") private var robotHost: String = "sandbot.local"

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sandBgPrimary.ignoresSafeArea()
                Form {
                    Section("Robot Connection") {
                        HStack {
                            Text("Host")
                                .font(.sandBody)
                                .foregroundColor(.sandTextSecondary)
                            Spacer()
                            TextField("sandbot.local", text: $robotHost)
                                .font(.sandBody)
                                .foregroundColor(.sandGold)
                                .multilineTextAlignment(.trailing)
                        }
                    }
                    Section("App") {
                        HStack {
                            Text("Mock Mode")
                                .font(.sandBody)
                                .foregroundColor(.sandTextSecondary)
                            Spacer()
                            Text("ON")
                                .font(.sandBody)
                                .foregroundColor(.sandGold)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}