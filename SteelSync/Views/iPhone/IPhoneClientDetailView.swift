#if STEELSYNC_IPHONE
import SwiftUI

struct IPhoneClientDetailView: View {
    @EnvironmentObject var dataStore: DataStore
    let client: Client

    private var linkedProjects: [Project] {
        dataStore.projects(for: client)
    }

    var body: some View {
        List {
            // MARK: - Contact Info
            Section("Contact") {
                InfoRow(label: "Name", value: client.name, icon: "building.2")

                if !client.contactName.isEmpty {
                    InfoRow(label: "Contact", value: client.contactName, icon: "person.fill")
                }

                if !client.email.isEmpty {
                    Link(destination: URL(string: "mailto:\(client.email)")!) {
                        HStack {
                            Image(systemName: "envelope.fill")
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            Text("Email")
                                .foregroundColor(AppTheme.secondaryText)
                            Spacer()
                            Text(client.email)
                                .foregroundColor(AppTheme.primaryOrange)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(1)
                        }
                    }
                }

                if !client.phone.isEmpty {
                    Link(destination: URL(string: "tel:\(client.phone.filter { $0.isNumber || $0 == "+" })")!) {
                        HStack {
                            Image(systemName: "phone.fill")
                                .foregroundColor(.secondary)
                                .frame(width: 20)
                            Text("Phone")
                                .foregroundColor(AppTheme.secondaryText)
                            Spacer()
                            Text(client.phone)
                                .foregroundColor(AppTheme.primaryOrange)
                        }
                    }
                }

                if !client.billingAddress.isEmpty {
                    InfoRow(label: "Address", value: client.billingAddress, icon: "mappin.and.ellipse")
                }

                InfoRow(
                    label: "Rate Type",
                    value: client.preferredRateType.displayName,
                    icon: client.preferredRateType == .generalContractor ? "star.fill" : "wrench.fill"
                )
            }

            // MARK: - Linked Projects
            Section("Projects (\(linkedProjects.count))") {
                if linkedProjects.isEmpty {
                    Text("No linked projects")
                        .font(AppTheme.Typography.body)
                        .foregroundColor(AppTheme.tertiaryText)
                } else {
                    ForEach(linkedProjects) { project in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(project.title)
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .lineLimit(1)
                                Text(project.contractAmount.currencyFormatted)
                                    .font(.caption)
                                    .foregroundColor(AppTheme.secondaryText)
                            }
                            Spacer()
                            StatusBadge(
                                text: project.computedStatus,
                                color: statusColor(for: project.computedStatus)
                            )
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(client.name)
        .navigationBarTitleDisplayMode(.large)
    }

    private func statusColor(for status: String) -> Color {
        switch status {
        case "Active": return AppTheme.ProjectStatus.active
        case "Upcoming": return AppTheme.ProjectStatus.upcoming
        case "Completed": return AppTheme.ProjectStatus.completed
        default: return AppTheme.ProjectStatus.onHold
        }
    }
}
#endif
