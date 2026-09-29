import SwiftUI

struct SyncStatusView: View {
    @Environment(SyncService.self) private var syncService
    
    var body: some View {
        HStack(spacing: 6) {
            // Status icon / pulsing dot
            statusIndicator
            
            // Status label
            Text(syncService.state.label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            
            // 🆕 Pending count badge
            if syncService.pendingCount > 0 {
                Text("\(syncService.pendingCount)")
                    .font(.caption2)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.orange)
                    .clipShape(Capsule())
                    .help("\(syncService.pendingCount) change(s) waiting to sync")
            }
            
            // 🆕 Error indicator
            if case .error = syncService.state {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .help(syncService.lastError ?? "Sync error")
            }
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
    
    @ViewBuilder
    private var statusIndicator: some View {
        switch syncService.state {
        case .live:
            // Pulsing green dot for live mode
            Circle()
                .fill(.green)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle()
                        .stroke(.green.opacity(0.5), lineWidth: 1.5)
                        .scaleEffect(1.6)
                        .opacity(0.6)
                )
        case .syncing:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 12, height: 12)
        default:
            Image(systemName: syncService.state.icon)
                .font(.caption)
                .foregroundStyle(iconColor)
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
            lines.append("Last update: \(last.formatted(date: .abbreviated, time: .standard))")
        }
        
        if syncService.pendingCount > 0 {
            lines.append("⏳ Pending: \(syncService.pendingCount) change(s)")
        }
        
        if syncService.isLive {
            lines.append("📡 Connected to live stream")
        }
        
        if let err = syncService.lastError {
            lines.append("❌ \(err)")
        }
        
        lines.append("—")
        lines.append("Click to force sync now")
        return lines.joined(separator: "\n")
    }
}