import SwiftUI

struct TimekeepingView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedTab = "Employees"
    @State private var showAddEmployee = false
    @State private var selectedEmployee: Employee?
    @State private var searchText = ""
    @State private var employeeToDelete: Employee?

    var filteredEmployees: [Employee] {
        if searchText.isEmpty { return dataStore.employees }
        return dataStore.employees.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchText) ||
            $0.employeeID.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Tab selector
            HStack(spacing: 0) {
                ForEach(["Employees", "Crew Management"], id: \.self) { tab in
                    Button(action: { selectedTab = tab }) {
                        Text(tab)
                            .font(.callout)
                            .fontWeight(selectedTab == tab ? .semibold : .regular)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(selectedTab == tab ? AppTheme.primaryOrange.opacity(0.1) : Color.clear)
                            .foregroundColor(selectedTab == tab ? AppTheme.primaryOrange : AppTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(.horizontal)
            .background(AppTheme.secondaryBackground)

            Divider()

            if selectedTab == "Employees" {
                employeeManagement
            } else {
                crewManagement
            }
        }
        .sheet(isPresented: $showAddEmployee) {
            AddEmployeeView()
        }
        .sheet(item: $employeeToDelete) { employee in
            ConfirmationPinSheet(
                title: "Delete Employee",
                detail: "\(employee.fullName)\n\nTheir timesheet history will remain in the records but they won't be assignable to new entries. This cannot be undone.",
                confirmLabel: "Delete",
                onConfirm: {
                    dataStore.deleteEmployee(employee)
                    if selectedEmployee?.id == employee.id { selectedEmployee = nil }
                }
            )
        }
        .navigationTitle("Timekeeping")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showAddEmployee = true }) {
                    Label("Add Employee", systemImage: "person.badge.plus")
                }
            }
        }
    }

    // MARK: - Employee Management
    @ViewBuilder
    private var employeeManagement: some View {
        #if os(iOS)
        // Compact iPad (portrait full-screen, Slide Over, narrow Stage
        // Manager) is too narrow for a side-by-side list+detail — drop
        // to a list-only view that opens detail in a full-screen cover.
        // Regular width keeps the existing two-pane split.
        GeometryReader { proxy in
            if proxy.size.width < 800 {
                employeeListPane
                    .fullScreenCover(item: $selectedEmployee) { employee in
                        NavigationStack {
                            EmployeeDetailPanel(employee: employee)
                                .navigationTitle(employee.fullName)
                                .navigationBarTitleDisplayMode(.inline)
                                .toolbar {
                                    ToolbarItem(placement: .cancellationAction) {
                                        Button("Done") { selectedEmployee = nil }
                                    }
                                }
                        }
                    }
            } else {
                PlatformSplitView {
                    employeeListPane
                    employeeDetailPane
                }
            }
        }
        #else
        PlatformSplitView {
            employeeListPane
            employeeDetailPane
        }
        #endif
    }

    @ViewBuilder
    private var employeeListPane: some View {
        VStack(spacing: 0) {
            // Stats
            HStack(spacing: AppTheme.Spacing.sm) {
                MetricCard(title: "Total Employees", value: "\(dataStore.employees.count)", icon: "person.2.fill", color: .blue)
                MetricCard(title: "Active", value: "\(dataStore.activeEmployees.count)", icon: "checkmark.circle.fill", color: .green)
                MetricCard(title: "Foremen", value: "\(dataStore.foremen.count)", icon: "person.fill.checkmark", color: AppTheme.primaryOrange)
            }
            .padding(AppTheme.Spacing.md)

            List(selection: $selectedEmployee) {
                ForEach(filteredEmployees) { employee in
                    EmployeeRow(employee: employee)
                        .tag(employee)
                        .contextMenu {
                            Button("Edit") { selectedEmployee = employee }
                            Divider()
                            Button("Delete…", role: .destructive) { employeeToDelete = employee }
                        }
                }
            }
            #if os(macOS)
            .listStyle(.inset(alternatesRowBackgrounds: true))
            #else
            .listStyle(.insetGrouped)
            #endif
            .searchable(text: $searchText, prompt: "Search employees...")
        }
        #if os(macOS)
        .frame(minWidth: 220, idealWidth: 450)
        #endif
    }

    @ViewBuilder
    private var employeeDetailPane: some View {
        if let employee = selectedEmployee {
            EmployeeDetailPanel(employee: employee)
                #if os(macOS)
                .frame(minWidth: 220, idealWidth: 350)
                #endif
        } else {
            EmptyStateView(icon: "person.crop.circle", title: "No Employee Selected",
                           message: "Select an employee to view details.",
                           buttonTitle: "Add Employee") { showAddEmployee = true }
            #if os(macOS)
            .frame(minWidth: 220, idealWidth: 350)
            #endif
        }
    }

    // MARK: - Crew Management
    private var crewManagement: some View {
        CrewManagementView()
    }
}

