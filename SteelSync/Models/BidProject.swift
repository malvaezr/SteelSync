import Foundation
import CloudKit

struct BidProject: Identifiable, Hashable {
    let recordID: CKRecord.ID
    var id: CKRecord.ID { recordID }

    var projectName: String
    var clientName: String
    var clientRef: CKRecord.Reference?
    var address: String
    var bidAmount: Decimal
    var bidDueDate: Date
    var createdDate: Date
    var isSubmitted: Bool
    var submittedDate: Date?
    var awardedProjectID: String?
    var isReadyToSubmit: Bool
    var isLost: Bool

    var squareFeet: Int
    var numberOfBeams: Int
    var numberOfColumns: Int
    var numberOfJoists: Int
    var numberOfWallPanels: Int
    var estimatedTons: Double

    var touchpoints: [Touchpoint]
    var nextFollowUp: Date?
    var reminderDate: Date?
    var notes: String
    var attachments: [Attachment]

    init(
        recordID: CKRecord.ID = CKRecord.ID(recordName: UUID().uuidString),
        projectName: String, clientName: String, clientRef: CKRecord.Reference? = nil, address: String = "",
        bidAmount: Decimal = 0, bidDueDate: Date = Date(), createdDate: Date = Date(),
        isSubmitted: Bool = false, submittedDate: Date? = nil,
        awardedProjectID: String? = nil, isReadyToSubmit: Bool = false, isLost: Bool = false,
        squareFeet: Int = 0, numberOfBeams: Int = 0, numberOfColumns: Int = 0,
        numberOfJoists: Int = 0, numberOfWallPanels: Int = 0, estimatedTons: Double = 0,
        touchpoints: [Touchpoint] = [], nextFollowUp: Date? = nil, reminderDate: Date? = nil,
        notes: String = "", attachments: [Attachment] = []
    ) {
        self.recordID = recordID; self.projectName = projectName; self.clientName = clientName
        self.clientRef = clientRef; self.address = address; self.bidAmount = bidAmount; self.bidDueDate = bidDueDate
        self.createdDate = createdDate; self.isSubmitted = isSubmitted; self.submittedDate = submittedDate
        self.awardedProjectID = awardedProjectID; self.isReadyToSubmit = isReadyToSubmit; self.isLost = isLost
        self.squareFeet = squareFeet; self.numberOfBeams = numberOfBeams
        self.numberOfColumns = numberOfColumns; self.numberOfJoists = numberOfJoists
        self.numberOfWallPanels = numberOfWallPanels; self.estimatedTons = estimatedTons
        self.touchpoints = touchpoints; self.nextFollowUp = nextFollowUp
        self.reminderDate = reminderDate; self.notes = notes; self.attachments = attachments
    }

    var isAwarded: Bool { awardedProjectID != nil }

    var status: BidStatus {
        if isLost { return .lost }
        else if isAwarded { return .awarded }
        else if isSubmitted { return .submitted }
        else if isReadyToSubmit { return .readyToSubmit }
        else { return .pending }
    }

    enum BidStatus: String {
        case pending = "Pending"
        case readyToSubmit = "Ready to Submit"
        case submitted = "Submitted"
        case awarded = "Awarded"
        case lost = "Lost"
    }
}

struct Touchpoint: Identifiable, Codable, Hashable {
    let id: UUID
    var type: TouchpointType
    var date: Date
    var notes: String

    enum TouchpointType: String, Codable, CaseIterable {
        case call = "Phone Call"
        case email = "Email"
        case meeting = "Meeting"
        case siteVisit = "Site Visit"
        case other = "Other"

        var icon: String {
            switch self {
            case .call: return "phone.fill"
            case .email: return "envelope.fill"
            case .meeting: return "person.2.fill"
            case .siteVisit: return "location.fill"
            case .other: return "ellipsis.circle.fill"
            }
        }
    }

    init(id: UUID = UUID(), type: TouchpointType, date: Date = Date(), notes: String = "") {
        self.id = id; self.type = type; self.date = date; self.notes = notes
    }
}

struct Attachment: Identifiable, Codable, Hashable {
    let id: UUID
    var filename: String
    var fileSize: Int64
    var fileURL: URL?
    var uploadedDate: Date

    init(id: UUID = UUID(), filename: String, fileSize: Int64 = 0, fileURL: URL? = nil, uploadedDate: Date = Date()) {
        self.id = id; self.filename = filename; self.fileSize = fileSize
        self.fileURL = fileURL; self.uploadedDate = uploadedDate
    }

    var fileSizeFormatted: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: fileSize)
    }
}

extension BidProject {
    static let preview = BidProject(
        projectName: "Downtown Office Tower", clientName: "Acme Developers",
        address: "123 Main St, City, ST", bidAmount: 250000,
        bidDueDate: Date().addingTimeInterval(86400 * 14),
        squareFeet: 48000, numberOfBeams: 120, numberOfColumns: 45,
        touchpoints: [
            Touchpoint(type: .call, date: Date().addingTimeInterval(-86400 * 5), notes: "Initial discussion"),
            Touchpoint(type: .siteVisit, date: Date().addingTimeInterval(-86400 * 2), notes: "Site walkthrough")
        ]
    )
}
