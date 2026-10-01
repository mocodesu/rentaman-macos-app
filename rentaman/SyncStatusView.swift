import SwiftUI

struct SyncStatusView: View {
    @Environment(SyncService.self) private var syncService

    var body: some View {
        HStack(spacing: 6) {
            // Status indicator
            statusIndicator

            // Status label
            Text(syncService.state.label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            // Pending count badge
            if syncService.pendingCount > 0 {
                Text("\(syncService.pendingCount)")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(RMDesign.warning)
                    .clipShape(Capsule())
                    .help("\(syncService.pendingCount) change(s) waiting to sync")
            }

            // Error indicator
            if case .error = syncService.state {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(RMDesign.danger)
                    .help(syncService.lastError ?? "Sync error")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(RMDesign.borderColor, lineWidth: 1)
        )
        .help(tooltip)
        .onTapGesture {
            Task { await syncService.forceSync() }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch syncService.state {
        case .live:
            // Pulsing green dot for live mode
            Circle()
                .fill(RMDesign.success)
                .frame(width: 7, height: 7)
                .overlay(
                    Circle()
                        .stroke(RMDesign.success.opacity(0.5), lineWidth: 1.5)
                        .scaleEffect(1.5)
                        .opacity(0.5)
                )
        case .syncing:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.65)
                .frame(width: 10, height: 10)
        default:
            Image(systemName: syncService.state.icon)
                .font(.system(size: 10))
                .foregroundStyle(iconColor)
        }
    }

    private var iconColor: Color {
        switch syncService.state.color {
        case "green": return RMDesign.success
        case "blue": return RMDesign.accent
        case "red": return RMDesign.danger
        case "orange": return RMDesign.warning
        default: return .secondary
        }
    }

    private var tooltip: String {
        var lines: [String] = [syncService.state.label]

        if let last = syncService.lastSyncAt {
            lines.append("Last update: \(last.formatted(date: .abbreviated, time: .standard))")
        }

        if syncService.pendingCount > 0 {
            lines.append("Pending: \(syncService.pendingCount) change(s)")
        }

        if syncService.isLive {
            lines.append("Connected to live stream")
        }

        if let err = syncService.lastError {
            lines.append("Error: \(err)")
        }

        lines.append("—")
        lines.append("Click to force sync now")
        return lines.joined(separator: "\n")
    }
}