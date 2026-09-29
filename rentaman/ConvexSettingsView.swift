import SwiftUI
import Combine

struct ConvexSettingsView: View {
    @Environment(AuthService.self) private var auth
    @Environment(SyncService.self) private var syncService
    
    @State private var urlInput: String = ConvexConfig.deploymentUrl ?? ""
    @State private var isTesting: Bool = false
    @State private var testResult: TestResult? = nil
    
    enum TestResult {
        case success
        case failure(String)
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 4) {
                    Text("Sync")
                        .font(.system(size: 24, weight: .bold))
                    Text("Configure your Convex backend and monitor sync status.")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                
                // MARK: - Current Status
                SettingsSection(title: "Status", subtitle: "Real-time connection to your Convex backend.") {
                    VStack(spacing: 0) {
                        StatusRow(
                            icon: statusIcon,
                            iconColor: statusColor,
                            title: "Connection",
                            value: syncService.state.label,
                            valueColor: statusColor
                        )
                        
                        Divider().padding(.leading, 40).padding(.vertical, 4)
                        
                        StatusRow(
                            icon: "person.crop.circle.fill",
                            iconColor: .blue,
                            title: "Signed in as",
                            value: signedInEmail,
                            valueColor: .primary
                        )
                        
                        Divider().padding(.leading, 40).padding(.vertical, 4)
                        
                        StatusRow(
                            icon: "clock.fill",
                            iconColor: .orange,
                            title: "Last sync",
                            value: lastSyncText,
                            valueColor: .secondary
                        )
                        
                        if syncService.pendingCount > 0 {
                            Divider().padding(.leading, 40).padding(.vertical, 4)
                            
                            StatusRow(
                                icon: "arrow.up.circle.fill",
                                iconColor: .orange,
                                title: "Pending changes",
                                value: "\(syncService.pendingCount) awaiting upload",
                                valueColor: .orange
                            )
                        }
                        
                        if let err = syncService.lastError {
                            Divider().padding(.leading, 40).padding(.vertical, 4)
                            
                            StatusRow(
                                icon: "exclamationmark.triangle.fill",
                                iconColor: .red,
                                title: "Last error",
                                value: err,
                                valueColor: .red
                            )
                        }
                        
                        Divider().padding(.leading, 40).padding(.vertical, 4)
                        
                        SettingsRow(
                            icon: "arrow.triangle.2.circlepath",
                            iconColor: .green,
                            title: "Force sync now",
                            subtitle: "Push all pending changes and reconnect the live stream."
                        ) {
                            Button {
                                Task { await syncService.forceSync() }
                            } label: {
                                Label("Sync Now", systemImage: "arrow.clockwise")
                            }
                            .buttonStyle(.bordered)
                            .disabled(auth.apiKey == nil)
                        }
                    }
                }
                
                // MARK: - Deployment URL
                SettingsSection(title: "Deployment URL", subtitle: "The URL of your Convex project. Find this in the terminal after running `bun run dev`.") {
                    VStack(spacing: 0) {
                        SettingsRow(
                            icon: "cloud.fill",
                            iconColor: .purple,
                            title: "Convex URL",
                            subtitle: "Format: https://your-project.convex.cloud"
                        ) {
                            EmptyView()
                        }
                        
                        TextField("https://your-project.convex.cloud", text: $urlInput)
                            .textFieldStyle(.plain)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(.horizontal, 12)
                            .frame(height: 36)
                            .background(Color(NSColor.textBackgroundColor))
                            .cornerRadius(8)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                            .autocorrectionDisabled()
                            .textCase(.lowercase)
                        
                        Spacer().frame(height: 12)
                        
                        HStack(spacing: 10) {
                            Button {
                                Task { await testConnection() }
                            } label: {
                                HStack(spacing: 6) {
                                    if isTesting {
                                        ProgressView().controlSize(.small)
                                        Text("Testing…")
                                    } else {
                                        Image(systemName: "checkmark.circle")
                                        Text("Test Connection")
                                    }
                                }
                            }
                            .buttonStyle(.bordered)
                            .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isTesting)
                            
                            Spacer()
                            
                            Button {
                                save()
                            } label: {
                                Label("Save URL", systemImage: "checkmark.circle.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(urlInput.trimmingCharacters(in: .whitespacesAndNewlines) == (ConvexConfig.deploymentUrl ?? ""))
                        }
                        
                        if let result = testResult {
                            Spacer().frame(height: 10)
                            switch result {
                            case .success:
                                HStack(spacing: 8) {
                                    Image(systemName: "checkmark.seal.fill")
                                        .foregroundStyle(.green)
                                    Text("Connection successful — the URL is reachable.")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.green)
                                    Spacer()
                                }
                                .padding(10)
                                .background(Color.green.opacity(0.08))
                                .cornerRadius(8)
                            case .failure(let msg):
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                    Text(msg)
                                        .font(.system(size: 12))
                                        .foregroundStyle(.red)
                                    Spacer()
                                }
                                .padding(10)
                                .background(Color.red.opacity(0.08))
                                .cornerRadius(8)
                            }
                        }
                    }
                }
                
