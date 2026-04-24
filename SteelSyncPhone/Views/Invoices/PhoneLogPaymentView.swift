import SwiftUI
import PhotosUI
import CloudKit

/// Mobile-optimized payment logging against a specific invoice. Uses PhotosPicker
/// for check image capture (library + stills only — no live camera per user spec).
/// Enforces the same proof-OR-reason save gate as the Mac LogPaymentSheet.
struct PhoneLogPaymentView: View {
    let invoice: Invoice
    let projectID: CKRecord.ID

    @EnvironmentObject var dataStore: DataStore
    @Environment(\.dismiss) var dismiss

    @State private var amount: Decimal = 0
    @State private var date = Date()
    @State private var method: PaymentMethod = .check
    @State private var referenceNumber = ""
    @State private var notes = ""
    @State private var proofReason = ""
    @State private var attachments: [Attachment] = []
    @State private var selectedPhoto: PhotosPickerItem?

    private var balanceDue: Decimal {
        dataStore.balanceRemaining(for: invoice)
    }

    private var hasProofOrReason: Bool {
        !attachments.isEmpty || !proofReason.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var canSave: Bool {
        amount > 0 && hasProofOrReason
    }

    var body: some View {
        Form {
            Section("Invoice") {
                InfoRow(label: "Number", value: invoice.invoiceNumber)
                InfoRow(label: "Balance Due", value: balanceDue.currencyFormatted)
            }

            Section("Payment") {
                HStack {
                    Text("Amount")
                    Spacer()
                    TextField("0", value: $amount, format: .currency(code: "USD"))
                        .multilineTextAlignment(.trailing)
                        .keyboardType(.decimalPad)
                }
                DatePicker("Received", selection: $date, displayedComponents: .date)
                Picker("Method", selection: $method) {
                    ForEach(PaymentMethod.allCases) { m in
                        Label(m.rawValue, systemImage: m.icon).tag(m)
                    }
                }
                TextField("Check #, wire confirmation, ACH ref", text: $referenceNumber)
            }

            Section {
                if attachments.isEmpty {
                    // PhotosPicker button for library photos + PDFs
                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        HStack {
                            Image(systemName: "photo.on.rectangle.angled")
                            Text("Attach Check Photo")
                        }
                    }

                    TextField(
                        "",
                        text: $proofReason,
                        prompt: Text("Or reason for no proof (required if no photo)"),
                        axis: .vertical
                    )
                    .lineLimit(2...5)
                } else {
                    ForEach(attachments, id: \.id) { att in
                        HStack {
                            Image(systemName: "doc.fill")
                                .foregroundColor(.green)
                            Text(att.filename)
                                .font(.callout)
                                .lineLimit(1)
                            Spacer()
                            Button(role: .destructive) {
                                attachments.removeAll { $0.id == att.id }
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    PhotosPicker(
                        selection: $selectedPhoto,
                        matching: .images,
                        photoLibrary: .shared()
                    ) {
                        Label("Add Another Photo", systemImage: "plus")
                    }
                }
            } header: {
                Text("Proof of Payment")
            } footer: {
                if !hasProofOrReason {
                    Text("⚠️ Attach a check photo or type a reason to save.")
                        .foregroundColor(.orange)
                }
            }

            Section("Notes") {
                TextField("", text: $notes, prompt: Text("Optional notes"), axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .navigationTitle("Log Payment")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .fontWeight(.semibold)
                    .disabled(!canSave)
            }
        }
        .onAppear {
            if amount == 0 { amount = balanceDue }
        }
        .onChange(of: selectedPhoto) { _, newValue in
            guard let newValue else { return }
            Task { await handlePhotoPick(newValue) }
        }
    }

    // MARK: - Photo handling

    /// Loads the picked photo's data and writes it into the shared file storage,
    /// then adds the resulting Attachment to the list. This uses the same
    /// FileStorageService flow as the Mac drag-and-drop.
    private func handlePhotoPick(_ item: PhotosPickerItem) async {
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            selectedPhoto = nil
            return
        }
        let tmpURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("check-\(UUID().uuidString).jpg")
        do {
            try data.write(to: tmpURL)
            let folderID = "payment-\(invoice.id.uuidString)"
            switch FileStorageService.importFile(from: tmpURL, bidID: folderID) {
            case .success(let attachment):
                await MainActor.run {
                    attachments.append(attachment)
                    selectedPhoto = nil
                }
            case .failure:
                await MainActor.run { selectedPhoto = nil }
            }
            try? FileManager.default.removeItem(at: tmpURL)
        } catch {
            await MainActor.run { selectedPhoto = nil }
        }
    }

    private func save() {
        var payment = Payment(
            amount: amount,
            date: date,
            appliedToInvoiceID: invoice.id,
            paymentMethod: method,
            referenceNumber: referenceNumber,
            proofReason: proofReason,
            notes: notes,
            attachments: attachments
        )
        payment.projectRef = CKRecord.Reference(recordID: projectID, action: .deleteSelf)
        dataStore.addPayment(payment, to: projectID)
        dataStore.refreshInvoiceStatus(invoice, in: projectID)
        dismiss()
    }
}
