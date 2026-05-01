import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var dataStore: DataStore
    @ObservedObject private var themeManager = ThemeManager.shared
    @ObservedObject private var llmService = LLMService.shared
    @StateObject private var memoryMonitor = MemoryMonitor.shared
    @ObservedObject private var notificationService = NotificationService.shared
    @State private var showModelFilePicker = false
    @State private var snapshots: [SnapshotDescriptor] = []
    @State private var snapshotLabel: String = ""
    @State private var snapshotStatus: String = ""
    @State private var snapshotBusy: Bool = false
    @State private var snapshotToRestore: SnapshotDescriptor?
    @State private var snapshotToDelete: SnapshotDescriptor?

    // Confirmation PIN management
    @State private var pinCurrentInput: String = ""
    @State private var pinNewInput: String = ""
    @State private var pinChangeStatus: String = ""
    @State private var pinChangeStatusIsError: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                // Theme Section
                GroupBox {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("Color Theme")
                            .font(AppTheme.Typography.headline)

                        Text("Choose an accent color for the app. All buttons, highlights, and badges will update.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: AppTheme.Spacing.md) {
                            ForEach(AppColorTheme.allCases, id: \.self) { theme in
                                ThemeCard(theme: theme, isSelected: themeManager.current == theme, isDark: themeManager.isDarkMode) {
                                    withAnimation(.easeInOut(duration: 0.3)) {
                                        themeManager.current = theme
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                // Appearance Mode
                GroupBox {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("Appearance")
                            .font(AppTheme.Typography.headline)

                        HStack(spacing: AppTheme.Spacing.md) {
                            modeButton(label: "Dark", icon: "moon.fill", isDark: true)
                            modeButton(label: "Light", icon: "sun.max.fill", isDark: false)
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                // AI Model Section
                GroupBox {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("AI Model")
                            .font(AppTheme.Typography.headline)

                        Text("Download a local AI model for smarter, conversational responses. Runs entirely on-device — your data never leaves this machine.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        aiModelStatusView
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                // Notifications Section
                GroupBox {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        HStack {
                            Text("Notifications")
                                .font(AppTheme.Typography.headline)
                            Spacer()
                            if notificationService.permissionStatus == .notDetermined {
                                Button("Enable") { notificationService.requestPermission() }
                                    .buttonStyle(.appPrimary)
                                    .controlSize(.small)
                            } else if notificationService.permissionStatus == .denied {
                                Text("Denied in System Settings")
                                    .font(.caption)
                                    .foregroundColor(.red)
                            }
                        }

                        Text("Morning batch notifications at the time you choose. Each type can be toggled independently.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Toggle("Notifications Enabled", isOn: $notificationService.isEnabled)

                        if notificationService.isEnabled {
                            HStack {
                                Text("Batch Time")
                                Spacer()
                                Picker("Hour", selection: $notificationService.batchHour) {
                                    ForEach(5..<22) { h in
                                        Text("\(h > 12 ? h - 12 : h) \(h >= 12 ? "PM" : "AM")").tag(h)
                                    }
                                }
                                .frame(width: 100)
                            }

                            Divider()

                            Toggle("Overdue Tasks", isOn: $notificationService.enableOverdueTasks)
                            Toggle("Overdue RFIs", isOn: $notificationService.enableOverdueRFIs)
                            Toggle("Overdue Invoices", isOn: $notificationService.enableOverdueInvoices)
                            Toggle("Bids Due Within 24h", isOn: $notificationService.enableBidDueSoon)
                            Toggle("Bid Follow-Up Reminders", isOn: $notificationService.enableBidFollowUp)
                            Toggle("Milestone Approaching", isOn: $notificationService.enableMilestoneApproaching)
                            Toggle("Payment Received", isOn: $notificationService.enablePaymentReceived)

                            Button("Reschedule Now") {
                                notificationService.scheduleMorningBatch(from: dataStore)
                            }
                            .buttonStyle(.appSecondary)
                            .controlSize(.small)
                            .padding(.top, 4)
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                // Snapshot Backups Section
                GroupBox {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        HStack {
                            Text("Snapshot Backups")
                                .font(AppTheme.Typography.headline)
                            Spacer()
                            Text("\(snapshots.count) saved")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Text("Captures EVERY tab's data into one read-only archive: projects, clients, bids, employees, todos, calendar events, change orders, payments, payroll, costs, equipment rentals, schedule tasks, pay applications, invoices, timesheets, RFIs, planning pads, assistant conversations, and the audit log — plus copies of every referenced file. Stored in your Documents folder. The live data is never modified when creating a snapshot. Restore later to revert to that exact state.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            TextField("Optional label (e.g., before year-end close)", text: $snapshotLabel)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                createSnapshot()
                            } label: {
                                Label("Create Snapshot", systemImage: "archivebox.fill")
                            }
                            .buttonStyle(.appPrimary)
                            .disabled(snapshotBusy)
                        }

                        if !snapshotStatus.isEmpty {
                            Text(snapshotStatus)
                                .font(.caption)
                                .foregroundColor(snapshotStatus.hasPrefix("Error") ? .red : .green)
                        }

                        if snapshots.isEmpty {
                            Text("No snapshots yet.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.top, 4)
                        } else {
                            Divider()
                            VStack(spacing: 6) {
                                ForEach(snapshots) { snapshot in
                                    snapshotRow(snapshot)
                                }
                            }
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                // Confirmation PIN Section
                GroupBox {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        HStack {
                            Text("Confirmation PIN")
                                .font(AppTheme.Typography.headline)
                            Spacer()
                            if PinService.isUsingDefault {
                                Text("Using default")
                                    .font(.caption)
                                    .foregroundColor(.orange)
                            } else {
                                Text("Custom PIN")
                                    .font(.caption)
                                    .foregroundColor(.green)
                            }
                        }

                        Text("Required when deleting payments and other destructive actions. The default is **\(PinService.defaultPin)** — change it below to something only you'll remember. If you forget your PIN, use **Reset to Default** to fall back to \(PinService.defaultPin) without losing any data.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: AppTheme.Spacing.sm) {
                            SecureField("Current PIN", text: $pinCurrentInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 120)
                                #if !os(macOS)
                                .keyboardType(.numberPad)
                                #endif
                            SecureField("New PIN (4 digits)", text: $pinNewInput)
                                .textFieldStyle(.roundedBorder)
                                .frame(width: 160)
                                #if !os(macOS)
                                .keyboardType(.numberPad)
                                #endif
                            Button("Change PIN") { changePin() }
                                .buttonStyle(.appPrimary)
                                .disabled(!PinService.isValidPinFormat(pinNewInput) || pinCurrentInput.isEmpty)
                            Spacer()
                            Button {
                                resetPin()
                            } label: {
                                Label("Reset to Default", systemImage: "arrow.counterclockwise")
                            }
                            .buttonStyle(.appSecondary)
                        }

                        if !pinChangeStatus.isEmpty {
                            Text(pinChangeStatus)
                                .font(.caption)
                                .foregroundColor(pinChangeStatusIsError ? .red : .green)
                        }
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                    .onChange(of: pinCurrentInput) { _, new in
                        let cleaned = String(new.filter(\.isNumber).prefix(4))
                        if cleaned != new { pinCurrentInput = cleaned }
                        pinChangeStatus = ""
                    }
                    .onChange(of: pinNewInput) { _, new in
                        let cleaned = String(new.filter(\.isNumber).prefix(4))
                        if cleaned != new { pinNewInput = cleaned }
                        pinChangeStatus = ""
                    }
                }

                // Diagnostics Section
                GroupBox {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        Text("Diagnostics")
                            .font(AppTheme.Typography.headline)

                        Text("Monitor app resource usage. The AI model and KV cache live inside this process, so memory will jump when the model is loaded.")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack(spacing: AppTheme.Spacing.lg) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Memory in Use")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(memoryMonitor.formattedUsed)
                                    .font(.title2.monospacedDigit())
                                    .fontWeight(.semibold)
                                    .foregroundColor(memoryMonitor.statusColor)
                            }
                            VStack(alignment: .leading, spacing: 4) {
                                Text("of Device RAM")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text("\(memoryMonitor.formattedTotal) (\(String(format: "%.1f%%", memoryMonitor.percentage)))")
                                    .font(.title2.monospacedDigit())
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }

                        // Visual bar
                        ZStack(alignment: .leading) {
                            Capsule()
                                .fill(Color.gray.opacity(0.2))
                                .frame(height: 8)
                            Capsule()
                                .fill(memoryMonitor.statusColor)
                                .frame(width: max(0, min(1, memoryMonitor.percentage / 100)) * 240, height: 8)
                                .animation(.easeInOut(duration: 0.5), value: memoryMonitor.percentage)
                        }
                        .frame(maxWidth: 240, alignment: .leading)
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                // App Info Section
                GroupBox {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                        Text("About")
                            .font(AppTheme.Typography.headline)

                        InfoRow(label: "App", value: "SteelSync")
                        InfoRow(label: "Version", value: "1.0")
                        InfoRow(label: "Company", value: "J&R Steel Welding LLC")
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .navigationTitle("Settings")
        .onAppear {
            memoryMonitor.start()
            refreshSnapshotList()
        }
        .onDisappear { memoryMonitor.stop() }
        .confirmationDialog(
            "Restore this snapshot?",
            isPresented: Binding(
                get: { snapshotToRestore != nil },
                set: { if !$0 { snapshotToRestore = nil } }
            ),
            presenting: snapshotToRestore
        ) { snapshot in
            Button("Restore", role: .destructive) {
                restoreSnapshot(snapshot)
                snapshotToRestore = nil
            }
            Button("Cancel", role: .cancel) { snapshotToRestore = nil }
        } message: { snapshot in
            Text("This will replace all current data with the contents of \"\(snapshot.folderName)\" from \(snapshot.formattedDate). A pre-restore backup of your current state will be created first, so this is reversible.")
        }
        .confirmationDialog(
            "Delete this snapshot?",
            isPresented: Binding(
                get: { snapshotToDelete != nil },
                set: { if !$0 { snapshotToDelete = nil } }
            ),
            presenting: snapshotToDelete
        ) { snapshot in
            Button("Delete", role: .destructive) {
                deleteSnapshot(snapshot)
                snapshotToDelete = nil
            }
            Button("Cancel", role: .cancel) { snapshotToDelete = nil }
        } message: { snapshot in
            Text("The snapshot folder and all its attachments will be permanently removed. This cannot be undone.")
        }
    }

    // MARK: - Confirmation PIN helpers

    private func changePin() {
        guard PinService.verify(pinCurrentInput) else {
            pinChangeStatus = "Current PIN is incorrect."
            pinChangeStatusIsError = true
            return
        }
        guard PinService.isValidPinFormat(pinNewInput) else {
            pinChangeStatus = "New PIN must be exactly 4 digits."
            pinChangeStatusIsError = true
            return
        }
        PinService.setPin(pinNewInput)
        pinCurrentInput = ""
        pinNewInput = ""
        pinChangeStatus = "PIN updated."
        pinChangeStatusIsError = false
    }

    private func resetPin() {
        PinService.resetToDefault()
        pinCurrentInput = ""
        pinNewInput = ""
        pinChangeStatus = "PIN reset to \(PinService.defaultPin)."
        pinChangeStatusIsError = false
    }

    // MARK: - Snapshot helpers

    @ViewBuilder
    private func snapshotRow(_ snapshot: SnapshotDescriptor) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: "archivebox.fill")
                    .foregroundColor(AppTheme.primaryOrange)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 6) {
                        Text(snapshot.formattedDate)
                            .font(.callout)
                            .fontWeight(.semibold)
                        if !snapshot.manifest.label.isEmpty {
                            Text("· \(snapshot.manifest.label)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    Text("\(snapshot.formattedSize) · \(snapshot.manifest.attachmentCount) attachment file\(snapshot.manifest.attachmentCount == 1 ? "" : "s")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                Spacer()
            Button {
                #if os(macOS)
                NSWorkspace.shared.activateFileViewerSelecting([snapshot.url])
                #endif
            } label: {
                Image(systemName: "folder")
            }
            .buttonStyle(.borderless)
            .help("Show in Finder")

            Button {
                snapshotToRestore = snapshot
            } label: {
                Image(systemName: "arrow.uturn.backward.circle.fill")
                    .foregroundColor(AppTheme.primaryOrange)
            }
            .buttonStyle(.borderless)
            .help("Restore this snapshot")

            Button(role: .destructive) {
                snapshotToDelete = snapshot
            } label: {
                Image(systemName: "trash")
                    .foregroundColor(.red)
            }
            .buttonStyle(.borderless)
            .help("Delete this snapshot")
            }

            // Full per-collection count grid so the user can confirm what's captured
            LazyVGrid(columns: [
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading),
                GridItem(.flexible(), alignment: .leading)
            ], spacing: 2) {
                countChip("Projects", snapshot.manifest.projectCount)
                countChip("Clients", snapshot.manifest.clientCount)
                countChip("Bids", snapshot.manifest.bidCount)
                countChip("Employees", snapshot.manifest.employeeCount)
                countChip("Todos", snapshot.manifest.todoCount)
                countChip("Calendar", snapshot.manifest.calendarEventCount)
                countChip("COs", snapshot.manifest.changeOrderCount)
                countChip("Payments", snapshot.manifest.paymentCount)
                countChip("Payroll", snapshot.manifest.payrollEntryCount)
                countChip("Costs", snapshot.manifest.costCount)
                countChip("Rentals", snapshot.manifest.equipmentRentalCount)
                countChip("Schedule", snapshot.manifest.ganttTaskCount)
                countChip("Pay Apps", snapshot.manifest.payApplicationCount)
                countChip("Invoices", snapshot.manifest.invoiceCount)
                countChip("Timesheets", snapshot.manifest.timesheetEntryCount)
                countChip("RFIs", snapshot.manifest.rfiCount)
                countChip("Planning", snapshot.manifest.planningPadCount)
                countChip("Assistant", snapshot.manifest.assistantMessageCount)
                countChip("Audit", snapshot.manifest.auditLogCount)
            }
            .padding(.leading, 26)  // align with text above the icon
            .padding(.top, 2)
        }
        .padding(.vertical, 6)
    }

    private func countChip(_ label: String, _ count: Int) -> some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 10))
                .foregroundColor(.secondary)
            Text("\(count)")
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundColor(count > 0 ? AppTheme.primaryText : .secondary.opacity(0.5))
        }
    }

    private func refreshSnapshotList() {
        snapshots = SnapshotService.listSnapshots()
    }

    private func createSnapshot() {
        snapshotBusy = true
        snapshotStatus = "Creating snapshot…"
        Task {
            do {
                let descriptor = try SnapshotService.createSnapshot(
                    from: dataStore,
                    label: snapshotLabel
                )
                await MainActor.run {
                    snapshotLabel = ""
                    snapshotStatus = "Created \(descriptor.folderName) (\(descriptor.formattedSize))"
                    refreshSnapshotList()
                    snapshotBusy = false
                }
            } catch {
                await MainActor.run {
                    snapshotStatus = "Error: \(error.localizedDescription)"
                    snapshotBusy = false
                }
            }
        }
    }

    private func restoreSnapshot(_ snapshot: SnapshotDescriptor) {
        do {
            try SnapshotService.restore(from: snapshot, into: dataStore)
            snapshotStatus = "Restored \(snapshot.folderName)"
            refreshSnapshotList()
        } catch {
            snapshotStatus = "Error: \(error.localizedDescription)"
        }
    }

    private func deleteSnapshot(_ snapshot: SnapshotDescriptor) {
        do {
            try SnapshotService.delete(snapshot)
            refreshSnapshotList()
        } catch {
            snapshotStatus = "Error: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private var aiModelStatusView: some View {
        switch llmService.status {
        case .notDownloaded:
            HStack {
                Image(systemName: "cpu").foregroundColor(.secondary)
                VStack(alignment: .leading) {
                    Text("Llama-3.2 8B").font(.callout).fontWeight(.medium)
                    Text("~4.5 GB download").font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                Button("Download") { llmService.downloadModel() }
                    .buttonStyle(.appPrimary)
                Button("Import File...") { showModelFilePicker = true }
                    .buttonStyle(.appSecondary)
            }
            .fileImporter(isPresented: $showModelFilePicker, allowedContentTypes: [.data], allowsMultipleSelection: false) { result in
                if case .success(let urls) = result, let url = urls.first {
                    _ = llmService.importModelFile(from: url)
                }
            }

        case .downloading(let progress):
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Downloading...").font(.callout)
                    Spacer()
                    Text("\(Int(progress * 100))%").font(.caption).foregroundColor(.secondary)
                    Button("Cancel") { llmService.cancelDownload() }
                        .font(.caption).foregroundColor(.red)
                }
                ProgressView(value: progress)
                    .tint(AppTheme.primaryOrange)
            }

        case .downloaded, .loading, .ready, .generating:
            HStack {
                Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
                VStack(alignment: .leading) {
                    Text("Llama-3.2 8B").font(.callout).fontWeight(.medium)
                    Text(llmService.status == .ready ? "Loaded & Ready" :
                         llmService.status == .generating ? "Generating..." :
                         llmService.status == .loading ? "Loading..." :
                         "Downloaded (\(llmService.modelFileSizeFormatted))")
                        .font(.caption2).foregroundColor(.secondary)
                }
                Spacer()
                if llmService.status == .downloaded {
                    Button("Load") { llmService.loadModel() }
                        .buttonStyle(.appSecondary)
                }
                Button("Delete", role: .destructive) { llmService.deleteModel() }
                    .font(.caption)
            }

        case .error(let msg):
            HStack {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(.red)
                Text(msg).font(.caption).foregroundColor(.red)
                Spacer()
                Button("Retry") { llmService.downloadModel() }
                    .buttonStyle(.appSecondary)
            }
        }
    }

    private func modeButton(label: String, icon: String, isDark: Bool) -> some View {
        let isSelected = themeManager.isDarkMode == isDark
        return Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                themeManager.isDarkMode = isDark
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? AppTheme.primaryOrange : .secondary)
                Text(label)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundColor(isSelected ? AppTheme.primaryOrange : .secondary)
            }
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(isSelected ? AppTheme.primaryOrange.opacity(0.1) : Color.gray.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(isSelected ? AppTheme.primaryOrange : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Theme Card

private struct ThemeCard: View {
    let theme: AppColorTheme
    let isSelected: Bool
    let isDark: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 10) {
                // Mini preview of the full theme
                VStack(spacing: 0) {
                    // Fake sidebar + content preview
                    HStack(spacing: 0) {
                        // Mini sidebar
                        VStack(alignment: .leading, spacing: 3) {
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.accent)
                                .frame(width: 28, height: 5)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.secondaryText(dark: isDark))
                                .frame(width: 22, height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.secondaryText(dark: isDark))
                                .frame(width: 24, height: 4)
                        }
                        .padding(6)
                        .frame(width: 44)
                        .background(theme.sidebarBackground(dark: isDark))

                        // Mini content area
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 4) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(theme.accent.opacity(0.3))
                                    .frame(width: 20, height: 14)
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(theme.accent.opacity(0.3))
                                    .frame(width: 20, height: 14)
                            }
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.primaryText(dark: isDark).opacity(0.4))
                                .frame(width: 50, height: 4)
                            RoundedRectangle(cornerRadius: 2)
                                .fill(theme.secondaryText(dark: isDark).opacity(0.3))
                                .frame(width: 36, height: 3)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.background(dark: isDark))
                    }
                }
                .frame(height: 50)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.gray.opacity(0.3), lineWidth: 0.5))

                // Color dots
                HStack(spacing: 4) {
                    Circle().fill(theme.accent).frame(width: 12, height: 12)
                    Circle().fill(theme.background(dark: isDark)).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
                    Circle().fill(theme.cardBackground(dark: isDark)).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(Color.gray.opacity(0.3), lineWidth: 0.5))
                    Circle().fill(theme.secondaryText(dark: isDark)).frame(width: 12, height: 12)
                }

                Image(systemName: theme.icon)
                    .font(.caption)
                    .foregroundColor(theme.accent)

                Text(theme.rawValue)
                    .font(.caption)
                    .fontWeight(isSelected ? .bold : .regular)
                    .foregroundColor(isSelected ? theme.accent : .secondary)

                Text(theme.description)
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(height: 30)

                if isSelected {
                    Label("Active", systemImage: "checkmark.circle.fill")
                        .font(.caption2)
                        .foregroundColor(theme.accent)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(AppTheme.Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .fill(isSelected ? theme.accent.opacity(0.08) : Color.gray.opacity(0.05))
            )
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(isSelected ? theme.accent : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
    }
}
