import SwiftUI
import SwiftData

@main
struct RentaManApp: App {
    let container: ModelContainer
    @State private var auth = AuthService.shared
    
    init() {
        do {
            let schema = Schema([Property.self, Bill.self])
            let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            container = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Fatal Error: Could not initialize RentaMan database. \(error.localizedDescription)")
        }
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .frame(minWidth: 900, minHeight: 600)
                .environment(auth)
                .environment(SyncService.shared)
                .modelContainer(container)
                .onAppear {
                    SyncService.shared.configure(modelContext: container.mainContext)
                    auth.bootstrap()           
}
                }
                .windowStyle(.hiddenTitleBar)
        .modelContainer(container)
        
        Settings {
            SettingsRootView()
                .environment(auth)
                .environment(SyncService.shared)
                .modelContainer(container)
        }
    }
}

// MARK: - Root View (Onboarding → Auth → App)
struct RootView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var syncService
    @Environment(\.modelContext) private var modelContext
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    
    var body: some View {
        Group {
            if !hasCompletedOnboarding {
                OnboardingView()
                    .environment(\.modelContext, modelContext)
                    .transition(.opacity)
            } else {
                switch auth.state {
                case .checking:
                    VStack(spacing: 16) {
                        ProgressView().controlSize(.large)
                        Text("Loading RentaMan…").foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    
                case .signedOut:
                    LoginView()
                    
                case .signedIn:
                    ContentView()
                }
            }
        }
        .animation(.easeInOut(duration: 0.3), value: hasCompletedOnboarding)
        .animation(.easeInOut(duration: 0.2), value: auth.state)
    }
}
