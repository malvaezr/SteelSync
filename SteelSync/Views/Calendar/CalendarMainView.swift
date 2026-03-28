import SwiftUI

struct CalendarMainView: View {
    @EnvironmentObject var dataStore: DataStore
    @State private var selectedDate = Date()
    @State private var viewMode = "Month"
    @State private var showAddEvent = false

    private let viewModes = ["Month", "Agenda"]

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Picker("View", selection: $viewMode) {
                    ForEach(viewModes, id: \.self) { Text($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 200)

                Spacer()

                HStack(spacing: AppTheme.Spacing.sm) {
                    Button(action: { selectedDate = Calendar.current.date(byAdding: .month, value: -1, to: selectedDate) ?? selectedDate }) {
                        Image(systemName: "chevron.left")
                    }
                    Button("Today") { selectedDate = Date() }
                        .buttonStyle(.bordered)
                    Button(action: { selectedDate = Calendar.current.date(byAdding: .month, value: 1, to: selectedDate) ?? selectedDate }) {
                        Image(systemName: "chevron.right")
                    }
                }

                Text(selectedDate.formatted("MMMM yyyy"))
                    .font(AppTheme.Typography.title3)
                    .frame(width: 180, alignment: .trailing)
            }
            .padding(AppTheme.Spacing.md)
            .background(AppTheme.secondaryBackground)

            Divider()

            if viewMode == "Month" {
                monthView
            } else {
                agendaView
            }
        }
        .sheet(isPresented: $showAddEvent) {
            AddEventView()
        }
        .navigationTitle("Calendar")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: { showAddEvent = true }) {
                    Label("New Event", systemImage: "plus")
                }
            }
        }
    }

    // MARK: - Month View
    private var monthView: some View {
        VStack(spacing: 0) {
            // Day headers
            HStack(spacing: 0) {
                ForEach(["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], id: \.self) { day in
                    Text(day)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
            }
            .background(AppTheme.secondaryBackground)

            Divider()

            // Calendar grid
            let days = daysInMonth()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(days, id: \.self) { date in
                    CalendarDayCell(date: date, selectedDate: $selectedDate,
                                    events: dataStore.events(for: date),
                                    isCurrentMonth: Calendar.current.isDate(date, equalTo: selectedDate, toGranularity: .month))
                }
            }

            Divider()

            // Selected day events
            VStack(alignment: .leading, spacing: AppTheme.Spacing.sm) {
                Text("Events for \(selectedDate.shortDate)")
                    .font(AppTheme.Typography.headline)
                    .padding(.horizontal)
                    .padding(.top, AppTheme.Spacing.sm)

                let dayEvents = dataStore.events(for: selectedDate)
                if dayEvents.isEmpty {
                    Text("No events scheduled.")
                        .foregroundColor(.secondary)
                        .padding(.horizontal)
                } else {
                    ForEach(dayEvents) { event in
                        EventRow(event: event)
                            .padding(.horizontal)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, AppTheme.Spacing.md)
        }
    }

    // MARK: - Agenda View
    private var agendaView: some View {
        List {
            let sorted = dataStore.calendarEvents.sorted { $0.startDate < $1.startDate }
            let upcoming = sorted.filter { $0.startDate >= Calendar.current.startOfDay(for: Date()) }
            let past = sorted.filter { $0.startDate < Calendar.current.startOfDay(for: Date()) }

            if !upcoming.isEmpty {
                Section("Upcoming") {
                    ForEach(upcoming) { event in
                        EventRow(event: event)
                            .contextMenu {
                                Button("Delete", role: .destructive) { dataStore.deleteEvent(event) }
                            }
                    }
                }
            }

            if !past.isEmpty {
                Section("Past") {
                    ForEach(past.reversed()) { event in
                        EventRow(event: event)
                            .opacity(0.6)
                    }
                }
            }
        }
        #if os(macOS)
        .listStyle(.inset(alternatesRowBackgrounds: true))
        #else
        .listStyle(.insetGrouped)
        #endif
    }

    // MARK: - Helpers
    private func daysInMonth() -> [Date] {
        let calendar = Calendar.current
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: selectedDate))!
        let weekday = calendar.component(.weekday, from: monthStart)
        let startDate = calendar.date(byAdding: .day, value: -(weekday - 1), to: monthStart)!
        return (0..<42).compactMap { calendar.date(byAdding: .day, value: $0, to: startDate) }
    }
}