                // MARK: - Diagnostics
                SettingsSection(title: "Diagnostics") {
                    VStack(spacing: 0) {
                        SettingsRow(
                            icon: "info.circle.fill",
                            iconColor: .blue,
                            title: "Configuration",
                            subtitle: ConvexConfig.configurationProblem ?? "All good"
                        ) {
                            if ConvexConfig.isConfigured {
                                Label("Valid", systemImage: "checkmark.circle.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.green)
                            } else {
                                Label("Invalid", systemImage: "xmark.circle.fill")
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(.red)
                            }
                        }
                        
                        Divider().padding(.leading, 40).padding(.vertical, 4)
                        
                        SettingsRow(
                            icon: "key.fill",
                            iconColor: .orange,
                            title: "API Key",
                            subtitle: auth.apiKey != nil ? "Stored securely in Keychain" : "Not available"
                        ) {
                            if let key = auth.apiKey {
                                Text("••••\(key.suffix(6))")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text("None")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                
                // MARK: - Danger Zone
                SettingsSection(title: "Session", subtitle: "Sign out or clear the stored URL.") {
                    VStack(spacing: 0) {
                        SettingsRow(
                            icon: "rectangle.portrait.and.arrow.right",
                            iconColor: .orange,
                            title: "Sign Out",
                            subtitle: "Disconnect from this account. Local data stays on your Mac."
                        ) {
                            Button("Sign Out") {
                                auth.signOut()
                            }
                            .buttonStyle(.bordered)
                            .disabled(!auth.state.isSignedIn)
                        }
                        
                        Divider().padding(.leading, 40).padding(.vertical, 4)
                        
                        SettingsRow(
                            icon: "trash.fill",
                            iconColor: .red,
                            title: "Clear URL & Sign Out",
                            subtitle: "Removes the Convex URL from this Mac and signs you out."
                        ) {
                            Button("Clear", role: .destructive) {
                                ConvexConfig.setDeploymentUrl(nil)
                                urlInput = ""
                                auth.signOut()
                                testResult = nil
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                        }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
    
    // MARK: - Computed
    private var statusIcon: String {
        syncService.isLive ? "dot.radiowaves.left.and.right" : syncService.state.icon
    }
    
    private var statusColor: Color {
        switch syncService.state {
        case .live: return .green
        case .idle: return .green
        case .syncing: return .blue
        case .error: return .red
        case .localOnly: return .gray
        }
    }
    
    private var signedInEmail: String {
        if case .signedIn(let email, _) = auth.state {
            return email
        }
        return "Not signed in"
    }
    
    private var lastSyncText: String {
        guard let date = syncService.lastSyncAt else { return "Never" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: Date())
    }
    
    // MARK: - Actions
    private func save() {
        let cleaned = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        ConvexConfig.setDeploymentUrl(cleaned)
        testResult = nil
        
        // Restart auth with the new URL
        auth.signOut()
        auth.bootstrap()
    }
    
    private func testConnection() async {
        isTesting = true
        testResult = nil
        defer { isTesting = false }
        
        let cleaned = urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let parsed = URL(string: cleaned),
              let scheme = parsed.scheme,
              (scheme == "https" || scheme == "http"),
              parsed.host != nil else {
            testResult = .failure("Invalid URL format")
            return
        }
        
        var request = URLRequest(url: parsed)
        request.httpMethod = "GET"
        request.timeoutInterval = 8
        
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, (200...499).contains(http.statusCode) {
                testResult = .success
            } else {
                testResult = .success
            }
        } catch {
            testResult = .failure("Could not reach server: \(error.localizedDescription)")
        }
    }
}

// MARK: - Status Row
struct StatusRow: View {
    let icon: String
    let iconColor: Color
    let title: String
    let value: String
    let valueColor: Color
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(iconColor.gradient)
                .cornerRadius(7)
            
            Text(title)
                .font(.system(size: 13, weight: .medium))
            
            Spacer()
            
            Text(value)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(valueColor)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.vertical, 4)
    }
}