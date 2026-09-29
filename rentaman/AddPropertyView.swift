import SwiftUI
import SwiftData

struct AddPropertyView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query private var allProperties: [Property]
    
    @State private var viewModel = AddPropertyViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: "house.badge.plus")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text("Add New Property")
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
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()
            
            // Form
            Form {
                Section {
                    HStack {
                        Image(systemName: "textformat")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        TextField("Name (e.g., Main House, Rental A)", text: $viewModel.name)
                    }
                    
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        TextField("Address (Optional)", text: $viewModel.address)
                    }
                    
                    HStack {
                        Image(systemName: "banknote")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Monthly Budget")
                        Spacer()
                        TextField("0.00", text: $viewModel.monthlyBudgetString)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 160)
                            .onChange(of: viewModel.monthlyBudgetString) { _, newValue in
                                let filtered = newValue.filter { "0123456789.".contains($0) }
                                if filtered != newValue { viewModel.monthlyBudgetString = filtered }
                            }
                    }
                    
                    HStack {
                        Image(systemName: "paintpalette")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        ColorPicker("Color Tag", selection: Binding(
                            get: { Color(hex: viewModel.colorHex) },
                            set: { viewModel.colorHex = $0.toHex() ?? "#007AFF" }
                        ))
                    }
                } header: {
                    Text("Property Details")
                }
                
                Section {
                    Toggle(isOn: $viewModel.isDefault) {
                        HStack {
                            Image(systemName: "star.fill")
                                .foregroundStyle(.yellow)
                            Text("Set as Default Property")
                        }
                    }
                    .toggleStyle(.switch)
                    
                    Text("The default property will be pre-selected when adding new bills.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } header: {
                    Text("Default Selection")
                }
                
                if let errorMessage = viewModel.validationErrorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.red)
                            Text(errorMessage)
                                .foregroundStyle(.red)
                                .font(.caption)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button {
                    if viewModel.save(context: modelContext, allProperties: allProperties) {
                        dismiss()
                    }
                } label: {
                    Label("Save Property", systemImage: "checkmark.circle.fill")
                        .frame(minWidth: 140)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.isValid)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))
        }
        .frame(width: 540, height: 580)
        .onDisappear { viewModel.reset() }
    }
}

// Helper extension to convert Color back to Hex string
extension Color {
    func toHex() -> String? {
        guard let components = NSColor(self).cgColor.components, components.count >= 3 else { return nil }
        let r = Float(components[0])
        let g = Float(components[1])
        let b = Float(components[2])
        return String(format: "#%02lX%02lX%02lX", lroundf(r * 255), lroundf(g * 255), lroundf(b * 255))
    }
}
