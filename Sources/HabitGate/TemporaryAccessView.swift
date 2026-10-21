import SwiftUI
import GateCore

private typealias AccessState<Value> = SwiftUI.State<Value>

struct TemporaryAccessView: View {
    @ObservedObject var store: GateStore
    @ObservedObject var access: DailyAccessController
    @AccessState private var duration = 15
    @AccessState private var custom = "15"
    private var minutes: Int? { duration == 0 ? DailyAccessBudget.minutes(custom) : duration }
    private var apps: [BlockedApp] { store.configuration.active?.apps ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DailyAccessCard(store: store, access: access)
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
            HStack(spacing: 9) {
                ForEach(apps) { app in
                    MacAppIcon(app: app).help(app.name).accessibilityHidden(false).accessibilityLabel(app.name)
                }
                Spacer(minLength: 0)
                Label("Websites stay protected", systemImage: "lock.shield")
                    .font(.system(size: 10)).foregroundStyle(.secondary)
            }
            if !access.notice.isEmpty { Text(access.notice).font(.system(size: 10)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
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
        return access.isCounting ? "Counting foreground use" : "Paused · ready when you need it"
    }
    var body: some View {
        GateCard(padding: compact ? 14 : 16) {
            VStack(alignment: .leading, spacing: compact ? 8 : 10) {
                HStack {
                    Label("Today’s app allowance", systemImage: "timer")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(GateTheme.blue)
                    Spacer()
                    Text("\(access.budget.todayMinutes) min / day").font(.system(size: 10)).foregroundStyle(.secondary)
                    if compact {
                        Button { store.requestTemporaryAccess() } label: { Image(systemName: "gearshape") }
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
                    Text("Open any blocked Mac app to use this balance. Switch away and the timer pauses. When it runs out, app windows hide; background work may continue.")
                        .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
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
    private var countdown: some View {
        let seconds = max(0, Int(ceil(access.remaining)))
        return HStack(alignment: .center, spacing: 16) {
            Text(String(format: "%02d:%02d", seconds / 60, seconds % 60))
                .font(.system(size: compact ? 29 : 48, weight: .semibold, design: .rounded)).monospacedDigit()
                .accessibilityLabel("\(seconds / 60) minutes \(seconds % 60) seconds left today")
            VStack(alignment: .leading, spacing: 5) {
                Text(state).font(.system(size: 11, weight: .medium))
                Text("Remaining today · resets at \(access.budget.resetsAt.formatted(date: .omitted, time: .shortened))").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
    }

}
