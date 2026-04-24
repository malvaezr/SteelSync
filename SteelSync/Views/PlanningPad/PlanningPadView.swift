import SwiftUI

struct PlanningPadView: View {
    var body: some View {
        #if os(iOS)
        PlanningPadContent()
        #else
        VStack(spacing: AppTheme.Spacing.lg) {
            Image(systemName: "pencil.and.outline")
                .font(.system(size: 48))
                .foregroundColor(.secondary)
            Text("Planning Pad")
                .font(AppTheme.Typography.title2)
            Text("The Planning Pad with Apple Pencil support is available on iPad.")
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #endif
    }
}

#if os(iOS)
import PencilKit

struct PlanningPadContent: View {
    @EnvironmentObject var dataStore: DataStore
    @EnvironmentObject var navigationState: NavigationState
    @State private var textNotes = ""
    @State private var selectedDate = Date()
    @State private var showDatePicker = false
    @State private var drawing = PKDrawing()
    @State private var isToolPickerVisible = true
    @State private var isRecognizing = false
    @State private var recognizedText = ""
    @State private var isFullScreen = false
    @State private var showNotes = false

    private var dateLabel: String {
        if Calendar.current.isDateInToday(selectedDate) { return "Today" }
        if Calendar.current.isDateInTomorrow(selectedDate) { return "Tomorrow" }
        return selectedDate.shortDate
    }

    var body: some View {
        VStack(spacing: 0) {
            // Compact toolbar
            toolbar
            Divider()

            if isFullScreen {
                // Full screen: canvas only
                canvasArea
            } else {
                GeometryReader { geo in
                    VStack(spacing: 0) {
                        // Canvas takes most of the screen
                        canvasArea
                            .frame(height: showNotes ? geo.size.height * 0.7 : geo.size.height)

                        if showNotes {
                            Divider()
                            notesArea
                                .frame(height: geo.size.height * 0.3)
                        }
                    }
                }
            }
        }
        .onAppear { loadPad(for: selectedDate) }
        .onChange(of: selectedDate) { _, newDate in
            saveCurrent()
            loadPad(for: newDate)
        }
        .onDisappear { saveCurrent() }
    }

    // MARK: - Toolbar

    private var toolbar: some View {
        HStack(spacing: 12) {
            // Date navigation
            Button { shiftDate(by: -1) } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)

            Button { showDatePicker.toggle() } label: {
                HStack(spacing: 4) {
                    Image(systemName: "calendar")
                    Text(dateLabel).fontWeight(.semibold)
                }
                .font(.subheadline)
            }
            .buttonStyle(.borderless)
            .popover(isPresented: $showDatePicker) {
                DatePicker("", selection: $selectedDate, displayedComponents: .date)
                    .datePickerStyle(.graphical)
                    .padding()
                    .frame(width: 320, height: 360)
            }

            Button { shiftDate(by: 1) } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)

            Spacer()

            // Convert handwriting
            if isRecognizing {
                ProgressView().controlSize(.small)
                Text("Recognizing...").font(.caption).foregroundColor(.secondary)
            } else {
                Button { convertHandwriting() } label: {
                    Label("Convert", systemImage: "text.viewfinder").font(.caption)
                }
                .buttonStyle(.appSecondary)
                .controlSize(.small)
                .disabled(drawing.strokes.isEmpty)
            }

            // Clear canvas
            Button { drawing = PKDrawing() } label: {
                Image(systemName: "trash")
                    .font(.caption)
            }
            .buttonStyle(.appSecondary)
            .controlSize(.small)
            .tint(.red.opacity(0.8))
            .disabled(drawing.strokes.isEmpty)

            // Toggle notes panel
            Button {
                withAnimation(.easeInOut(duration: 0.2)) { showNotes.toggle() }
            } label: {
                Image(systemName: showNotes ? "note.text" : "note.text.badge.plus")
                    .font(.caption)
            }
            .buttonStyle(.appSecondary)
            .controlSize(.small)
            .tint(showNotes ? AppTheme.primaryOrange : .secondary)

            // Send to To-Do
            Button { sendToTodo() } label: {
                Image(systemName: "checklist")
                    .font(.caption)
            }
            .buttonStyle(.appSecondary)
            .controlSize(.small)

