import SwiftUI
import SwiftData

struct PropertiesSettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appCurrency) private var currency: AppCurrency
    @Query(sort: \Property.createdAt) private var properties: [Property]

    @State private var editingProperty: Property? = nil
    @State private var isShowingAddSheet = false
    @State private var propertyToDelete: Property? = nil
    @State private var isShowingDeleteConfirm = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Properties")
                            .font(.system(size: 22, weight: .semibold))
                        Text("Manage your houses, budgets, and default selection.")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        isShowingAddSheet = true
                    } label: {
                        Label("Add Property", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                // Empty state
                if properties.isEmpty {
                    VStack(spacing: 14) {
                        Image(systemName: "house")
                            .font(.system(size: 40, weight: .light))
                            .foregroundStyle(.tertiary)
                        VStack(spacing: 3) {
                            Text("No properties yet")
                                .font(.system(size: 14, weight: .semibold))
                            Text("Add your first house to start tracking bills.")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Button {
                            isShowingAddSheet = true
                        } label: {
                            Label("Add Property", systemImage: "plus.circle.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(40)
                    .background(RMDesign.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
                    .overlay(
                        RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                            .stroke(RMDesign.borderColor, lineWidth: 1)
                    )
                } else {
                    VStack(spacing: 10) {
                        ForEach(properties) { property in
                            PropertySettingsRow(
                                property: property,
                                currency: currency,
                                onSetDefault: { setDefault(property) },
                                onEdit: { editingProperty = property },
                                onDelete: {
                                    propertyToDelete = property
                                    isShowingDeleteConfirm = true
                                }
                            )
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .sheet(isPresented: $isShowingAddSheet) {
            AddPropertyView()
                .environment(\.appCurrency, currency)
        }
        .sheet(item: $editingProperty) { property in
            EditPropertyView(property: property)
                .environment(\.appCurrency, currency)
        }
        .alert(
            "Delete \"\(propertyToDelete?.name ?? "")\"?",
            isPresented: $isShowingDeleteConfirm,
            presenting: propertyToDelete
        ) { property in
            Button("Delete", role: .destructive) {
                AuditLog.shared.propertyDeleted(property, context: modelContext)
                Task { await SyncService.shared.deleteProperty(property) }
            }
            Button("Cancel", role: .cancel) {}
        } message: { property in
            Text("This will permanently remove **\(property.name)** and all \(property.bills.filter { !$0.isDeleted }.count) bill(s) associated with it. This action cannot be undone.")
        }
    }

    private func setDefault(_ property: Property) {
        for prop in properties {
            prop.isDefault = (prop.id == property.id)
            prop.syncStatus = .pendingUpload
            prop.updatedAt = Date()
        }
        AuditLog.shared.propertySetDefault(property, context: modelContext)
        SyncService.shared.schedulePush()
    }
}

// MARK: - Property Row
struct PropertySettingsRow: View {
    let property: Property
    let currency: AppCurrency
    let onSetDefault: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 12) {
            // Color dot
            ZStack {
                Circle()
                    .fill(Color(hex: property.colorHex).opacity(0.12))
                    .frame(width: 40, height: 40)
                Image(systemName: "house.fill")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(Color(hex: property.colorHex))
            }

            // Info
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(property.name)
                        .font(.system(size: 13, weight: .semibold))

                    if property.isDefault {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 8))
                            Text("Default")
                                .font(.system(size: 9, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.yellow)
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    }
                }

                HStack(spacing: 10) {
                    Label("\(property.bills.filter { !$0.isDeleted }.count) bill\(property.bills.filter { !$0.isDeleted }.count == 1 ? "" : "s")", systemImage: "doc.text")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    if property.monthlyBudget > 0 {
                        Label(CurrencyFormatter.format(property.monthlyBudget, as: currency) + "/mo", systemImage: "banknote")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            // Actions
            HStack(spacing: 6) {
                if !property.isDefault {
                    Button(action: onSetDefault) {
                        Image(systemName: "star")
                            .font(.system(size: 12))
                    }
                    .buttonStyle(.borderless)
                    .help("Set as default")
                }

                Button(action: onEdit) {
                    Image(systemName: "square.and.pencil")
                        .font(.system(size: 12))
                }
                .buttonStyle(.borderless)
                .help("Edit")

                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(RMDesign.danger)
                }
                .buttonStyle(.borderless)
                .help("Delete")
            }
            .opacity(isHovered ? 1 : 0.6)
        }
        .padding(12)
        .background(RMDesign.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: RMDesign.cardRadius))
        .overlay(
            RoundedRectangle(cornerRadius: RMDesign.cardRadius)
                .stroke(isHovered ? Color(hex: property.colorHex).opacity(0.35) : RMDesign.borderColor, lineWidth: 1)
        )
        .onHover { hovering in
            withAnimation(RMDesign.ease) {
                isHovered = hovering
            }
        }
    }
}