//
//  DrawingHistory.swift
//  SandBot
//
//  Created by Anderson Colburn on 4/16/26.
//

import Foundation
import SwiftData

enum JobStatus: String, Codable {
    case sent, drawing, completed, failed
}

@Model
final class DrawingHistoryEntry {
    var id: UUID
    var timestamp: Date
    var sourceType: String
    var label: String
    var strokesData: Data
    var jobId: String?
    var statusRaw: String
    var completionPhotoData: Data?

    init(sourceType: String, label: String, strokesData: Data, jobId: String? = nil) {
        self.id = UUID()
        self.timestamp = Date()
        self.sourceType = sourceType
        self.label = label
        self.strokesData = strokesData
        self.jobId = jobId
        self.statusRaw = JobStatus.sent.rawValue
    }

    var status: JobStatus {
        get { JobStatus(rawValue: statusRaw) ?? .sent }
        set { statusRaw = newValue.rawValue }
    }
}
