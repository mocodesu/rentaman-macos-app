import Foundation
import Observation
import Combine
import ConvexMobile

// MARK: - Auth State
enum AuthState: Equatable {
    case checking
    case signedOut
    case signedIn(email: String, name: String?)
    
    var isSignedIn: Bool {
        if case .signedIn = self { return true }
        return false
    }
}

// MARK: - Response DTOs
/// Decodes the `{ "apiKey": "..." }` response from signUp / signIn
struct AuthApiKeyResponse: Decodable {
    let apiKey: String
}

/// Decodes the current user from `auth:me`
struct AuthUser: Decodable {
    let _id: String
    let email: String
    let name: String?
}

// MARK: - Auth Errors
enum AuthError: LocalizedError {
    case invalidResponse
    case serverMessage(String)
    case networkError(Error)
    case notConfigured
    
    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "The server returned an unexpected response."
        case .serverMessage(let msg):
            return msg
        case .networkError(let err):
            return err.localizedDescription
        case .notConfigured:
            return "Convex is not configured. Set ConvexConfig.deploymentUrl first."
        }
    }
}

// MARK: - Auth Service
@Observable
final class AuthService {
    
    // MARK: - Public State
    var state: AuthState = .checking
    var isBusy: Bool = false
    
    // MARK: - Private
    private var client: ConvexClient?
    private(set) var apiKey: String?
    
    // MARK: - Singleton
    static let shared = AuthService()
    private init() {}
    
    // MARK: - Launch
    func bootstrap() {
        guard ConvexConfig.isConfigured,
              let urlString = ConvexConfig.deploymentUrl,
              let url = URL(string: urlString) else {
            print("⚠️ AuthService: Convex not configured — starting signed out.")
            state = .signedOut
            return
        }
        
        client = ConvexClient(deploymentUrl: url.absoluteString)
        
        guard let storedKey = KeychainHelper.load(), !storedKey.isEmpty else {
            print("ℹ️ AuthService: no stored API key — signed out.")
            state = .signedOut
            return
        }
        
        apiKey = storedKey
        Task { await verifyStoredKey() }
    }
    
    // MARK: - Sign Up
    func signUp(email: String, password: String, name: String?) async throws {
        guard let client = client else { throw AuthError.notConfigured }
        await MainActor.run { self.isBusy = true }
        defer { Task { @MainActor in self.isBusy = false } }
        
        var args: [String: ConvexEncodable?] = [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "password": password
        ]
        if let name = name, !name.isEmpty {
            args["name"] = name
        }
        
        print("🚀 AuthService.signUp — calling auth:signUp with email: \(args["email"] ?? "")")
        
        do {
            let response: AuthApiKeyResponse = try await client.action("auth:signUp", with: args)
            print("✅ AuthService.signUp — got apiKey (length: \(response.apiKey.count))")
            try await finishAuth(apiKey: response.apiKey, client: client)
        } catch let err as AuthError {
            throw err
        } catch {
            print("❌ AuthService.signUp error: \(error)")
            throw AuthError.networkError(error)
        }
    }
    
    // MARK: - Sign In
    func signIn(email: String, password: String) async throws {
        guard let client = client else { throw AuthError.notConfigured }
        await MainActor.run { self.isBusy = true }
        defer { Task { @MainActor in self.isBusy = false } }
        
        let args: [String: ConvexEncodable?] = [
            "email": email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
            "password": password
        ]
        
        print("🚀 AuthService.signIn — calling auth:signIn with email: \(args["email"] ?? "")")
        
        do {
            let response: AuthApiKeyResponse = try await client.action("auth:signIn", with: args)
            print("✅ AuthService.signIn — got apiKey (length: \(response.apiKey.count))")
            try await finishAuth(apiKey: response.apiKey, client: client)
        } catch let err as AuthError {
            throw err
        } catch {
            print("❌ AuthService.signIn error: \(error)")
            throw AuthError.networkError(error)
        }
    }
    
    // MARK: - Sign Out
    func signOut() {
        KeychainHelper.delete()
        apiKey = nil
        state = .signedOut
        SyncService.shared.reset()
        print("👋 AuthService — signed out.")
    }
    
    // MARK: - Finish Auth (shared between signUp / signIn)
    private func finishAuth(apiKey: String, client: ConvexClient) async throws {
        guard !apiKey.isEmpty else {
            print("❌ AuthService — empty apiKey in response")
            throw AuthError.invalidResponse
        }
        
        guard KeychainHelper.save(apiKey) else {
            print("⚠️ AuthService — Keychain save failed; continuing in-memory only")
            // Don't throw — allow the session to continue without persistence
            self.apiKey = apiKey
            // Skip user fetch if Keychain fails — we already have what we need
            await MainActor.run {
                self.state = .signedIn(email: "—", name: nil)
            }
            SyncService.shared.configureWithAuth(apiKey: apiKey)
            return
        }
        
        self.apiKey = apiKey
        print("💾 AuthService — apiKey saved to Keychain")
        
        // Try to fetch user profile (non-fatal if it fails)
        do {
            let user = try await fetchUser(client: client, apiKey: apiKey)
            await MainActor.run {
                self.state = .signedIn(email: user.email, name: user.name)
            }
            print("✅ AuthService — user loaded: \(user.email)")
        } catch {
            print("⚠️ AuthService — could not load user profile: \(error). Continuing anyway.")
            await MainActor.run {
                self.state = .signedIn(email: "—", name: nil)
            }
        }
        
        SyncService.shared.configureWithAuth(apiKey: apiKey)
    }
    
    // MARK: - Verify Stored Key
    private func verifyStoredKey() async {
        guard let client = client, let key = apiKey else {
            await MainActor.run { self.state = .signedOut }
            return
        }
        
        do {
            let user = try await fetchUser(client: client, apiKey: key)
            await MainActor.run {
                self.state = .signedIn(email: user.email, name: user.name)
            }
            print("✅ AuthService — stored key verified for: \(user.email)")
            SyncService.shared.configureWithAuth(apiKey: key)
        } catch {
            print("⚠️ AuthService — stored key verification failed: \(error)")
            // Sign in optimistically — sync service will fail cleanly if the key is bad
            await MainActor.run {
                self.state = .signedIn(email: "—", name: nil)
            }
            SyncService.shared.configureWithAuth(apiKey: key)
        }
    }
    
    // MARK: - Fetch Current User
    /// Uses `subscribe` + `firstValue` and handles nullable responses.
    private func fetchUser(client: ConvexClient, apiKey: String) async throws -> AuthUser {
        let args: [String: ConvexEncodable?] = ["apiKey": apiKey]
        
        // auth:me can return null (user not found), so decode as Optional
        let publisher = client.subscribe(
            to: "auth:me",
            with: args,
            yielding: AuthUser?.self
        )
        
        let user = try await publisher.firstValue()
        guard let user = user else {
            throw AuthError.serverMessage("Your session has expired. Please sign in again.")
        }
        return user
    }
}