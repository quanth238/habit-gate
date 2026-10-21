import SwiftUI
import GateCore

private typealias AccessState<Value> = SwiftUI.State<Value>

struct TemporaryAccessView: View {
    @ObservedObject var store: GateStore
    @ObservedObject var access: DailyAccessController
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            DailyAccessCard(store: store, access: access)
            HStack(spacing: 9) {
                ForEach(store.configuration.active?.apps ?? []) { app in
                    MacAppIcon(app: app).help(app.name).accessibilityHidden(false).accessibilityLabel(app.name)
                }
                Spacer(minLength: 0)
                Label("Websites stay protected", systemImage: "lock.shield")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Button { store.requestTemporaryAccess(settings: true) } label: {
                Label("Daily allowance settings", systemImage: "gearshape")
            }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(GateTheme.blue)
        }.onDisappear { store.pendingAccessApp = nil }
    }
}

struct DailyAccessSettingsView: View {
    @ObservedObject var store: GateStore
    @ObservedObject var access: DailyAccessController
    @AccessState private var duration = 15
    @AccessState private var custom = "15"
    private var minutes: Int? { duration == 0 ? DailyAccessBudget.minutes(custom) : duration }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GateCard(padding: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("Daily allowance").font(.system(size: 13, weight: .semibold))
                        Spacer()
                        Text("Shared across all blocked apps").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 7) {
                        ForEach([5, 15, 30, 60, 0], id: \.self) { value in
                            Button { duration = value } label: {
                                Text(value == 0 ? "Custom" : "\(value) min").frame(maxWidth: .infinity)
                            }.buttonStyle(GateButtonStyle(primary: duration == value))
                                .accessibilityValue(duration == value ? "Selected" : "")
                        }
                    }
                    if duration == 0 {
                        HStack {
                            TextField("Minutes", text: $custom).textFieldStyle(.roundedBorder).frame(width: 70)
                                .accessibilityLabel("Daily allowance in minutes")
                            Text("minutes · 1–120").font(.system(size: 11)).foregroundStyle(.secondary)
                            if minutes == nil { Text("Enter 1–120 whole minutes.").font(.system(size: 10)).foregroundStyle(.orange) }
                        }
                    }
                    HStack {
                        Text(access.budget.limitMinutes == access.budget.todayMinutes ? "Changes begin at 4 AM; today’s balance stays the same." : "Next reset: \(access.budget.limitMinutes) minutes. Today’s balance stays the same.")
                            .font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 8)
                        Button("Save allowance") { if let minutes { access.setMinutes(minutes) } }
                            .keyboardShortcut("s", modifiers: .command).help("Save daily allowance (⌘S)")
                            .buttonStyle(GateButtonStyle(primary: true))
                            .disabled(minutes == nil || minutes == access.budget.limitMinutes || !access.issue.isEmpty || store.needsRecovery)
                    }
                }
            }
            if !access.notice.isEmpty {
                Text(access.notice).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }.onAppear {
            let limit = access.budget.limitMinutes
            duration = [5, 15, 30, 60].contains(limit) ? limit : 0; custom = String(limit)
        }
    }
}

struct DailyAccessCard: View {
    @ObservedObject var store: GateStore
    @ObservedObject var access: DailyAccessController
    var compact = false
    private var state: String {
        if store.normalAccess { return "Essentials complete · apps unlocked" }
        if !access.issue.isEmpty || store.needsRecovery { return "Allowance locked · needs attention" }
        if access.remaining <= 0 { return "Daily allowance used up" }
        if !access.accessStarted { return "Ready when you need it" }
        return access.isCounting ? "Counting foreground use" : "Access on · paused until you use an app"
    }
    var body: some View {
        GateCard(padding: compact ? 14 : 20) {
            VStack(alignment: .leading, spacing: compact ? 8 : 16) {
                HStack {
                    Label("Today’s app allowance", systemImage: "timer")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(GateTheme.blue)
                    Spacer()
                    Text("\(access.budget.todayMinutes) min / day").font(.system(size: 10)).foregroundStyle(.secondary)
                    if compact {
                        Button { store.requestTemporaryAccess(settings: true) } label: { Image(systemName: "gearshape") }
                            .buttonStyle(.plain).accessibilityLabel("Configure daily allowance")
                    }
                }
                if access.isCounting {
                    TimelineView(.periodic(from: .now, by: 1)) { _ in countdown }
                } else { countdown }
                if access.remaining > 0 && access.remaining <= 60 {
                    Text("One minute or less left today").font(.system(size: 10, weight: .medium)).foregroundStyle(.orange)
                }
                if !compact {
                    Text(access.accessStarted ? "Switching away pauses your time. End access when you’re done." : "Start when you need access. Only foreground app use counts.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                if access.accessStarted {
                    Button { access.endAccess() } label: {
                        Text("End access").frame(maxWidth: .infinity)
                    }.buttonStyle(GateButtonStyle(primary: true))
                } else {
                    Button { store.startDailyAccess() } label: {
                        Text("Start access").frame(maxWidth: .infinity)
                    }.buttonStyle(GateButtonStyle(primary: true))
                        .disabled(!access.canStart || store.normalAccess || store.needsRecovery)
                }
                if !access.issue.isEmpty {
                    Text(access.issue).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
                    if access.issue.hasPrefix("Daily allowance could not be saved.") {
                        Button("Retry storage") { access.retryStorage() }.buttonStyle(GateButtonStyle())
                    }
                }
            }
        }
    }
    @ViewBuilder private var countdown: some View {
        let seconds = max(0, Int(ceil(access.remaining)))
        let digits = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        if compact {
            HStack(alignment: .center, spacing: 16) {
                Text(digits).font(.system(size: 29, weight: .semibold, design: .rounded)).monospacedDigit()
                    .accessibilityLabel("\(seconds / 60) minutes \(seconds % 60) seconds left today")
                countdownStatus
                Spacer(minLength: 0)
            }
        } else {
            VStack(spacing: 12) {
                Text(digits).font(.system(size: 76, weight: .semibold, design: .rounded)).monospacedDigit()
                    .tracking(-2).accessibilityLabel("\(seconds / 60) minutes \(seconds % 60) seconds left today")
                countdownStatus
            }.frame(maxWidth: .infinity).padding(.vertical, 8)
        }
    }
    private var countdownStatus: some View {
        VStack(alignment: compact ? .leading : .center, spacing: 5) {
            Text(state).font(.system(size: 12, weight: .medium))
            Text("Remaining today · resets at \(access.budget.resetsAt.formatted(date: .omitted, time: .shortened))")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}