            // Full screen toggle
            Button {
                withAnimation(.easeInOut(duration: 0.25)) {
                    isFullScreen.toggle()
                    navigationState.columnVisibility = isFullScreen ? .detailOnly : .automatic
                }
            } label: {
                Image(systemName: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                    .font(.caption)
            }
            .buttonStyle(.appPrimary)
            .controlSize(.small)
            .tint(isFullScreen ? AppTheme.primaryOrange : .gray)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Canvas Area

    private var canvasArea: some View {
        PencilCanvasView(drawing: $drawing, isToolPickerVisible: $isToolPickerVisible)
            .background(Color.gray.opacity(0.06))
            .overlay(alignment: .topTrailing) {
                if isFullScreen {
                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            isFullScreen = false
                            navigationState.columnVisibility = .automatic
                        }
                    } label: {
                        Label("Exit Full Screen", systemImage: "arrow.down.right.and.arrow.up.left")
                            .font(.caption)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(.ultraThinMaterial)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .padding(12)
                }
            }
    }

    // MARK: - Notes Area

    private var notesArea: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Notes")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                Spacer()
                if !recognizedText.isEmpty {
                    Text("Last recognized: \(recognizedText.prefix(40))...")
                        .font(.caption2)
                        .foregroundColor(AppTheme.primaryOrange)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 4)

            TextEditor(text: $textNotes)
                .font(.callout)
                .padding(.horizontal, 6)
                .scrollContentBackground(.hidden)
        }
    }

    // MARK: - Actions

    private func shiftDate(by days: Int) {
        selectedDate = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) ?? selectedDate
    }

    /// List-item prefixes: -, •, *, o, >, numbered (1. 2) 3), checkboxes [ ], etc.
    private static let listPrefixPattern = #"^[\s]*([-–—•*>o]|\d+[.)]\s*|\[[ x]\])\s*"#

    private func sendToTodo() {
        let allText = [textNotes, recognizedText].joined(separator: "\n")
        let regex = try? NSRegularExpression(pattern: Self.listPrefixPattern, options: [.caseInsensitive])

        let items = allText.components(separatedBy: .newlines)
            .filter { line in
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard !trimmed.isEmpty else { return false }
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                return regex?.firstMatch(in: trimmed, range: range) != nil
            }
            .map { line -> String in
                // Strip the bullet/number prefix to get clean todo title
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                guard let regex else { return trimmed }
                let range = NSRange(trimmed.startIndex..., in: trimmed)
                return regex.stringByReplacingMatches(in: trimmed, range: range, withTemplate: "")
                    .trimmingCharacters(in: .whitespaces)
            }
            .filter { !$0.isEmpty }
            .prefix(50)

        guard !items.isEmpty else { return }

        for item in items {
            let todo = TodoItem(title: item, dueDate: selectedDate, category: .general)
            dataStore.addTodo(todo)
        }
        textNotes = ""
        recognizedText = ""
    }

    private func convertHandwriting() {
        guard !drawing.strokes.isEmpty else { return }
        isRecognizing = true

        Task {
            let result = await HandwritingRecognitionService.recognizeText(from: drawing)
            await MainActor.run {
                if !result.isEmpty {
                    if textNotes.isEmpty {
                        textNotes = result
                    } else {
                        textNotes += "\n" + result
                    }
                    recognizedText = result
                }
                isRecognizing = false
            }
        }
    }

    // MARK: - Persistence

    private func loadPad(for date: Date) {
        if let pad = dataStore.planningPad(for: date) {
            textNotes = pad.textNotes
            recognizedText = pad.recognizedText
            if let data = pad.loadDrawingData() {
                drawing = (try? PKDrawing(data: data)) ?? PKDrawing()
            } else {
                drawing = PKDrawing()
            }
        } else {
            textNotes = ""
            recognizedText = ""
            drawing = PKDrawing()
        }
    }

    private func saveCurrent() {
        // Only save if there's actual content
        guard !textNotes.isEmpty || !drawing.strokes.isEmpty else { return }

        var pad = dataStore.planningPad(for: selectedDate) ?? PlanningPad(date: selectedDate)
        pad.textNotes = textNotes
        pad.recognizedText = recognizedText
        pad.lastModifiedDate = Date()

        if !drawing.strokes.isEmpty {
            pad.saveDrawingData(drawing.dataRepresentation())
        }

        dataStore.savePlanningPad(pad)
    }
}
#endif
