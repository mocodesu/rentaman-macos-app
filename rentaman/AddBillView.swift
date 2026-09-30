import SwiftUI
import SwiftData

struct AddBillView: View {
    var billToEdit: Bill? = nil
    var preSelectedPropertyId: String? = nil
    
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCurrency) private var appCurrency: AppCurrency
    
    @Query private var properties: [Property]
    @Query private var allBills: [Bill]
    
    @State private var viewModel = AddBillViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            
            // MARK: - Header
            HStack {
                Image(systemName: viewModel.isEditMode ? "square.and.pencil" : "plus.rectangle.on.folder.fill")
                    .font(.title2)
                    .foregroundStyle(.blue)
                Text(viewModel.isEditMode ? "Edit Bill" : "Add New Bill")
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
            
            // MARK: - Form
            Form {
                Section {
                    HStack {
                        Image(systemName: "textformat")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        TextField("Title (e.g., KPLC Electricity)", text: $viewModel.title)
                    }
                    
                    HStack {
                        Image(systemName: "tag")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Picker("Category", selection: $viewModel.selectedCategory) {
                            ForEach(ExpenseCategory.allCases) { category in
                                Label(category.rawValue, systemImage: category.iconName)
                                    .tag(category)
                            }
                        }
                        .onChange(of: viewModel.selectedCategory) { _, _ in
                            viewModel.prefillFromHistory(bills: allBills, properties: properties)
                        }
                    }
                    
                    HStack {
                        Image(systemName: "house")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Picker("Property", selection: $viewModel.selectedPropertyId) {
                            Text("Select a property...").tag(nil as String?)
                            ForEach(properties) { property in
                                HStack {
                                    Text(property.name)
                                    if property.isDefault {
                                        Image(systemName: "star.fill")
                                    }
                                }
                                .tag(property.id as String?)
                            }
                        }
                        .onChange(of: viewModel.selectedPropertyId) { _, _ in
                            viewModel.prefillFromHistory(bills: allBills, properties: properties)
                        }
                    }
                } header: {
                    Label("Bill Information", systemImage: "doc.text")
                }
                
                Section {
                    HStack {
                        Image(systemName: "dollarsign.circle")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Picker("Currency", selection: $viewModel.entryCurrency) {
                            ForEach(AppCurrency.allCases) { curr in
                                Text("\(curr.symbol) \(curr.rawValue)").tag(curr)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                    
                    HStack {
                        Image(systemName: "banknote")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        Text("Amount")
                        Spacer()
                        TextField("0.00", text: $viewModel.amountString)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 160)
                            .onChange(of: viewModel.amountString) { _, newValue in
                                let filtered = newValue.filter { "0123456789.".contains($0) }
                                if filtered != newValue { viewModel.amountString = filtered }
                            }
                    }
                } header: {
                    Label("Amount & Currency", systemImage: "banknote.fill")
                }
                
                Section {
                    Toggle(isOn: $viewModel.isPaid) {
                        HStack {
                            Image(systemName: viewModel.isPaid ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(viewModel.isPaid ? .green : .secondary)
                            Text("Already Paid")
                        }
                    }
                    .toggleStyle(.switch)
                    
                    HStack {
                        Image(systemName: "calendar")
                            .foregroundStyle(.secondary)
                            .frame(width: 20)
                        DatePicker("Due Date", selection: $viewModel.dueDate, displayedComponents: .date)
                    }
                    
                    if viewModel.isPaid {
                        HStack {
                            Image(systemName: "calendar.badge.checkmark")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            DatePicker("Payment Date", selection: $viewModel.paymentDate, displayedComponents: .date)
                        }
                        
                        HStack {
                            Image(systemName: viewModel.paymentMethod.iconName)
                                .foregroundStyle(viewModel.paymentMethod.color)
                                .frame(width: 20)
                            Picker("Payment Method", selection: $viewModel.paymentMethod) {
                                ForEach(PaymentMethod.allCases) { method in
                                    Label(method.displayName, systemImage: method.iconName)
                                        .tag(method)
                                }
                            }
                        }
                    }
                } header: {
                    Label("Payment Status", systemImage: "calendar.badge.clock")
                }
                
                Section {
                    Toggle(isOn: $viewModel.isRecurring) {
                        HStack {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .foregroundStyle(viewModel.isRecurring ? .blue : .secondary)
                            Text("Recurring Bill")
                        }
                    }
                    .toggleStyle(.switch)
                    
                    if viewModel.isRecurring {
                        HStack {
                            Image(systemName: "repeat")
                                .foregroundStyle(.secondary)
                                .frame(width: 20)
                            Picker("Frequency", selection: $viewModel.recurringFrequency) {
                                ForEach(RecurringFrequency.allCases.filter { $0 != .none }) { freq in
                                    Label(freq.rawValue, systemImage: freq.iconName)
                                        .tag(freq)
                                }
                            }
                        }
                    }
                } header: {
                    Label("Recurring", systemImage: "arrow.triangle.2.circlepath.circle")
                }
                
                Section {
                    TextEditor(text: $viewModel.notes)
                        .frame(height: 70)
                        .font(.body)
                        .padding(4)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                } header: {
                    Label("Notes", systemImage: "note.text")
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
            
            // MARK: - Footer
            HStack {
                Spacer()
                Button {
                    if viewModel.save(context: modelContext, properties: properties) {
                        dismiss()
                    }
                } label: {
                    Label(viewModel.isEditMode ? "Update Bill" : "Save Bill",
                          systemImage: viewModel.isEditMode ? "checkmark.seal.fill" : "checkmark.circle.fill")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!viewModel.isValid)
                .keyboardShortcut(.defaultAction)
            }
            .padding(20)
            .background(Color(NSColor.windowBackgroundColor))
        }
        // ✅ Explicit frame — sheet adopts this size on macOS
        .frame(minWidth: 600, idealWidth: 600, maxWidth: 700,
               minHeight: 700, idealHeight: 780, maxHeight: 900)
        .onAppear {
            if let bill = billToEdit {
                viewModel.loadFrom(bill)
            } else {
                if let preselected = preSelectedPropertyId {
                    viewModel.selectedPropertyId = preselected
                } else if let defaultProp = properties.first(where: { $0.isDefault }) {
                    viewModel.selectedPropertyId = defaultProp.id
                }
                viewModel.entryCurrency = appCurrency
                viewModel.prefillFromHistory(bills: allBills, properties: properties)
            }
        }
        .onDisappear { viewModel.reset() }
    }
}