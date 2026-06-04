import SwiftUI
import CloudKit

/// Carries which rental + which kind of request to log, so one sheet handles
/// delivery requests, pickup ("cut") requests, confirmations, and notes.
struct RentalRequestContext: Identifiable {
    let id = UUID()
    let rental: EquipmentRental
    let kind: RentalRequestKind
}

// MARK: - Status badges

/// Colored pill for a rental's lifecycle stage.
struct RentalLifecycleBadge: View {
    let lifecycle: RentalLifecycle
    private var color: Color {
        switch lifecycle {
        case .requested: return .blue
        case .onRent: return .green
        case .pickupRequested: return .orange
        case .closed: return AppTheme.secondaryText
        }
    }
    var body: some View {
        Text(lifecycle.rawValue.uppercased())
            .font(.system(size: 9, weight: .bold))
            .tracking(0.4)
            .foregroundColor(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(Capsule().fill(color.opacity(0.15)))
    }
}

/// Colored pill for the supplier-invoice check status.
struct InvoiceStatusBadge: View {
    let status: InvoiceCheckStatus
    private var color: Color {
        switch status {
        case .notReceived: return AppTheme.secondaryText
        case .underReview: return .blue
        case .matches, .approved: return .green
        case .disputed: return .red
        }
    }
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: status.icon).font(.system(size: 9))
            Text(status.rawValue).font(.system(size: 9, weight: .semibold))
        }
        .foregroundColor(color)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(Capsule().fill(color.opacity(0.15)))
    }
}

// MARK: - Request log timeline

/// Compact, read-only timeline of a rental's documented requests — the
/// dispute record. Each row shows what was requested, the date it was
/// requested for, and the immutable timestamp it was logged.
struct RentalRequestLogView: View {
    let events: [RentalRequestEvent]

    private var sorted: [RentalRequestEvent] {
        events.sorted { $0.loggedAt > $1.loggedAt }   // newest first
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(sorted) { e in
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: e.kind.icon)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.primaryOrange)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(e.kind.rawValue).font(.caption).fontWeight(.semibold)
                            if let d = e.requestedDate {
                                Text("for \(d.shortDate)").font(.caption).foregroundColor(AppTheme.secondaryText)
                            }
                        }
                        Text(detailLine(e))
                            .font(.caption2)
                            .foregroundColor(AppTheme.secondaryText)
                        if !e.notes.isEmpty {
                            Text(e.notes).font(.caption2).foregroundColor(AppTheme.tertiaryText)
                        }
                    }
                    Spacer()
                }
            }
        }
    }

    private func detailLine(_ e: RentalRequestEvent) -> String {
        var parts = ["logged \(timestamp(e.loggedAt))"]
        var via = "via \(e.method.rawValue)"
        if !e.contactName.isEmpty { via += " to \(e.contactName)" }
        parts.append(via)
        if !e.loggedBy.isEmpty { parts.append("by \(e.loggedBy)") }
        return parts.joined(separator: " · ")
    }

    private func timestamp(_ d: Date) -> String {
        let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"
        return f.string(from: d)
    }
}

// MARK: - Request sheet (delivery / pickup-"cut")

/// Logs a timestamped request to the rental's record. Used for the off-rent
/// ("cut") pickup request and for logging a delivery request, so there's a
/// documented date on our end if the supplier's invoice disagrees.
struct RentalRequestSheet: View {
    let rental: EquipmentRental
    let projectID: CKRecord.ID
    let kind: RentalRequestKind
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    @State private var requestedDate = Date()
    @State private var method: RentalContactMethod = .text
    @State private var contactName = ""
    @State private var loggedBy = ""
    @State private var notes = ""

    private var isPickup: Bool { kind == .pickupRequested }
    private var title: String {
        switch kind {
        case .deliveryRequested: return "Request Delivery"
        case .deliveryConfirmed: return "Confirm Drop-Off"
        case .pickupRequested: return "Request Pickup (Cut Off)"
        case .pickupConfirmed: return "Confirm Pickup"
        case .note: return "Add Note"
        }
    }
    private var dateLabel: String {
        switch kind {
        case .deliveryRequested: return "Requested Delivery Date"
        case .deliveryConfirmed: return "Drop-Off Date"
        case .pickupRequested: return "Requested Pickup Date"
        case .pickupConfirmed: return "Pickup Date"
        case .note: return "Date"
        }
    }
    private var saveTitle: String {
        switch kind {
        case .deliveryConfirmed, .pickupConfirmed: return "Confirm"
        case .note: return "Add Note"
        default: return "Log Request"
        }
    }

