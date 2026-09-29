import Foundation
import Observation

/// Persistent per-bill-title spending limits.
/// Keyed by lowercased bill title so a single setting applies to
/// every occurrence of that bill, past and future.
@Observable
final class BillLimits {
    static let shared = BillLimits()
    private let key = "bill.limits.v1"

    /// lowercased title → limit (stored in KSH)
    private(set) var limits: [String: Double] = [:]

    private init() { load() }

    // MARK: - Public API
    func limit(for title: String) -> Double? {
        limits[title.lowercased()]
    }

    func hasLimit(for title: String) -> Bool {
        limits[title.lowercased()] != nil
    }

    func setLimit(_ value: Double?, for title: String) {
        let key = title.lowercased()
        if let value, value > 0 {
            limits[key] = value
        } else {
            limits.removeValue(forKey: key)
        }
        save()
    }

    func allTitles() -> [String] {
        Array(limits.keys).sorted()
    }

    // MARK: - Persistence
    private func load() {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Double].self, from: data)
        else { return }
        limits = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(limits) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}