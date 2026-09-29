import SwiftUI
import SwiftData

struct EditPropertyView: View {
    let property: Property
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    
    @State private var name: String = ""
    @State private var address: String = ""
    @State private var budgetString: String = ""
    @State private var colorHex: String = "#3B82F6"
    
    private let colorOptions: [String] = [
        "#3B82F6", "#8B5CF6", "#EC4899", "#EF4444",
        "#F59E0B", "#10B981", "#14B8A6", "#6366F1"
    ]
    
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "square.and.pencil")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Edit Property")
                    .font(.title2)
                    .fontWeight(.bold)
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            
            Divider()
            
            Form {
                Section {
                    HStack {
                        Image(systemName: "textformat")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        TextField("Name", text: $name)
                    }
                    
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        TextField("Address (optional)", text: $address)
                    }
                    
                    HStack {
                        Image(systemName: "banknote")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Monthly Budget")
                        Spacer()
                        TextField("0.00", text: $budgetString)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 150)
                            .onChange(of: budgetString) { _, newValue in
                                let filtered = newValue.filter { "0123456789.".contains($0) }
                                if filtered != newValue { budgetString = filtered }
                            }
                    }
                    
                    HStack(alignment: .top) {
                        Image(systemName: "paintpalette")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Color Tag")
                            HStack(spacing: 10) {
                                ForEach(colorOptions, id: \.self) { hex in
                                    Button {
                                        withAnimation(.spring(response: 0.4, dampingFraction: 0.75)) {
                                            colorHex = hex
                                        }
                                    } label: {
                                        Circle()
                                            .fill(Color(hex: hex))
                                            .frame(width: 24, height: 24)
                                            .overlay(
                                                Circle()
                                                    .stroke(Color.white, lineWidth: 2)
                                                    .padding(2)
                                                    .opacity(colorHex == hex ? 1 : 0)
                                            )
                                            .overlay(
                                                Circle()
                                                    .stroke(Color(hex: hex).opacity(0.3), lineWidth: 2.5)
                                                    .scaleEffect(colorHex == hex ? 1.35 : 1.0)
                                                    .opacity(colorHex == hex ? 1 : 0)
                                            )
                                            .scaleEffect(colorHex == hex ? 1.1 : 1.0)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                
                Button {
                    save()
                } label: {
                    Label("Save Changes", systemImage: "checkmark.circle.fill")
                        .frame(minWidth: 130)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
        }
        .frame(width: 520, height: 500)
        .onAppear {
            name = property.name
            address = property.address ?? ""
            budgetString = property.monthlyBudget > 0
                ? String(format: "%.2f", property.monthlyBudget)
                : ""
            colorHex = property.colorHex
        }
    }
    
    private func save() {
        property.name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        property.address = address.isEmpty ? nil : address
        property.monthlyBudget = Double(budgetString) ?? 0
        property.colorHex = colorHex
        property.syncStatus = .pendingUpload
        property.updatedAt = Date()
        
        try? modelContext.save()
        SyncService.shared.schedulePush()
        dismiss()
    }
}