    var body: some View {
        EntryFormScaffold(
            title: title,
            icon: kind.icon,
            saveTitle: saveTitle,
            onCancel: closeForm,
            onSave: save
        ) {
            EntrySection("Equipment", systemImage: AppIcons.equipment) {
                InfoRow(label: "Unit", value: rental.equipmentName)
                InfoRow(label: "On rent since", value: rental.startDate.shortDate)
                if isPickup {
                    InfoRow(label: "Days on rent", value: "\(rental.daysSinceStart)")
                }
            }

            EntrySection("Request Details", systemImage: kind.icon) {
                LabeledField(label: dateLabel) {
                    DatePicker("", selection: $requestedDate, displayedComponents: .date)
                        .labelsHidden().appControlSurface()
                }
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    LabeledField(label: "How Requested") {
                        Picker("", selection: $method) {
                            ForEach(RentalContactMethod.allCases) { m in
                                Label(m.rawValue, systemImage: m.icon).tag(m)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).appControlSurface()
                    }
                    LabeledField(label: "Supplier Contact") {
                        TextField("Agent name", text: $contactName).textFieldStyle(.appField)
                    }
                }
                LabeledField(label: "Requested By (you)") {
                    TextField("Your name", text: $loggedBy).textFieldStyle(.appField)
                }
                LabeledField(label: "Notes") {
                    NotesField(text: $notes, minHeight: 60)
                }
                Text("Logged with a timestamp of now (\(nowStamp)). This becomes part of the permanent record for invoice disputes.")
                    .font(.caption2)
                    .foregroundColor(AppTheme.tertiaryText)
            }

            if !rental.events.isEmpty {
                EntrySection("Prior Requests", systemImage: AppIcons.history) {
                    RentalRequestLogView(events: rental.events)
                }
            }
        }
        .onAppear {
            // Things happening "now" (pickup ask, drop-off / pickup confirm)
            // default to today; a planned delivery request defaults to the
            // rental's planned start.
            switch kind {
            case .pickupRequested, .deliveryConfirmed, .pickupConfirmed:
                requestedDate = Date()
            default:
                requestedDate = rental.startDate
            }
            if let last = rental.events.last(where: { !$0.contactName.isEmpty }) {
                contactName = last.contactName
            }
        }
    }

    private var nowStamp: String {
        let f = DateFormatter(); f.dateFormat = "MMM d, h:mm a"
        return f.string(from: Date())
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func save() {
        let event = RentalRequestEvent(
            kind: kind,
            requestedDate: requestedDate,
            method: method,
            contactName: contactName,
            loggedBy: loggedBy,
            notes: notes
        )
        dataStore.logRentalRequest(event, on: rental, in: projectID)
        closeForm()
    }
}

// MARK: - Reconcile supplier invoice

/// Enter the supplier's billed dates + amount and check them against our
/// documented dates. Shows the discrepancy (days + estimated $), then lets you
/// confirm or dispute. Approving updates the job Cost to the billed amount.
struct ReconcileInvoiceSheet: View {
    let rental: EquipmentRental
    let projectID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    @State private var invoiceNumber = ""
    @State private var receivedDate = Date()
    @State private var billedStart = Date()
    @State private var billedEnd = Date()
    @State private var billedAmountText = ""
    @State private var status: InvoiceCheckStatus = .underReview
    @State private var notes = ""

    private var billedAmount: Decimal? {
        let cleaned = billedAmountText.replacingOccurrences(of: ",", with: "")
        return cleaned.isEmpty ? nil : Decimal(string: cleaned)
    }

    private var ourOffRent: Date? { rental.documentedOffRentDate }

    /// Days the invoice bills past our documented off-rent date (>0 = overbilled).
    private var endOverbillDays: Int? {
        guard let off = ourOffRent else { return nil }
        return Calendar.current.dateComponents([.day], from: off.startOfDay, to: billedEnd.startOfDay).day
    }
    private var startDeltaDays: Int {
        Calendar.current.dateComponents([.day], from: rental.documentedStartDate.startOfDay, to: billedStart.startOfDay).day ?? 0
    }
    private var estOverbill: Decimal? {
        guard let d = endOverbillDays, d > 0 else { return nil }
        return Decimal(d) * rental.dailyRate
    }

