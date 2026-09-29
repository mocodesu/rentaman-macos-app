import Foundation

/// Defines the sync state of a local record with the future Convex backend.
enum SyncStatus: String, Codable, CaseIterable {
    case synced = "synced"
    case pendingUpload = "pending_upload"
    case pendingDelete = "pending_delete"
}
