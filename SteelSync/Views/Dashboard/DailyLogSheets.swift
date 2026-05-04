import SwiftUI
import CloudKit
import UniformTypeIdentifiers

// MARK: - Add Daily Log

struct AddDailyLogSheet: View {
    let projectID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var weather = ""
    @State private var workCompleted = ""
    @State private var issuesEncountered = ""
    @State private var crewIDs: Set<String> = []
    @State private var totalCrewHoursText = ""
    @State private var safetyIncidentsNote = ""
    @State private var notes = ""

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "New Daily Log",
                saveTitle: "Save",
                saveDisabled: !canSave,
                onCancel: { dismiss() },
                onSave: save
            )
            ScrollView {
                DailyLogFormBody(
                    employees: dataStore.employees,
                    date: $date, weather: $weather,
                    workCompleted: $workCompleted, issuesEncountered: $issuesEncountered,
                    crewIDs: $crewIDs, totalCrewHoursText: $totalCrewHoursText,
                    safetyIncidentsNote: $safetyIncidentsNote, notes: $notes,
                    photos: nil,                          // photos added after first save
                    onPhotoUpload: nil,
                    onPhotoRemove: nil
                )
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
        }
        #if os(macOS)
        .frame(width: 640, height: 700)
        #endif
    }

    private var canSave: Bool {
        // Don't allow empty logs.
        !workCompleted.trimmingCharacters(in: .whitespaces).isEmpty
            || !issuesEncountered.trimmingCharacters(in: .whitespaces).isEmpty
            || !crewIDs.isEmpty
    }

    private func save() {
        let hours = Decimal(string: totalCrewHoursText.replacingOccurrences(of: ",", with: "")) ?? 0
        let log = DailyLog(
            date: date,
            weather: weather,
            workCompleted: workCompleted,
            issuesEncountered: issuesEncountered,
            crewOnSiteIDs: Array(crewIDs),
            totalCrewHours: hours,
            safetyIncidentsNote: safetyIncidentsNote,
            notes: notes
        )
        dataStore.addDailyLog(log, to: projectID)
        dismiss()
    }
}

// MARK: - Edit Daily Log

struct EditDailyLogSheet: View {
    let log: DailyLog
    let projectID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var date: Date
    @State private var weather: String
    @State private var workCompleted: String
    @State private var issuesEncountered: String
    @State private var crewIDs: Set<String>
    @State private var totalCrewHoursText: String
    @State private var safetyIncidentsNote: String
    @State private var notes: String
    @State private var attachmentToDelete: Attachment?
    @State private var showFileImporter = false
    @State private var uploadError: String?

    init(log: DailyLog, projectID: CKRecord.ID) {
        self.log = log
        self.projectID = projectID
        _date = State(initialValue: log.date)
        _weather = State(initialValue: log.weather)
        _workCompleted = State(initialValue: log.workCompleted)
        _issuesEncountered = State(initialValue: log.issuesEncountered)
        _crewIDs = State(initialValue: Set(log.crewOnSiteIDs))
        _totalCrewHoursText = State(initialValue: log.totalCrewHours > 0
            ? NSDecimalNumber(decimal: log.totalCrewHours).stringValue
            : "")
        _safetyIncidentsNote = State(initialValue: log.safetyIncidentsNote)
        _notes = State(initialValue: log.notes)
    }

    /// Always read photos straight from the live store so attachments
    /// added/removed during the sheet's lifetime are reflected.
    private var currentPhotos: [Attachment] {
        dataStore.dailyLogs(for: projectID).first(where: { $0.id == log.id })?.photos ?? log.photos
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Edit Daily Log",
                saveTitle: "Save",
                onCancel: { dismiss() },
                onSave: save
            )
            ScrollView {
                DailyLogFormBody(
                    employees: dataStore.employees,
                    date: $date, weather: $weather,
                    workCompleted: $workCompleted, issuesEncountered: $issuesEncountered,
                    crewIDs: $crewIDs, totalCrewHoursText: $totalCrewHoursText,
                    safetyIncidentsNote: $safetyIncidentsNote, notes: $notes,
                    photos: currentPhotos,
                    onPhotoUpload: { showFileImporter = true },
                    onPhotoRemove: { attachmentToDelete = $0 }
                )
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
        }
        #if os(macOS)
        .frame(width: 640, height: 700)
        #endif
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: [.image, .pdf],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls): importPhotos(urls)
            case .failure(let error): uploadError = error.localizedDescription
            }
        }
        .alert("Upload error", isPresented: Binding(
            get: { uploadError != nil },
            set: { if !$0 { uploadError = nil } }
        ), presenting: uploadError) { _ in
            Button("OK") { uploadError = nil }
        } message: { msg in Text(msg) }
        .confirmationDialog(
            "Remove photo?",
            isPresented: Binding(
                get: { attachmentToDelete != nil },
                set: { if !$0 { attachmentToDelete = nil } }
            ),
            presenting: attachmentToDelete
        ) { att in
            Button("Remove", role: .destructive) {
                dataStore.removeDailyLogAttachment(att, from: log.id, in: projectID)
                attachmentToDelete = nil
            }
            Button("Cancel", role: .cancel) { attachmentToDelete = nil }
        } message: { att in
            Text("\"\(att.filename)\" will be deleted from local storage.")
        }
    }

    private func importPhotos(_ urls: [URL]) {
        let logIDString = log.id.uuidString
        for url in urls {
            switch FileStorageService.importFile(from: url, dailyLogID: logIDString) {
            case .success(let attachment):
                dataStore.addDailyLogAttachment(attachment, to: log.id, in: projectID)
            case .failure(let error):
                uploadError = error.localizedDescription
            }
        }
    }

    private func save() {
        var updated = log
        updated.date = date
        updated.weather = weather
        updated.workCompleted = workCompleted
        updated.issuesEncountered = issuesEncountered
        updated.crewOnSiteIDs = Array(crewIDs)
        updated.totalCrewHours = Decimal(string: totalCrewHoursText.replacingOccurrences(of: ",", with: "")) ?? 0
        updated.safetyIncidentsNote = safetyIncidentsNote
        updated.notes = notes
        // photos are managed via add/remove attachment APIs and read from store
        updated.photos = currentPhotos
        dataStore.updateDailyLog(updated, in: projectID)
        dismiss()
    }
}

