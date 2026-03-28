import Foundation
import CloudKit

struct WeeklyAssignment: Identifiable, Hashable {
    var id: UUID
    var assignmentToken: String
    var projectRef: CKRecord.Reference
    var foremanRef: CKRecord.Reference
    var weekStartDate: Date
    var weekEndDate: Date
    var status: AssignmentStatus
    var crewMemberRefs: [CKRecord.Reference]
    var crewRates: [String: Decimal]
    var notes: String
    var createdDate: Date
    var closedDate: Date?
    var tokenExpiryDate: Date
    var recordID: CKRecord.ID?

    init(
        id: UUID = UUID(), assignmentToken: String = "", projectRef: CKRecord.Reference,
        foremanRef: CKRecord.Reference, weekStartDate: Date, weekEndDate: Date,
        status: AssignmentStatus = .pending, crewMemberRefs: [CKRecord.Reference] = [],
        crewRates: [String: Decimal] = [:], notes: String = "", createdDate: Date = Date(),
        closedDate: Date? = nil, tokenExpiryDate: Date? = nil, recordID: CKRecord.ID? = nil
    ) {
        self.id = id
        self.assignmentToken = assignmentToken.isEmpty ? Self.generateToken() : assignmentToken
        self.projectRef = projectRef; self.foremanRef = foremanRef
        self.weekStartDate = weekStartDate; self.weekEndDate = weekEndDate
        self.status = status; self.crewMemberRefs = crewMemberRefs
        self.crewRates = crewRates; self.notes = notes; self.createdDate = createdDate
        self.closedDate = closedDate
        self.tokenExpiryDate = tokenExpiryDate ?? Self.calculateExpiryDate(weekEnd: weekEndDate)
        self.recordID = recordID
    }

    static func generateToken() -> String {
        let characters = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
        return String((0..<6).map { _ in
            characters.randomElement()!
        })
    }

    static func calculateExpiryDate(weekEnd: Date) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: weekEnd)
        components.hour = 23; components.minute = 59; components.second = 59
        return Calendar.current.date(from: components) ?? weekEnd
    }

    var isExpired: Bool { Date() > tokenExpiryDate }
    var isActive: Bool { status == .active || status == .pending }
    var weekNumber: Int { Calendar.current.component(.weekOfYear, from: weekStartDate) }
    var year: Int { Calendar.current.component(.year, from: weekStartDate) }

    var weekDateRange: String {
        let formatter = DateFormatter()
        if Calendar.current.isDate(weekStartDate, inSameDayAs: weekEndDate) {
            formatter.dateFormat = "MMM d, yyyy"
            return formatter.string(from: weekStartDate)
        }
        formatter.dateFormat = "MMM d"
        let start = formatter.string(from: weekStartDate)
        formatter.dateFormat = "MMM d, yyyy"
        return "\(start) - \(formatter.string(from: weekEndDate))"
    }
}

enum AssignmentStatus: String, CaseIterable {
    case pending = "Pending"
    case active = "Active"
    case completed = "Completed"
    case approved = "Approved"
    case cancelled = "Cancelled"
    var displayName: String { rawValue }
}
