//
//  HistoryView.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//


import SwiftUI
import SwiftData

struct HistoryView: View {
    @Query(sort: \DrawingHistoryEntry.timestamp, order: .reverse) var entries: [DrawingHistoryEntry]

    var body: some View {
        NavigationStack {
            ZStack {
                Color.sandBgPrimary.ignoresSafeArea()
                if entries.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "clock")
                            .font(.system(size: 40))
                            .foregroundColor(.sandTextSecondary)
                        Text("No drawings yet")
                            .font(.sandHeader)
                            .foregroundColor(.sandTextSecondary)
                        Text("Send something to the robot\nand it'll appear here.")
                            .font(.sandBody)
                            .foregroundColor(.sandTextSecondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(entries) { entry in
                                NavigationLink(destination: HistoryDetailView(entry: entry)) {
                                    HistoryCardView(entry: entry)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