    var body: some View {
        EntryFormScaffold(
            title: "Reconcile Invoice",
            icon: AppIcons.invoice,
            saveTitle: "Save",
            onCancel: closeForm,
            onSave: save
        ) {
            EntrySection("Our Records", systemImage: "checkmark.shield") {
                InfoRow(label: "Equipment", value: rental.equipmentName)
                InfoRow(label: "Documented start", value: rental.documentedStartDate.shortDate)
                InfoRow(label: "Documented off-rent",
                        value: ourOffRent?.shortDate ?? "— (no pickup request / not closed)")
                InfoRow(label: "Our estimate", value: rental.calculatedCost?.currencyFormatted ?? rental.estimatedActiveCost.currencyFormatted)
            }

            EntrySection("Supplier Invoice", systemImage: AppIcons.document) {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    LabeledField(label: "Invoice #") {
                        TextField("e.g. INV-44821", text: $invoiceNumber).textFieldStyle(.appField)
                    }
                    LabeledField(label: "Received") {
                        DatePicker("", selection: $receivedDate, displayedComponents: .date)
                            .labelsHidden().appControlSurface()
                    }
                }
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    LabeledField(label: "Billed Start") {
                        DatePicker("", selection: $billedStart, displayedComponents: .date)
                            .labelsHidden().appControlSurface()
                    }
                    LabeledField(label: "Billed End") {
                        DatePicker("", selection: $billedEnd, displayedComponents: .date)
                            .labelsHidden().appControlSurface()
                    }
                }
                LabeledField(label: "Billed Amount") {
                    CurrencyInput(placeholder: "0", text: $billedAmountText)
                }
            }

            EntrySection("Comparison", systemImage: "arrow.left.arrow.right") {
                comparisonRow(
                    label: "Start date",
                    detail: startDeltaDays == 0 ? "Matches our record" :
                        "\(abs(startDeltaDays)) day\(abs(startDeltaDays) == 1 ? "" : "s") \(startDeltaDays > 0 ? "after" : "before") our \(rental.documentedStartDate.shortDate)",
                    ok: startDeltaDays == 0
                )
                comparisonRow(
                    label: "End / off-rent",
                    detail: endDetail,
                    ok: (endOverbillDays ?? 0) <= 0
                )
                if let est = estOverbill {
                    HStack {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.orange)
                        Text("Estimated over-bill: ~\(est.currencyFormatted) (\(endOverbillDays ?? 0) extra day\((endOverbillDays ?? 0) == 1 ? "" : "s") @ \(rental.dailyRate.currencyFormatted)/day)")
                            .font(.caption).foregroundColor(.orange)
                        Spacer()
                    }
                }
                if let billed = billedAmount, let est = rental.calculatedCost {
                    let delta = billed - est
                    InfoRow(label: "Billed vs our estimate",
                            value: "\(delta >= 0 ? "+" : "")\(delta.currencyFormatted)")
                }
            }

            EntrySection("Result", systemImage: "checkmark.circle") {
                LabeledField(label: "Status") {
                    Picker("", selection: $status) {
                        ForEach([InvoiceCheckStatus.underReview, .matches, .disputed, .approved]) { s in
                            Label(s.rawValue, systemImage: s.icon).tag(s)
                        }
                    }
                    .labelsHidden().pickerStyle(.menu).appControlSurface()
                }
                if status == .approved {
                    Text("Approving will set this rental's job Cost to the billed amount.")
                        .font(.caption2).foregroundColor(AppTheme.tertiaryText)
                }
                LabeledField(label: "Notes") {
                    NotesField(text: $notes, minHeight: 60)
                }
            }
        }
        #if os(macOS)
        .frame(width: 560, height: 680)
        #endif
        .onAppear { seedFromExistingOrDefaults() }
    }

    private var endDetail: String {
        guard let d = endOverbillDays else { return "No off-rent date on record yet" }
        if d == 0 { return "Matches our off-rent date" }
        if d > 0 { return "\(d) day\(d == 1 ? "" : "s") PAST our \(ourOffRent?.shortDate ?? "") — possible over-bill" }
        return "\(abs(d)) day\(abs(d) == 1 ? "" : "s") before our off-rent date"
    }

    @ViewBuilder
    private func comparisonRow(label: String, detail: String, ok: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(ok ? .green : .orange)
            VStack(alignment: .leading, spacing: 1) {
                Text(label).font(.caption).fontWeight(.medium)
                Text(detail).font(.caption2).foregroundColor(AppTheme.secondaryText)
            }
            Spacer()
        }
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func seedFromExistingOrDefaults() {
        invoiceNumber = rental.supplierInvoiceNumber ?? ""
        receivedDate = rental.invoiceReceivedDate ?? Date()
        billedStart = rental.billedStartDate ?? rental.documentedStartDate
        billedEnd = rental.billedEndDate ?? rental.documentedOffRentDate ?? Date()
        if let a = rental.billedAmount { billedAmountText = NSDecimalNumber(decimal: a).stringValue }
        if rental.invoiceStatus != .notReceived { status = rental.invoiceStatus }
        notes = rental.invoiceCheckNotes ?? ""
    }

    private func save() {
        dataStore.reconcileInvoice(
            rental,
            invoiceNumber: invoiceNumber,
            receivedDate: receivedDate,
            billedStart: billedStart,
            billedEnd: billedEnd,
            billedAmount: billedAmount,
            status: status,
            notes: notes,
            in: projectID
        )
        closeForm()
    }
}

