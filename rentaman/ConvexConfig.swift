import Foundation

/// Central configuration for Convex DB.
///
/// Resolution order for the deployment URL:
///   1. User-configured URL (stored in UserDefaults via Settings screen)
///   2. Hardcoded `defaultDeploymentUrl` below
///   3. `nil` → App runs in Local Only mode (no sync, no auth)
struct ConvexConfig {
    
    // MARK: - Default URL
    /// ✅ Pre-configured with your RentaMan deployment.
    /// Users can still override this via Settings → Convex.
    private static let defaultDeploymentUrl: String? = "https://zany-reindeer-526.convex.cloud"
    
    // MARK: - UserDefaults Key
    private static let urlKey = "convexDeploymentUrl"
    
    // MARK: - Deployment URL
    static var deploymentUrl: String? {
        // 1. User override from Settings
        if let userValue = UserDefaults.standard.string(forKey: urlKey),
           !userValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return userValue.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // 2. Built-in default
        if let defaultUrl = defaultDeploymentUrl, !defaultUrl.isEmpty {
            return defaultUrl
        }
        // 3. Not configured
        return nil
    }
    
    /// Set or clear the URL at runtime (from the Settings screen).
    static func setDeploymentUrl(_ url: String?) {
        if let url = url, !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let cleaned = url.trimmingCharacters(in: .whitespacesAndNewlines)
            UserDefaults.standard.set(cleaned, forKey: urlKey)
        } else {
            UserDefaults.standard.removeObject(forKey: urlKey)
        }
    }
    
    // MARK: - Auth
    static var authToken: String? {
        return nil
    }
    
    // MARK: - Behaviour
    static let pushDebounceSeconds: TimeInterval = 3.0
    static let retryBaseSeconds: TimeInterval = 5.0
    static let retryMaxSeconds: TimeInterval = 300.0
    static let pullOnLaunch: Bool = true
    
    // MARK: - Validation
    static var isConfigured: Bool {
        guard let url = deploymentUrl,
              !url.isEmpty,
              let parsed = URL(string: url),
              let scheme = parsed.scheme,
              (scheme == "https" || scheme == "http"),
              parsed.host != nil else {
            return false
        }
        return true
    }
    
    static var configurationProblem: String? {
        guard let url = deploymentUrl, !url.isEmpty else {
            return "No Convex URL configured. Open Settings → Convex to set it."
        }
        guard let parsed = URL(string: url) else {
            return "Invalid URL format. Expected: https://name.convex.cloud"
        }
        guard let scheme = parsed.scheme, scheme == "https" || scheme == "http" else {
            return "URL must start with https://"
        }
        guard parsed.host != nil else {
            return "URL has no host. Expected format: https://name.convex.cloud"
        }
        guard url.hasSuffix(".convex.cloud") else {
            return "URL should end with .convex.cloud (got: \(url))"
        }
        return nil
    }
    
    // MARK: - Debug
    static var debugDescription: String {
        let url = deploymentUrl ?? "nil"
        let configured = isConfigured ? "✅ configured" : "❌ not configured"
        let problem = configurationProblem ?? "none"
        return """
        [ConvexConfig]
          URL:      \(url)
          Status:   \(configured)
          Problem:  \(problem)
        """
    }
}