// MARK: - Employee Row
struct EmployeeRow: View {
    let employee: Employee

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Circle()
                .fill(employee.isForeman ? AppTheme.primaryOrange : AppTheme.primaryGreen)
                .frame(width: 32, height: 32)
                .overlay(
                    Text(String(employee.firstName.prefix(1)))
                        .font(.callout.bold())
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(employee.fullName)
                        .fontWeight(.medium)
                    Text(employee.employeeID)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                HStack(spacing: AppTheme.Spacing.sm) {
                    StatusBadge(text: employee.employeeType.displayName,
                                color: employee.isForeman ? AppTheme.primaryOrange : .blue)
                    StatusBadge(text: employee.status.displayName,
                                color: employee.isActive ? .green : .red)
                }
            }

            Spacer()

            Text(employee.defaultHourlyRate.currencyFormatted + "/hr")
                .font(.callout)
                .fontWeight(.medium)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }
}

// MARK: - Employee Detail Panel
struct EmployeeDetailPanel: View {
    let employee: Employee
    @EnvironmentObject var dataStore: DataStore
    @State private var showEdit = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                // Header
                HStack {
                    Circle()
                        .fill(employee.isForeman ? AppTheme.primaryOrange : AppTheme.primaryGreen)
                        .frame(width: 48, height: 48)
                        .overlay(
                            Text(String(employee.firstName.prefix(1)) + String(employee.lastName.prefix(1)))
                                .font(.title3.bold())
                                .foregroundColor(.white)
                        )
                    VStack(alignment: .leading) {
                        Text(employee.fullName).font(AppTheme.Typography.title3)
                        Text(employee.employeeID).foregroundColor(.secondary)
                    }
                    Spacer()
                    Button("Edit") { showEdit = true }.buttonStyle(.appSecondary)
                }

                GroupBox("Details") {
                    VStack(spacing: AppTheme.Spacing.sm) {
                        InfoRow(label: "Type", value: employee.employeeType.displayName, icon: "person.fill")
                        Divider()
                        InfoRow(label: "Status", value: employee.status.displayName, icon: "checkmark.circle")
                        Divider()
                        InfoRow(label: "Hourly Rate", value: employee.defaultHourlyRate.currencyFormatted + "/hr", icon: "dollarsign.circle")
                        Divider()
                        if !employee.phone.isEmpty {
                            InfoRow(label: "Phone", value: employee.phone, icon: "phone")
                            Divider()
                        }
                        if !employee.email.isEmpty {
                            InfoRow(label: "Email", value: employee.email, icon: "envelope")
                            Divider()
                        }
                        InfoRow(label: "Added", value: employee.createdDate.shortDate, icon: "calendar")
                    }
                    .padding(.vertical, AppTheme.Spacing.sm)
                }

                if !employee.notes.isEmpty {
                    GroupBox("Notes") {
                        Text(employee.notes).padding(.vertical, AppTheme.Spacing.sm)
                    }
                }
            }
            .padding(AppTheme.Spacing.lg)
        }
        .sheet(isPresented: $showEdit) {
            EditEmployeeView(employee: employee)
        }
    }
}

// MARK: - Add Employee
struct AddEmployeeView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var email = ""
    @State private var employeeType: EmployeeType = .w2
    @State private var hourlyRate = ""
    @State private var notes = ""

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Add Employee",
                saveTitle: "Save",
                saveDisabled: firstName.isEmpty || lastName.isEmpty,
                onCancel: { dismiss() },
                onSave: save
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        SectionTitle(text: "Personal Information")
                        HStack(spacing: AppTheme.Spacing.md) {
                            LabeledField(label: "First Name") {
                                TextField("First", text: $firstName)
                                    .textFieldStyle(.appField)
                            }
                            LabeledField(label: "Last Name") {
                                TextField("Last", text: $lastName)
                                    .textFieldStyle(.appField)
                            }
                        }
                        LabeledField(label: "Phone") {
                            TextField("(555) 555-5555", text: $phone)
                                .textFieldStyle(.appField)
                                #if !os(macOS)
                                .keyboardType(.phonePad)
                                #endif
                        }
                        LabeledField(label: "Email") {
                            TextField("name@example.com", text: $email)
                                .textFieldStyle(.appField)
                                #if !os(macOS)
                                .textInputAutocapitalization(.never)
                                .keyboardType(.emailAddress)
                                #endif
                        }
                    }

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        SectionTitle(text: "Employment")
                        HStack(spacing: AppTheme.Spacing.md) {
                            LabeledField(label: "Type") {
                                Picker("", selection: $employeeType) {
                                    ForEach(EmployeeType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                                }
                                .labelsHidden()
                                .pickerStyle(.menu)
                                .appControlSurface()
                            }
                            LabeledField(label: "Hourly Rate") {
                                CurrencyInput(placeholder: "0.00", text: $hourlyRate)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
                        SectionTitle(text: "Notes")
                        NotesField(text: $notes, minHeight: 70)
                    }
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
        }
        #if os(macOS)
        .frame(width: 520, height: 560)
        #endif
    }

    private func save() {
        let employee = Employee(
            employeeID: dataStore.nextEmployeeID(),
            firstName: firstName, lastName: lastName, email: email, phone: phone,
            employeeType: employeeType,
            defaultHourlyRate: Decimal(string: hourlyRate) ?? 0
        )
        dataStore.addEmployee(employee)
        dismiss()
    }
}

