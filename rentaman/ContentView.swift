import SwiftUI
import SwiftData

// MARK: - App Currency Environment Key
private struct AppCurrencyKey: EnvironmentKey {
    static let defaultValue: AppCurrency = .ksh
}

extension EnvironmentValues {
    var appCurrency: AppCurrency {
        get { self[AppCurrencyKey.self] }
        set { self[AppCurrencyKey.self] = newValue }
    }
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(AuthService.self) private var auth
    @Query private var properties: [Property]
    
    @State private var selection: String? = "AllBills"
    @State private var isShowingAddPropertySheet = false
    @State private var isShowingAddBillSheet = false
    @State private var syncService = SyncService.shared
    
    @AppStorage("displayCurrency") private var currencyRaw: String = AppCurrency.ksh.rawValue
    
    private var currentCurrency: AppCurrency {
        AppCurrency(rawValue: currencyRaw) ?? .ksh
    }
    
    var body: some View {
        NavigationSplitView {
            // MARK: - Sidebar
            List(selection: $selection) {
                Section {
                    Label("Dashboard", systemImage: "square.grid.2x2.fill")
                        .tag("Dashboard")
                    Label("All Bills", systemImage: "list.bullet.rectangle.portrait.fill")
                        .tag("AllBills")
                    Label("Reports", systemImage: "chart.pie.fill")
                        .tag("Reports")
                } header: {
                    Text("Overview")
                }
                
                Section {
                    ForEach(properties) { property in
                        HStack(spacing: 8) {
                            Image(systemName: property.isDefault ? "house.fill" : "house")
                            Text(property.name)
                            Spacer()
                            if property.isDefault {
                                Image(systemName: "star.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.yellow)
                            }
                        }
                        .tag(property.id)
                        .contextMenu {
                            if !property.isDefault {
                                Button {
                                    setDefaultProperty(property)
                                } label: {
                                    Label("Set as Default", systemImage: "star")
                                }
                            }
                            Button(role: .destructive) {
                                deleteProperty(property)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    HStack {
                        Text("Properties")
                        Spacer()
                        Button {
                            isShowingAddPropertySheet = true
                        } label: {
                            Image(systemName: "plus.circle.fill")
                                .font(.title3)
                                .foregroundStyle(.blue)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Add a new property (Cmd+Shift+N)")
                        .keyboardShortcut("n", modifiers: [.command, .shift])
                    }
                    .padding(.trailing, 4)
                }
            }
            .listStyle(SidebarListStyle())
            .navigationTitle("RentaMan")
            
        } detail: {
            Group {
                if selection == "Dashboard" {
                    DashboardView()
                } else if selection == "AllBills" {
                    AllBillsView()
                } else if selection == "Reports" {
                    ReportsView()
                } else if let propertyId = selection {
                    PropertyDetailView(propertyId: propertyId)
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "sidebar.left")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("Select an item from the sidebar")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .environment(\.appCurrency, currentCurrency)
        }
        .toolbar {
            // Sync status pill
            ToolbarItem(placement: .automatic) {
                SyncStatusView()
                    .environment(syncService)
            }
            
            // Currency toggle
            ToolbarItem(placement: .automatic) {
                Picker("Currency", selection: $currencyRaw) {
                    ForEach(AppCurrency.allCases) { curr in
                        Text("\(curr.symbol) \(curr.rawValue)").tag(curr.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .help("Switch display currency")
            }
            
            // Account menu
            ToolbarItem(placement: .automatic) {
                AccountMenuView()
                    .environment(auth)
            }
            
            // Add Bill
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isShowingAddBillSheet = true
                } label: {
                    Label("Add Bill", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("Add a new bill (Cmd+N)")
            }
        }
        .sheet(isPresented: $isShowingAddPropertySheet) {
            AddPropertyView()
                .environment(\.appCurrency, currentCurrency)
        }
        .sheet(isPresented: $isShowingAddBillSheet) {
            AddBillView()
                .environment(\.appCurrency, currentCurrency)
        }
    }
    
    private func setDefaultProperty(_ property: Property) {
        for prop in properties {
            prop.isDefault = (prop.id == property.id)
            prop.syncStatus = .pendingUpload
            prop.updatedAt = Date()
        }
        syncService.schedulePush()
    }
    
  private func deleteProperty(_ property: Property) {
    Task {
        await SyncService.shared.deleteProperty(property)
    }
}
}

// MARK: - Account Menu
struct AccountMenuView: View {
    @Environment(AuthService.self) private var auth
    
    var body: some View {
        Menu {
            if case .signedIn(let email, let name) = auth.state {
                Section {
                    if let name, !name.isEmpty {
                        Label(name, systemImage: "person.fill")
                    }
                    Label(email, systemImage: "envelope.fill")
                }
                
                Divider()
                
                Button {
                    Task { await SyncService.shared.forceSync() }
                } label: {
                    Label("Sync Now", systemImage: "arrow.triangle.2.circlepath")
                }
                
                Divider()
                
                Button(role: .destructive) {
                    auth.signOut()
                } label: {
                    Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } label: {
            Image(systemName: "person.crop.circle.fill")
                .font(.title3)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.blue)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .frame(width: 30)
        .help("Account menu")
    }
}

// MARK: - Property Detail Placeholder
struct PropertyDetailView: View {
    let propertyId: String
    @Query private var properties: [Property]
    
    private var property: Property? {
        properties.first { $0.id == propertyId }
    }
    
    var body: some View {
        if let property = property {
            VStack(spacing: 16) {
                Image(systemName: "house.fill")
                    .font(.system(size: 56))
                    .foregroundStyle(Color(hex: property.colorHex))
                Text(property.name)
                    .font(.largeTitle)
                    .fontWeight(.bold)
                if let address = property.address, !address.isEmpty {
                    Text(address)
                        .foregroundStyle(.secondary)
                }
                Text("Bills: \(property.bills.count)")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            Text("Property not found")
                .foregroundStyle(.secondary)
        }
    }
}

// MARK: - Color Extension
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3:
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6:
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8:
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue:  Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}