// MARK: - Batch delivery request (project-level)

/// Request several pieces of equipment to be delivered to a project on the same
/// date — the documented "here's what I need on site Monday" request. Logs a
/// timestamped `deliveryRequested` event on each selected unit (so each carries
/// the same paper trail the per-item Request Delivery produces).
struct BatchDeliveryRequestSheet: View {
    let rentals: [EquipmentRental]
    let projectID: CKRecord.ID
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.inlineDismiss) private var inlineDismiss

    @State private var selected: Set<UUID> = []
    @State private var deliveryDate = Date()
    @State private var method: RentalContactMethod = .text
    @State private var contactName = ""
    @State private var loggedBy = ""
    @State private var notes = ""

    var body: some View {
        EntryFormScaffold(
            title: "Request Equipment Delivery",
            icon: AppIcons.equipment,
            saveTitle: selected.isEmpty ? "Select Units" : "Log \(selected.count) Request\(selected.count == 1 ? "" : "s")",
            saveDisabled: selected.isEmpty,
            onCancel: closeForm,
            onSave: save
        ) {
            EntrySection("Deliver On", systemImage: AppIcons.calendar) {
                LabeledField(label: "Requested Delivery Date") {
                    DatePicker("", selection: $deliveryDate, displayedComponents: .date)
                        .labelsHidden().appControlSurface()
                }
            }

            EntrySection("Equipment (\(selected.count) of \(rentals.count))", systemImage: AppIcons.equipment) {
                if rentals.isEmpty {
                    Text("No equipment on this project yet. Add rentals first, then request their delivery here.")
                        .font(.caption).foregroundColor(AppTheme.secondaryText)
                } else {
                    HStack {
                        Button(selected.count == rentals.count ? "Clear All" : "Select All") {
                            selected = selected.count == rentals.count ? [] : Set(rentals.map { $0.id })
                        }
                        .font(.caption).buttonStyle(.appSecondary)
                        Spacer()
                    }
                    ForEach(rentals) { r in
                        Button {
                            if selected.contains(r.id) { selected.remove(r.id) } else { selected.insert(r.id) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: selected.contains(r.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selected.contains(r.id) ? AppTheme.primaryOrange : .secondary)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(r.equipmentName).font(.callout).foregroundColor(.primary)
                                    if !r.unitInfo.isEmpty {
                                        Text(r.unitInfo).font(.caption2).foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                RentalLifecycleBadge(lifecycle: r.lifecycle)
                            }
                            .padding(.vertical, 3).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            EntrySection("Request Details", systemImage: "shippingbox.and.arrow.backward.fill") {
                HStack(alignment: .top, spacing: AppTheme.Spacing.md) {
                    LabeledField(label: "How Requested") {
                        Picker("", selection: $method) {
                            ForEach(RentalContactMethod.allCases) { m in
                                Label(m.rawValue, systemImage: m.icon).tag(m)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).appControlSurface()
                    }
                    LabeledField(label: "Supplier Contact") {
                        TextField("Agent name", text: $contactName).textFieldStyle(.appField)
                    }
                }
                LabeledField(label: "Requested By (you)") {
                    TextField("Your name", text: $loggedBy).textFieldStyle(.appField)
                }
                LabeledField(label: "Notes") {
                    NotesField(text: $notes, minHeight: 50)
                }
                Text("Logs a timestamped delivery request on each selected unit for \(deliveryDate.shortDate) — your documented record for this project's delivery.")
                    .font(.caption2).foregroundColor(AppTheme.tertiaryText)
            }
        }
        #if os(macOS)
        .frame(width: 560, height: 700)
        #endif
        .onAppear {
            // Pre-select units that haven't been requested/delivered yet.
            selected = Set(rentals.filter { $0.firstDeliveryRequest == nil }.map { $0.id })
        }
    }

    private func closeForm() { (inlineDismiss ?? { dismiss() })() }

    private func save() {
        for r in rentals where selected.contains(r.id) {
            let event = RentalRequestEvent(
                kind: .deliveryRequested,
                requestedDate: deliveryDate,
                method: method,
                contactName: contactName,
                loggedBy: loggedBy,
                notes: notes
            )
            dataStore.logRentalRequest(event, on: r, in: projectID)
        }
        closeForm()
    }
}