// MARK: - Calendar Day Cell
struct CalendarDayCell: View {
    let date: Date
    @Binding var selectedDate: Date
    let events: [CalendarEvent]
    let isCurrentMonth: Bool

    var isSelected: Bool { Calendar.current.isDate(date, inSameDayAs: selectedDate) }
    var isToday: Bool { Calendar.current.isDateInToday(date) }

    var body: some View {
        VStack(spacing: 2) {
            Text("\(Calendar.current.component(.day, from: date))")
                .font(.callout)
                .fontWeight(isToday ? .bold : .regular)
                .foregroundColor(isCurrentMonth ? (isToday ? AppTheme.primaryOrange : AppTheme.primaryText) : AppTheme.tertiaryText)

            HStack(spacing: 2) {
                ForEach(events.prefix(3)) { event in
                    Circle()
                        .fill(eventColor(event.type))
                        .frame(width: 5, height: 5)
                }
            }
            .frame(height: 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(isSelected ? AppTheme.primaryOrange.opacity(0.1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onTapGesture { selectedDate = date }
    }

    private func eventColor(_ type: CalendarEvent.EventType) -> Color {
        switch type {
        case .milestone: return .blue
        case .meeting: return .green
        case .inspection: return .orange
        case .delivery: return .purple
        case .deadline: return .red
        case .other: return .gray
        }
    }
}

// MARK: - Event Row
struct EventRow: View {
    let event: CalendarEvent

    var body: some View {
        HStack(spacing: AppTheme.Spacing.sm) {
            Image(systemName: event.type.icon)
                .foregroundColor(eventColor)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).fontWeight(.medium)
                HStack {
                    Text(event.startDate.formatted("MMM d, h:mm a"))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if !event.description.isEmpty {
                        Text("- \(event.description)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            Spacer()
            StatusBadge(text: event.type.rawValue, color: eventColor)
        }
        .padding(.vertical, 4)
    }

    private var eventColor: Color {
        switch event.type {
        case .milestone: return .blue
        case .meeting: return .green
        case .inspection: return .orange
        case .delivery: return .purple
        case .deadline: return .red
        case .other: return .gray
        }
    }
}

// MARK: - Add Event
struct AddEventView: View {
    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) private var dismiss

    @State private var title = ""
    @State private var description = ""
    @State private var startDate = Date()
    @State private var endDate = Date().addingTimeInterval(3600)
    @State private var type: CalendarEvent.EventType = .other
    @State private var isAllDay = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("New Event").font(AppTheme.Typography.title2)
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(title.isEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(AppTheme.primaryOrange)
            }
            .padding()
            Divider()
            Form {
                TextField("Title", text: $title)
                TextField("Description", text: $description)
                Picker("Type", selection: $type) {
                    ForEach(CalendarEvent.EventType.allCases, id: \.self) {
                        Label($0.rawValue, systemImage: $0.icon).tag($0)
                    }
                }
                Toggle("All Day", isOn: $isAllDay)
                DatePicker("Start", selection: $startDate, displayedComponents: isAllDay ? .date : [.date, .hourAndMinute])
                if !isAllDay {
                    DatePicker("End", selection: $endDate, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .formStyle(.grouped)
        }
        #if os(macOS)
        .frame(width: 450, height: 400)
        #endif
    }

    private func save() {
        let event = CalendarEvent(title: title, description: description,
                                   startDate: startDate, endDate: isAllDay ? startDate : endDate,
                                   type: type, isAllDay: isAllDay)
        dataStore.addEvent(event)
        dismiss()
    }
}
