//
//  HistoryCardView.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/19/26.
//


import SwiftUI

struct HistoryCardView: View {
    let entry: DrawingHistoryEntry

    var body: some View {
        HStack(spacing: 12) {

            // Thumbnail
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.sandSurface)
                    .frame(width: 56, height: 56)

                if let photoData = entry.completionPhotoData,
                   let uiImage = UIImage(data: photoData) {
                    Image(uiImage: uiImage)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 56, height: 56)
                        .clipped()
                        .cornerRadius(8)
                } else {
                    Image(systemName: sourceIcon)
                        .foregroundColor(.sandTextSecondary)
                        .font(.system(size: 20))
                }
            }

            // Info
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.label)
                    .font(.sandBody)
                    .foregroundColor(.sandTextPrimary)
                    .lineLimit(1)

                Text(entry.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.sandCaption)
                    .foregroundColor(.sandTextSecondary)

                // Source badge
                Text(entry.sourceType.uppercased().replacingOccurrences(of: "_", with: " "))
                    .font(.sandCaption)
                    .foregroundColor(.sandGold)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.sandGold.opacity(0.15))
                    .cornerRadius(4)
            }

            Spacer()

            // Status
            VStack(alignment: .trailing, spacing: 4) {
                statusView
                Image(systemName: "chevron.right")
                    .font(.sandCaption)
                    .foregroundColor(.sandTextSecondary)
            }
        }
        .padding(12)
        .background(Color.sandSurface)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.sandBorder, lineWidth: 1)
        )
        .cornerRadius(12)
    }

    @ViewBuilder
    private var statusView: some View {
        switch entry.status {
        case .sent:
            StatusDot(color: .sandGold, label: "Sent")
        case .drawing:
            StatusDot(color: .sandOrange, label: "Drawing")
        case .completed:
            StatusDot(color: .sandSuccess, label: "Done")
        case .failed:
            StatusDot(color: .sandError, label: "Failed")
        }
    }

    private var sourceIcon: String {
        switch entry.sourceType {
        case "text":       return "textformat"
        case "image":      return "photo"
        case "ai_pattern": return "sparkles"
        default:           return "scribble"
        }
    }
}

struct StatusDot: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(.sandCaption)
                .foregroundColor(color)
        }
    }
}