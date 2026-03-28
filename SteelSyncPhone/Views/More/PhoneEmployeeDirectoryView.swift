import SwiftUI

struct PhoneEmployeeDirectoryView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var searchText = ""

    private var filteredEmployees: [Employee] {
        if searchText.isEmpty {
            return dataStore.employees
        }
        return dataStore.employees.filter {
            $0.fullName.localizedCaseInsensitiveContains(searchText) ||
            $0.employeeID.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        List {
            if filteredEmployees.isEmpty {
                Section {
                    VStack(spacing: AppTheme.Spacing.md) {
                        Image(systemName: "person.crop.rectangle.stack")
                            .font(.system(size: 40))
                            .foregroundColor(AppTheme.tertiaryText)
                        Text(searchText.isEmpty ? "No employees" : "No results")
                            .font(AppTheme.Typography.subheadline)
                            .foregroundColor(AppTheme.tertiaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, AppTheme.Spacing.xl)
                }
                .listRowBackground(AppTheme.secondaryBackground)
            } else {
                ForEach(filteredEmployees, id: \.id) { employee in
                    employeeRow(employee)
                        .listRowBackground(AppTheme.secondaryBackground)
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $searchText, prompt: "Search employees...")
        .navigationTitle("Directory")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Employee Row

    private func employeeRow(_ employee: Employee) -> some View {
        VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(employee.fullName)
                        .font(AppTheme.Typography.headline)
                        
                    Text(employee.employeeID)
                        .font(AppTheme.Typography.caption)
                        .foregroundColor(AppTheme.secondaryText)
                }
                Spacer()
                StatusBadge(
                    text: employee.employeeType.displayName,
                    color: badgeColor(for: employee.employeeType)
                )
            }

            HStack(spacing: AppTheme.Spacing.md) {
                if !employee.phone.isEmpty {
                    Link(destination: URL(string: "tel:\(employee.phone.filter { $0.isNumber })")!) {
                        Label("Call", systemImage: "phone.fill")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.success)
                    }
                }

                if !employee.email.isEmpty {
                    Link(destination: URL(string: "mailto:\(employee.email)")!) {
                        Label("Email", systemImage: "envelope.fill")
                            .font(AppTheme.Typography.caption)
                            .foregroundColor(AppTheme.info)
                    }
                }

                Spacer()
            }
        }
        .padding(.vertical, AppTheme.Spacing.xs)
    }

    private func badgeColor(for type: EmployeeType) -> Color {
        switch type {
        case .foreman: return AppTheme.primaryOrange
        case .w2: return AppTheme.info
        case .contractor: return AppTheme.warning
        }
    }
}
