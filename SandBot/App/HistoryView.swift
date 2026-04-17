//
//  HistoryView.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//


import SwiftUI

struct HistoryView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Color.sandBgPrimary.ignoresSafeArea()
                Text("History")
                    .font(.sandDisplay)
                    .foregroundColor(.sandTextPrimary)
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}