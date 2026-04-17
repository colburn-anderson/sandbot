//
//  LiveFeedView.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//


import SwiftUI

struct LiveFeedView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.sandBgPrimary.ignoresSafeArea()
                Text("Live Feed")
                    .font(.sandDisplay)
                    .foregroundColor(.sandTextPrimary)
            }
            .navigationTitle("Live Feed")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}