//
//  HistoryDetailView.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/19/26.
//


import SwiftUI

struct HistoryDetailView: View {
    let entry: DrawingHistoryEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            Color.sandBgPrimary.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {

                    // Completion photo or stroke preview
                    if let photoData = entry.completionPhotoData,
                       let uiImage = UIImage(data: photoData) {
                        Image(uiImage: uiImage)
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.sandGold.opacity(0.3), lineWidth: 1)
                            )
                    } else {
                        // Show stroke preview
                        if let strokes = try? JSONDecoder().decode([Stroke].self, from: entry.strokesData) {
                            SandCanvas(strokes: strokes)
                        }
                    }

                    // Info card
                    VStack(alignment: .leading, spacing: 12) {
                        infoRow(label: "Label", value: entry.label)
                        infoRow(label: "Type", value: entry.sourceType.replacingOccurrences(of: "_", with: " ").capitalized)
                        infoRow(label: "Sent", value: entry.timestamp.formatted(date: .long, time: .shortened))
                        infoRow(label: "Status", value: entry.status.rawValue.capitalized)
                        if let jobId = entry.jobId {
                            infoRow(label: "Job ID", value: jobId)
                        }
                    }
                    .padding()
                    .background(Color.sandSurface)
                    .cornerRadius(12)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.sandBorder, lineWidth: 1)
                    )

                    // Resend button
                    PrimaryButton(title: "Resend", action: {}, style: .secondary)
                }
                .padding()
            }
        }
        .navigationTitle(entry.label)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label.uppercased())
                .font(.sandCaption)
                .foregroundColor(.sandTextSecondary)
            Spacer()
            Text(value)
                .font(.sandBody)
                .foregroundColor(.sandTextPrimary)
        }
    }
}