// MARK: - Edit Employee
struct EditEmployeeView: View {
    let employee: Employee
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var firstName: String
    @State private var lastName: String
    @State private var phone: String
    @State private var email: String
    @State private var employeeType: EmployeeType
    @State private var hourlyRate: String
    @State private var status: EmployeeStatus
    @State private var notes: String

    init(employee: Employee) {
        self.employee = employee
        _firstName = State(initialValue: employee.firstName)
        _lastName = State(initialValue: employee.lastName)
        _phone = State(initialValue: employee.phone)
        _email = State(initialValue: employee.email)
        _employeeType = State(initialValue: employee.employeeType)
        _hourlyRate = State(initialValue: "\(employee.defaultHourlyRate)")
        _status = State(initialValue: employee.status)
        _notes = State(initialValue: employee.notes)
    }

    var body: some View {
        VStack(spacing: 0) {
            SheetHeader(
                title: "Edit Employee",
                saveTitle: "Save",
                saveDisabled: firstName.isEmpty || lastName.isEmpty,
                onCancel: { dismiss() },
                onSave: save
            )

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    editEmployeePersonalSection
                    editEmployeeEmploymentSection
                    editEmployeeNotesSection
                }
                .padding(AppTheme.Spacing.lg)
            }
            .background(AppTheme.background)
        }
        #if os(macOS)
        .frame(width: 520, height: 600)
        #endif
    }

    @ViewBuilder private var editEmployeePersonalSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Personal Information")
            HStack(spacing: AppTheme.Spacing.md) {
                LabeledField(label: "First Name") {
                    TextField("First", text: $firstName)
                        .textFieldStyle(.appField)
                }
                LabeledField(label: "Last Name") {
                    TextField("Last", text: $lastName)
                        .textFieldStyle(.appField)
                }
            }
            LabeledField(label: "Phone") {
                TextField("(555) 555-5555", text: $phone)
                    .textFieldStyle(.appField)
                    #if !os(macOS)
                    .keyboardType(.phonePad)
                    #endif
            }
            LabeledField(label: "Email") {
                TextField("name@example.com", text: $email)
                    .textFieldStyle(.appField)
                    #if !os(macOS)
                    .textInputAutocapitalization(.never)
                    .keyboardType(.emailAddress)
                    #endif
            }
        }
    }

    @ViewBuilder private var editEmployeeEmploymentSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Employment")
            HStack(spacing: AppTheme.Spacing.md) {
                LabeledField(label: "Type") {
                    Picker("", selection: $employeeType) {
                        ForEach(EmployeeType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .appControlSurface()
                }
                LabeledField(label: "Hourly Rate") {
                    CurrencyInput(placeholder: "0.00", text: $hourlyRate)
                }
            }
            LabeledField(label: "Status") {
                Picker("", selection: $status) {
                    ForEach(EmployeeStatus.allCases, id: \.self) { Text($0.displayName).tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .appControlSurface()
            }
        }
    }

    @ViewBuilder private var editEmployeeNotesSection: some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.md) {
            SectionTitle(text: "Notes")
            NotesField(text: $notes, minHeight: 70)
        }
    }

    private func save() {
        var updated = employee
        updated.firstName = firstName; updated.lastName = lastName
        updated.phone = phone; updated.email = email
        updated.employeeType = employeeType
        updated.defaultHourlyRate = Decimal(string: hourlyRate) ?? 0
        updated.status = status; updated.notes = notes
        updated.updatedDate = Date()
        dataStore.updateEmployee(updated)
        dismiss()
    }
}
