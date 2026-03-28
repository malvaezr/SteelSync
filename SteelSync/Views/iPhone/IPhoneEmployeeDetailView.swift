#if STEELSYNC_IPHONE
import SwiftUI

struct IPhoneEmployeeDetailView: View {
    let employee: Employee

    var body: some View {
        List {
            // MARK: - Identity
            Section("Identity") {
                InfoRow(label: "Name", value: employee.fullName, icon: "person.fill")
                InfoRow(label: "Employee ID", value: employee.employeeID, icon: "number")
                InfoRow(label: "Type", value: employee.employeeType.displayName, icon: "briefcase.fill")
                InfoRow(
                    label: "Status",
                    value: employee.status.displayName,
                    icon: employee.isActive ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
            }

            // MARK: - Compensation
            Section("Compensation") {
                InfoRow(label: "Hourly Rate", value: employee.defaultHourlyRate.currencyFormatted + "/hr", icon: "dollarsign.circle")
            }

            // MARK: - Contact
            if !employee.email.isEmpty || !employee.phone.isEmpty {
                Section("Contact") {
                    if !employee.email.isEmpty {
                        InfoRow(label: "Email", value: employee.email, icon: "envelope.fill")
                    }
                    if !employee.phone.isEmpty {
                        InfoRow(label: "Phone", value: employee.phone, icon: "phone.fill")
                    }
                }
            }

            // MARK: - Notes
            if !employee.notes.isEmpty {
                Section("Notes") {
                    Text(employee.notes)
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.secondaryText)
                }
            }

            // MARK: - Dates
            Section("Dates") {
                InfoRow(label: "Created", value: employee.createdDate.shortDate, icon: "calendar.badge.plus")
                InfoRow(label: "Updated", value: employee.updatedDate.shortDate, icon: "calendar.badge.clock")
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(employee.fullName)
        .navigationBarTitleDisplayMode(.large)
    }
}
#endif
