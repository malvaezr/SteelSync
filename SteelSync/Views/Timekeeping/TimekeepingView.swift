import SwiftUI

struct TimekeepingView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedTab = "Employees"
    @State private var showAddEmployee = false
    @State private var selectedEmployee: Employee?
    @State private var searchText = ""

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
    private var employeeManagement: some View {
        PlatformSplitView {
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
                                Button("Delete", role: .destructive) { dataStore.deleteEmployee(employee) }
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
            .frame(minWidth: 450)
            #endif

            if let employee = selectedEmployee {
                EmployeeDetailPanel(employee: employee)
                    #if os(macOS)
                    .frame(minWidth: 350)
                    #endif
            } else {
                EmptyStateView(icon: "person.crop.circle", title: "No Employee Selected",
                               message: "Select an employee to view details.",
                               buttonTitle: "Add Employee") { showAddEmployee = true }
                #if os(macOS)
                .frame(minWidth: 350)
                #endif
            }
        }
    }

    // MARK: - Crew Management
    private var crewManagement: some View {
        VStack(spacing: AppTheme.Spacing.lg) {
            EmptyStateView(icon: "person.3.fill", title: "Crew Assignments",
                           message: "Create weekly assignments to manage crew deployment across projects. Crew members can clock in/out using a shared token code.")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
                    Button("Edit") { showEdit = true }.buttonStyle(.bordered)
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
            HStack {
                Text("Add Employee").font(AppTheme.Typography.title2)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(firstName.isEmpty || lastName.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryOrange)
            }
            .padding()
            Divider()
            Form {
                Section("Personal Information") {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                    TextField("Phone", text: $phone)
                    TextField("Email", text: $email)
                }
                Section("Employment") {
                    Picker("Type", selection: $employeeType) {
                        ForEach(EmployeeType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    HStack { Text("$"); TextField("Hourly Rate", text: $hourlyRate) }
                }
                Section("Notes") {
                    TextEditor(text: $notes).frame(height: 60)
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 450, height: 480)
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
            HStack {
                Text("Edit Employee").font(AppTheme.Typography.title2)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryOrange)
            }
            .padding()
            Divider()
            Form {
                Section("Personal Information") {
                    TextField("First Name", text: $firstName)
                    TextField("Last Name", text: $lastName)
                    TextField("Phone", text: $phone)
                    TextField("Email", text: $email)
                }
                Section("Employment") {
                    Picker("Type", selection: $employeeType) {
                        ForEach(EmployeeType.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                    HStack { Text("$"); TextField("Hourly Rate", text: $hourlyRate) }
                    Picker("Status", selection: $status) {
                        ForEach(EmployeeStatus.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
                Section("Notes") {
                    TextEditor(text: $notes).frame(height: 60)
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 450, height: 520)
        #endif
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
