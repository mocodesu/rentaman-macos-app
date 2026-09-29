import SwiftUI

struct SyncStatusView: View {
    @Environment(SyncService.self) private var syncService
    
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: syncService.state.icon)
                .foregroundStyle(iconColor)
                .symbolEffect(.rotate, isActive: syncService.state == .syncing)
            
            Text(syncService.state.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Color(NSColor.controlBackgroundColor))
        .cornerRadius(12)
        .help(tooltip)
        .onTapGesture {
            Task { await syncService.forceSync() }
        }
    }
    
    private var iconColor: Color {
        switch syncService.state.color {
        case "green": return .green
        case "blue": return .blue
        case "red": return .red
        case "orange": return .orange
        default: return .secondary
        }
    }
    
    private var tooltip: String {
        var lines: [String] = [syncService.state.label]
        if let last = syncService.lastSyncAt {
            lines.append("Last sync: \(last.formatted(date: .abbreviated, time: .shortened))")
        }
        if syncService.pendingCount > 0 {
            lines.append("Pending: \(syncService.pendingCount) changes")
        }
        lines.append("Click to force sync now")
        return lines.joined(separator: "\n")
    }
}
