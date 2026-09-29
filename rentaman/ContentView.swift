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
    @Environment(SyncService.self) private var syncService
    @Query private var properties: [Property]

    @State private var isShowingAddPropertySheet = false
    @State private var isShowingAddBillSheet = false
    @State private var navigation = AppNavigation.shared

    @AppStorage(PreferenceKey.displayCurrency) private var currencyRaw: String = AppCurrency.ksh.rawValue

    private var currentCurrency: AppCurrency {
        AppCurrency(rawValue: currencyRaw) ?? .ksh
    }

    private let trafficLightWidth: CGFloat = 78
    private let headerHeight: CGFloat = 48

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 0) {
                // ───── HEADER ─────
                HStack(spacing: 0) {
                    Spacer().frame(width: trafficLightWidth)

                    RentaManToolbarLeading()

                    Spacer(minLength: 20)

                    HStack(spacing: 10) {
                        RentaManSyncPill()
                        RentaManCurrencyPicker()
                        RentaManAddBillButton {
                            isShowingAddBillSheet = true
                        }
                    }
                }
                .padding(.horizontal, 16)
                .frame(height: headerHeight)
                .frame(maxWidth: .infinity)
                .background {
                    Rectangle().fill(.ultraThinMaterial)
                }
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.gray.opacity(0.18))
                        .frame(height: 0.5)
                }

                // ───── TAB CONTENT ─────
                Group {
                    switch navigation.selectedTab {
                    case .dashboard:
                        DashboardView()
                            .environment(\.appCurrency, currentCurrency)
                    case .bills:
                        AllBillsView()
                            .environment(\.appCurrency, currentCurrency)
                    case .impact:
                        BillImpactView()
                            .environment(\.appCurrency, currentCurrency)
                    case .reports:
                        ReportsView()
                            .environment(\.appCurrency, currentCurrency)
                    case .profile:
                        ProfileView()
                            .environment(\.appCurrency, currentCurrency)
                    case .settings:
                        SettingsTabView()
                            .environment(\.appCurrency, currentCurrency)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.opacity)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: 82)
                }
            }

            // ───── FLOATING BOTTOM TAB BAR ─────
            RentaManTabBar(selection: $navigation.selectedTab)
        }
        .frame(minWidth: 900, minHeight: 600)
        .animation(.easeInOut(duration: 0.2), value: navigation.selectedTab)
        .sheet(isPresented: $isShowingAddPropertySheet) {
            AddPropertyView()
                .environment(\.appCurrency, currentCurrency)
        }
        .sheet(isPresented: $isShowingAddBillSheet) {
            AddBillView()
                .environment(\.appCurrency, currentCurrency)
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
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}