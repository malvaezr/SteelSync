import Foundation
import CloudKit

/// A reusable, modular bundle of crew members. Applying a preset to a week
/// drops one TimesheetEntry per member into that week — pre-populated with
/// the member's preferred rate, per-diem, and default daily-hours pattern.
/// Presets are people-based by default; `duplicatedAsRoleTemplate()` strips
/// employee references so the same preset can be reused as a role template
/// (Foreman + 4 Ironworkers) and re-assigned to different people later.
struct CrewPreset: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var members: [CrewPresetMember]
    var createdDate: Date
    var recordID: CKRecord.ID?

    enum CodingKeys: String, CodingKey {
        case id, name, members, createdDate
    }

    init(
        id: UUID = UUID(),
        name: String,
        members: [CrewPresetMember] = [],
        createdDate: Date = Date(),
        recordID: CKRecord.ID? = nil
    ) {
        self.id = id
        self.name = name
        self.members = members
        self.createdDate = createdDate
        self.recordID = recordID
    }

    /// True when no member has a concrete employee link — i.e. this preset is
    /// a role template that needs people assigned at apply time.
    var isRoleTemplate: Bool {
        !members.isEmpty && members.allSatisfy { $0.employeeRef == nil }
    }

    /// Returns a copy with a fresh UUID, "(Roles)" appended to the name, and
    /// every member's employee link cleared. The role labels (employeeName /
    /// employeeType) survive so the user can see "Foreman", "Ironworker", etc.
    /// when re-assigning later.
    func duplicatedAsRoleTemplate() -> CrewPreset {
        let roleMembers = members.map { m in
            CrewPresetMember(
                employeeRef: nil,
                employeeName: m.employeeType.isEmpty ? m.employeeName : m.employeeType,
                employeeType: m.employeeType,
                hourlyRateOverride: m.hourlyRateOverride,
                perDiem: m.perDiem,
                dailyHours: m.dailyHours
            )
        }
        return CrewPreset(name: "\(name) (Roles)", members: roleMembers)
    }
}

struct CrewPresetMember: Identifiable, Codable, Hashable {
    let id: UUID
    /// Employee.id.uuidString — nil for role-only templates.
    var employeeRef: String?
    /// Snapshotted at preset-creation time so role templates display
    /// meaningful labels even without an employee link.
    var employeeName: String
    var employeeType: String
    /// nil = use the linked employee's `defaultHourlyRate` at apply time.
    var hourlyRateOverride: Decimal?
    var perDiem: Decimal
    /// Mon..Sun. Always 7 entries; init normalizes any other shape.
    var dailyHours: [Decimal]

    init(
        id: UUID = UUID(),
        employeeRef: String?,
        employeeName: String,
        employeeType: String = "",
        hourlyRateOverride: Decimal? = nil,
        perDiem: Decimal = 0,
        dailyHours: [Decimal] = [10, 10, 10, 10, 10, 0, 0]
    ) {
        self.id = id
        self.employeeRef = employeeRef
        self.employeeName = employeeName
        self.employeeType = employeeType
        self.hourlyRateOverride = hourlyRateOverride
        self.perDiem = perDiem
        self.dailyHours = dailyHours.count == 7 ? dailyHours : [10, 10, 10, 10, 10, 0, 0]
    }

    var totalDefaultHours: Decimal {
        dailyHours.reduce(0, +)
    }
}