// MARK: - Shared form body

struct DailyLogFormBody: View {
    let employees: [Employee]
    @Binding var date: Date
    @Binding var weather: String
    @Binding var workCompleted: String
    @Binding var issuesEncountered: String
    @Binding var crewIDs: Set<String>
    @Binding var totalCrewHoursText: String
    @Binding var safetyIncidentsNote: String
    @Binding var notes: String
    /// Optional photo attachments. When `nil`, the photos section is hidden
    /// (used by Add — photos are added after the log exists).
    let photos: [Attachment]?
    let onPhotoUpload: (() -> Void)?
    let onPhotoRemove: ((Attachment) -> Void)?

    private var activeEmployees: [Employee] {
        employees.filter { $0.status == .active }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
            basicsSection
            workSection
            crewSection
            safetySection
            if photos != nil {
                photosSection
            }
            notesSection
        }
    }

    @ViewBuilder private var basicsSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Day")
            HStack(spacing: AppTheme.Spacing.md) {
                LabeledField(label: "Date") {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                        .appControlSurface()
                }
                LabeledField(label: "Weather", helpText: "Free text — e.g. \"Sunny 78°F\" or \"Rain 9–11am\"") {
                    TextField("Sunny 78°F", text: $weather)
                        .textFieldStyle(.appField)
                }
            }
        }
    }

    @ViewBuilder private var workSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Work Completed")
            NotesField(text: $workCompleted, minHeight: 70)

            SectionTitle(text: "Issues / Blockers")
            NotesField(text: $issuesEncountered, minHeight: 60)
        }
    }

    @ViewBuilder private var crewSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Crew on Site")

            LabeledField(label: "Total Crew Hours") {
                TextField("0", text: $totalCrewHoursText)
                    .textFieldStyle(.appField)
                    #if !os(macOS)
                    .keyboardType(.decimalPad)
                    #endif
            }

            if activeEmployees.isEmpty {
                Text("No active employees. Add some in Crew & Timesheets to assign them here.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("PEOPLE ON SITE")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.secondaryText)
                        .tracking(0.5)
                    ForEach(activeEmployees) { employee in
                        Toggle(isOn: Binding(
                            get: { crewIDs.contains(employee.id.uuidString) },
                            set: { isOn in
                                if isOn { crewIDs.insert(employee.id.uuidString) }
                                else { crewIDs.remove(employee.id.uuidString) }
                            }
                        )) {
                            HStack {
                                Text(employee.fullName)
                                Spacer()
                                Text(employee.employeeType.displayName)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                }
                .padding(AppTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.secondaryBackground)
                )
            }
        }
    }

    @ViewBuilder private var safetySection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Safety")
            LabeledField(
                label: "Incidents",
                helpText: "Leave blank if nothing happened. If something did, describe it concisely — date, who, what, what was done."
            ) {
                NotesField(text: $safetyIncidentsNote, minHeight: 60)
            }
        }
    }

    @ViewBuilder private var photosSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            HStack {
                SectionTitle(text: "Photos (\(photos?.count ?? 0))")
                Spacer()
                if let onUpload = onPhotoUpload {
                    Button { onUpload() } label: {
                        Label("Upload", systemImage: "photo.on.rectangle.angled")
                    }
                    .buttonStyle(.appSecondary)
                    .controlSize(.small)
                }
            }

            if let photos = photos, photos.isEmpty {
                Text("No photos attached. Tap Upload, or drag images into this card.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(AppTheme.Spacing.md)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.secondaryBackground)
                    )
            } else if let photos = photos {
                VStack(spacing: 6) {
                    ForEach(photos) { photo in
                        photoRow(photo)
                    }
                }
                .padding(AppTheme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(AppTheme.secondaryBackground)
                )
            }
        }
    }

    @ViewBuilder private func photoRow(_ photo: Attachment) -> some View {
        HStack {
            Image(systemName: FileStorageService.iconName(for: photo.filename))
                .foregroundColor(AppTheme.primaryOrange)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 1) {
                Text(photo.filename)
                    .font(.callout)
                    .lineLimit(1)
                Text(photo.fileSizeFormatted)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button {
                FileStorageService.openFile(photo)
            } label: {
                Image(systemName: "arrow.up.forward.app")
            }
            .buttonStyle(.borderless)
            .help("Open")
            if let onRemove = onPhotoRemove {
                Button {
                    onRemove(photo)
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
                .help("Remove")
            }
        }
    }

    @ViewBuilder private var notesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Internal Notes")
            NotesField(text: $notes, minHeight: 60)
        }
    }
}
