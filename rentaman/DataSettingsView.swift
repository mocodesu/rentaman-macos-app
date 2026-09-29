import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct DataSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var properties: [Property]
    @Query private var bills: [Bill]
    
    @State private var isShowingResetConfirm = false
    @State private var exportStatus: ExportStatus = .idle
    
    enum ExportStatus {
        case idle
        case exporting
        case success(URL)
        case failure(String)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Data")
                        .font(.system(size: 24, weight: .bold))
                    Text("Manage your local data and backups.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                
                // Stats
                SettingsSection(title: "Database", subtitle: "Summary of stored records on this device.") {
                    HStack(spacing: 0) {
                        StatBlock(icon: "house.fill", color: .blue, value: "\(properties.count)", label: "Properties")
                        Divider().frame(height: 50)
                        StatBlock(icon: "doc.text.fill", color: .green, value: "\(bills.count)", label: "Bills")
                        Divider().frame(height: 50)
                        StatBlock(icon: "banknote.fill", color: .orange, value: "\(bills.filter { $0.isPaid }.count)", label: "Paid")
                        Divider().frame(height: 50)
                        StatBlock(icon: "clock.fill", color: .red, value: "\(bills.filter { !$0.isPaid }.count)", label: "Unpaid")
                    }
                }
                
                // Backup
                SettingsSection(title: "Backup & Restore", subtitle: "Export your data as JSON to keep a backup or move to another Mac.") {
                    VStack(spacing: 12) {
                        SettingsRow(
                            icon: "square.and.arrow.up.fill",
                            iconColor: .blue,
                            title: "Export Data",
                            subtitle: "Save a JSON file with all properties and bills."
                        ) {
                            Button("Export") {
                                exportData()
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Divider().padding(.leading, 40).padding(.vertical, 4)
                        
                        SettingsRow(
                            icon: "square.and.arrow.down.fill",
                            iconColor: .green,
                            title: "Import Data",
                            subtitle: "Restore from a previously exported JSON file."
                        ) {
                            Button("Import") {
                                // Import is a future feature
                            }
                            .buttonStyle(.bordered)
                            .disabled(true)
                            .help("Coming in a future update")
                        }
                    }
                }
                
                // Danger zone
                SettingsSection(title: "Reset", subtitle: "Erase data on this device. Data synced to the cloud is not affected.") {
                    SettingsRow(
                        icon: "trash.fill",
                        iconColor: .red,
                        title: "Reset All Local Data",
                        subtitle: "Permanently remove all properties and bills from this Mac."
                    ) {
                        Button("Reset…") {
                            isShowingResetConfirm = true
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                    }
                }
                
                // Export status
                if case .success(let url) = exportStatus {
                    HStack(spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Export successful")
                                .font(.system(size: 12, weight: .semibold))
                            Text(url.path)
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button("Reveal in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        }
                        .buttonStyle(.borderless)
                    }
                    .padding(12)
                    .background(Color.green.opacity(0.08))
                    .cornerRadius(10)
                } else if case .failure(let msg) = exportStatus {
                    HStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                        Text(msg)
                            .font(.system(size: 12))
                        Spacer()
                    }
                    .padding(12)
                    .background(Color.red.opacity(0.08))
                    .cornerRadius(10)
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .alert("Reset all local data?", isPresented: $isShowingResetConfirm) {
            Button("Reset", role: .destructive) {
                resetAllData()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently remove **\(properties.count) propert\(properties.count == 1 ? "y" : "ies")** and **\(bills.count) bill\(bills.count == 1 ? "" : "s")** from this Mac. Data synced to the cloud will remain and can be re-downloaded on next launch.")
        }
    }
    
    private func exportData() {
        exportStatus = .exporting
        do {
            let export = RentaManExport(properties: properties, bills: bills)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(export)
            
            let fileName = "RentaMan_Backup_\(Date().formatted(date: .numeric, time: .omitted).replacingOccurrences(of: "/", with: "-")).json"
            let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
            try data.write(to: tempURL)
            
            // Present save panel
            let panel = NSSavePanel()
            panel.nameFieldStringValue = fileName
            panel.allowedContentTypes = [.json]
            panel.canCreateDirectories = true
            
            if panel.runModal() == .OK, let url = panel.url {
                try data.write(to: url)
                exportStatus = .success(url)
            } else {
                exportStatus = .idle
            }
        } catch {
            exportStatus = .failure("Export failed: \(error.localizedDescription)")
        }
    }
    
    private func resetAllData() {
        for bill in bills { modelContext.delete(bill) }
        for property in properties { modelContext.delete(property) }
        try? modelContext.save()
        exportStatus = .idle
    }
}

// MARK: - Stat Block
struct StatBlock: View {
    let icon: String
    let color: Color
    let value: String
    let label: String
    
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(color)
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Export Model
struct RentaManExport: Codable {
    let version: String
    let exportedAt: Date
    let properties: [ExportedProperty]
    let bills: [ExportedBill]
    
    init(properties: [Property], bills: [Bill]) {
        self.version = "1.0"
        self.exportedAt = Date()
        self.properties = properties.map {
            ExportedProperty(
                id: $0.id, name: $0.name, address: $0.address,
                colorHex: $0.colorHex, monthlyBudget: $0.monthlyBudget,
                isDefault: $0.isDefault, createdAt: $0.createdAt
            )
        }
        self.bills = bills.map {
            ExportedBill(
                id: $0.id, title: $0.title, amount: $0.amount,
                category: $0.categoryRawValue, dueDate: $0.dueDate,
                isPaid: $0.isPaid, paymentDate: $0.paymentDate,
                notes: $0.notes, isRecurring: $0.isRecurring,
                recurringFrequency: $0.recurringFrequencyRaw,
                propertyId: $0.property?.id
            )
        }
    }
}

struct ExportedProperty: Codable {
    let id: String
    let name: String
    let address: String?
    let colorHex: String
    let monthlyBudget: Double
    let isDefault: Bool
    let createdAt: Date
}

struct ExportedBill: Codable {
    let id: String
    let title: String
    let amount: Double
    let category: String
    let dueDate: Date
    let isPaid: Bool
    let paymentDate: Date?
    let notes: String?
    let isRecurring: Bool
    let recurringFrequency: String
    let propertyId: String?
}