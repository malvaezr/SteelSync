#if STEELSYNC_IPHONE
import SwiftUI

struct IPhoneCrewTab: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedSegment = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Crew", selection: $selectedSegment) {
                    Text("Clients").tag(0)
                    Text("Employees").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, AppTheme.Spacing.md)
                .padding(.vertical, AppTheme.Spacing.sm)

                if selectedSegment == 0 {
                    clientsList
                } else {
                    employeesList
                }
            }
            .navigationTitle("Crew")
            .navigationDestination(for: Client.self) { client in
                IPhoneClientDetailView(client: client)
            }
            .navigationDestination(for: Employee.self) { employee in
                IPhoneEmployeeDetailView(employee: employee)
            }
        }
    }

    // MARK: - Clients List
    @ViewBuilder
    private var clientsList: some View {
        if dataStore.clients.isEmpty {
            EmptyStateView(
                icon: "person.crop.rectangle.stack",
                title: "No Clients",
                message: "Clients will appear here once added on the Mac."
            )
        } else {
            List {
                ForEach(dataStore.clients) { client in
                    NavigationLink(value: client) {
                        ClientRowView(client: client)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Employees List
    @ViewBuilder
    private var employeesList: some View {
        if dataStore.employees.isEmpty {
            EmptyStateView(
                icon: "person.2",
                title: "No Employees",
                message: "Employees will appear here once added on the Mac."
            )
        } else {
            List {
                ForEach(dataStore.employees) { employee in
                    NavigationLink(value: employee) {
                        EmployeeRowView(employee: employee)
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Client Row
    @ViewBuilder
    private func ClientRowView(client: Client) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(client.name)
                    .font(.headline)
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(1)
                Spacer()
                StatusBadge(
                    text: client.preferredRateType == .generalContractor ? "GC" : "Sub",
                    color: client.preferredRateType == .generalContractor ? .blue : .purple
                )
            }

            if !client.contactName.isEmpty {
                Text(client.contactName)
                    .font(.subheadline)
                    .foregroundColor(AppTheme.secondaryText)
                    .lineLimit(1)
            }

            HStack {
                let projectCount = dataStore.projects(for: client).count
                Label("\(projectCount) project\(projectCount == 1 ? "" : "s")", systemImage: "building.2")
                    .font(.caption)
                    .foregroundColor(AppTheme.tertiaryText)
                Spacer()
            }
        }
        .padding(.vertical, 4)
    }

    // MARK: - Employee Row
    @ViewBuilder
    private func EmployeeRowView(employee: Employee) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(employee.fullName)
                    .font(.headline)
                    .foregroundColor(AppTheme.primaryText)
                    .lineLimit(1)
                Spacer()
                StatusBadge(
                    text: employee.status.displayName,
                    color: employee.isActive ? .green : .red
                )
            }

            HStack {
                Text(employee.employeeID)
                    .font(.caption)
                    .foregroundColor(AppTheme.tertiaryText)
                Text("  |  ")
                    .font(.caption)
                    .foregroundColor(AppTheme.tertiaryText)
                Text(employee.employeeType.displayName)
                    .font(.caption)
                    .foregroundColor(AppTheme.secondaryText)
                Spacer()
                Text(employee.defaultHourlyRate.currencyFormatted + "/hr")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppTheme.primaryOrange)
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
