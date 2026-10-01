import SwiftUI
import AppKit

// MARK: - Window Drag Handle
struct WindowDragHandle: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { DraggableView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class DraggableView: NSView {
        override var mouseDownCanMoveWindow: Bool { true }
    }
}

// MARK: - Toolbar Leading (Logo + Name + Email)
struct RentaManToolbarLeading: View {
    @Environment(AuthService.self) private var auth

    private var subtitle: String {
        if case .signedIn(let email, _) = auth.state {
            return email
        }
        return "Not signed in"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "house.lodge.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(RMDesign.accent)
                .frame(width: 20, height: 20)
                .background(RMDesign.accentSoft)
                .clipShape(RoundedRectangle(cornerRadius: 5))

            VStack(alignment: .leading, spacing: 0) {
                Text("RentaMan")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize()
        .help("RentaMan — Bill & Property Manager")
    }
}

// MARK: - Sync Pill
struct RentaManSyncPill: View {
    @Environment(SyncService.self) private var syncService
    @Environment(AuthService.self) private var auth
    @State private var isHovered = false

    var body: some View {
        Menu {
            Section {
                if let last = syncService.lastSyncAt {
                    Label("Last update: \(relativeTime(last))", systemImage: "clock")
                }
                if syncService.pendingCount > 0 {
                    Label("\(syncService.pendingCount) pending", systemImage: "arrow.up.circle")
                }
                if let err = syncService.lastError {
                    Label(err, systemImage: "exclamationmark.triangle")
                }
                if syncService.state.isLocalOnly {
                    Label("Running in Local Only mode", systemImage: "internaldrive")
                }
            }

            Divider()

            Button {
                Task { await syncService.forceSync() }
            } label: {
                Label("Sync Now", systemImage: "arrow.clockwise")
            }
            .disabled(!auth.state.isSignedIn)
        } label: {
            HStack(spacing: 5) {
                statusIndicator

                Text(statusLabel)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(labelColor)

                if syncService.pendingCount > 0 {
                    Text("\(syncService.pendingCount)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(minWidth: 12)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(RMDesign.warning)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(pillBackground)
            .overlay(Capsule().stroke(pillBorder, lineWidth: 0.75))
            .clipShape(Capsule())
            .contentShape(Capsule())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .onHover { hovering in
            withAnimation(RMDesign.ease) { isHovered = hovering }
        }
        .help(syncService.lastError ?? syncService.state.label)
    }

    @ViewBuilder
    private var statusIndicator: some View {
        switch syncService.state {
        case .live: CompactLiveDot()
        case .syncing:
            ProgressView().controlSize(.mini).scaleEffect(0.6).frame(width: 7, height: 7)
        case .error:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(RMDesign.danger)
        case .localOnly:
            Image(systemName: "internaldrive.fill")
                .font(.system(size: 9, weight: .medium))
                .foregroundStyle(.secondary)
        case .idle:
            Image(systemName: "checkmark.icloud.fill")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(RMDesign.success)
        }
    }

    private var statusLabel: String {
        switch syncService.state {
        case .live: return "Live"
        case .syncing: return "Syncing"
        case .error: return "Error"
        case .localOnly: return "Local"
        case .idle: return "Synced"
        }
    }

    private var labelColor: Color {
        switch syncService.state {
        case .error: return RMDesign.danger
        case .live, .idle: return .primary
        default: return .primary
        }
    }

    private var pillBackground: Color {
        isHovered ? Color.gray.opacity(0.14) : Color.gray.opacity(0.06)
    }

    private var pillBorder: Color {
        switch syncService.state {
        case .error: return RMDesign.danger.opacity(0.4)
        default: return RMDesign.borderColor
        }
    }

    private func relativeTime(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Compact Live Dot
struct CompactLiveDot: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.green.opacity(pulse ? 0 : 0.55), lineWidth: 1)
                .frame(width: 8, height: 8)
                .scaleEffect(pulse ? 1.7 : 0.8)
                .opacity(pulse ? 0 : 1)
            Circle()
                .fill(Color.green)
                .frame(width: 5, height: 5)
        }
        .frame(width: 8, height: 8)
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

// MARK: - Backwards Compat
struct LiveIndicator: View {
    @State private var pulse = false
    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.green.opacity(pulse ? 0 : 0.5), lineWidth: 1.5)
                .frame(width: 12, height: 12)
                .scaleEffect(pulse ? 1.6 : 0.8)
                .opacity(pulse ? 0 : 1)
            Circle()
                .fill(Color.green)
                .frame(width: 7, height: 7)
                .shadow(color: Color.green.opacity(0.6), radius: 3)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.8).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

// MARK: - Currency Picker
struct RentaManCurrencyPicker: View {
    @AppStorage(PreferenceKey.displayCurrency) private var currencyRaw: String = AppCurrency.ksh.rawValue
    @Namespace private var namespace

    private var currency: AppCurrency {
        AppCurrency(rawValue: currencyRaw) ?? .ksh
    }

    var body: some View {
        HStack(spacing: 1) {
            ForEach(AppCurrency.allCases) { curr in
                Button {
                    withAnimation(RMDesign.springFast) {
                        currencyRaw = curr.rawValue
                    }
                } label: {
                    Text(curr.rawValue)
                        .font(.system(size: 9.5, weight: .semibold))
                        .tracking(0.3)
                        .foregroundStyle(currency == curr ? .white : .secondary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3.5)
                        .background {
                            if currency == curr {
                                Capsule()
                                    .fill(RMDesign.accent)
                                    .matchedGeometryEffect(id: "currencyPill", in: namespace)
                            }
                        }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Display amounts in \(curr.displayName)")
            }
        }
        .padding(1.5)
        .background(Color.gray.opacity(0.08))
        .overlay(Capsule().stroke(RMDesign.borderColor, lineWidth: 0.75))
        .clipShape(Capsule())
        .fixedSize()
    }
}

// MARK: - Add Bill Button (Native Primary Action)
struct RentaManAddBillButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label("Add Bill", systemImage: "plus")
                .font(.system(size: 12, weight: .medium))
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .keyboardShortcut("n", modifiers: .command)
        .help("Add a new bill (⌘N)")
        .fixedSize()
    }
}