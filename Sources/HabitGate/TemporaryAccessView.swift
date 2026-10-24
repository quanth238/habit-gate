import SwiftUI
import GateCore

private typealias AccessState<Value> = SwiftUI.State<Value>

struct TemporaryAccessView: View {
    @ObservedObject var store: GateStore
    @ObservedObject var access: DailyAccessController
    var availableSize: CGSize
    var body: some View {
        DailyAccessCard(store: store, access: access, availableSize: availableSize)
            .onDisappear { store.pendingAccessApp = nil }
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
    var availableSize = CGSize(width: 600, height: 440)
    private var dialDiameter: CGFloat { max(220, min(340, availableSize.width * 0.58, availableSize.height - 240)) }
    private var dialScale: CGFloat { dialDiameter / 232 }
    private var labelSize: CGFloat { min(13, max(11, 11 * dialScale)) }
    private var apps: [BlockedApp] { store.configuration.active?.apps ?? [] }
    private var state: String {
        if store.snapshot.isWeekendDayOff { return "Weekend day off" }
        if store.normalAccess { return "Apps unlocked" }
        if !access.issue.isEmpty || store.needsRecovery { return "Needs attention" }
        if apps.isEmpty { return "No apps selected" }
        if access.remaining <= 0 { return "Time used today" }
        return access.accessStarted ? "Access on" : "Ready"
    }
    private var caption: String {
        if store.snapshot.isWeekendDayOff { return "Apps and websites are available. Weekday rules resume Monday at 4 AM." }
        if store.normalAccess { return "Your essentials are complete. Enjoy your time." }
        if apps.isEmpty { return "Choose the apps to protect in Mac apps." }
        if access.remaining <= 0 { return "Complete your essentials or wait for the daily reset." }
        return access.accessStarted ? "End access to save time for later." : "Start when needed. End access to save unused time."
    }
    var body: some View {
        if compact { compactCard }
        else if store.snapshot.isWeekendDayOff {
            VStack(spacing: 18) {
                Image(systemName: "sun.max").font(.system(size: 44, weight: .light)).foregroundStyle(GateTheme.blue)
                    .accessibilityHidden(true)
                Text("Enjoy your weekend.").font(.system(size: 28, weight: .semibold)).tracking(-0.6)
                Text(caption).font(.system(size: 13)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 9) {
                    ForEach(Array(apps.prefix(5))) { app in MacAppIcon(app: app).help(app.name).accessibilityLabel(app.name) }
                }.padding(.top, 8)
                Label("No timer needed", systemImage: "lock.open").font(.system(size: 11)).foregroundStyle(GateTheme.green)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        else {
            VStack(spacing: 0) {
                liveCountdown
                action.frame(width: min(240, max(200, dialDiameter * 0.7))).padding(.top, 22)
                Text(caption).font(.system(size: min(14, labelSize))).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
                warning.padding(.top, 10)
                appStrip.padding(.top, 24)
                storageProblem.padding(.top, access.issue.isEmpty ? 0 : 12)
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
    }
    private var compactCard: some View {
        GateCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Today’s app allowance", systemImage: "timer")
                        .font(.system(size: 12, weight: .semibold)).foregroundStyle(GateTheme.blue)
                    Spacer()
                    Text("\(access.budget.todayMinutes) min / day").font(.system(size: 10)).foregroundStyle(.secondary)
                    Button { store.requestTemporaryAccess(settings: true) } label: { Image(systemName: "gearshape") }
                        .buttonStyle(.plain).accessibilityLabel("Configure daily allowance")
                }
                liveCountdown
                warning
                action
                storageProblem
            }
        }
    }
    @ViewBuilder private var liveCountdown: some View {
        if access.isCounting {
            TimelineView(.periodic(from: .now, by: 1)) { _ in countdown }
        } else { countdown }
    }
    @ViewBuilder private var countdown: some View {
        let seconds = max(0, Int(ceil(access.remaining)))
        let digits = String(format: "%02d:%02d", seconds / 60, seconds % 60)
        if compact {
            HStack(spacing: 16) {
                Text(digits).font(.system(size: 29, weight: .semibold, design: .rounded)).monospacedDigit()
                    .accessibilityLabel("\(seconds / 60) minutes \(seconds % 60) seconds left today")
                VStack(alignment: .leading, spacing: 4) {
                    Text(state).font(.system(size: 12, weight: .medium))
                    Text("Resets at \(access.budget.resetsAt.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
        } else {
            let fraction = min(1, max(0, access.remaining / access.budget.totalSeconds))
            let radius = dialDiameter / 2
            ZStack {
                Circle().stroke(GateTheme.line, lineWidth: 3).accessibilityHidden(true)
                ForEach(0..<12, id: \.self) { tick in
                    Capsule().fill(GateTheme.secondary.opacity(0.5))
                        .frame(width: 1, height: (tick % 3 == 0 ? 7 : 4) * min(1.5, dialScale))
                        .offset(y: -(radius - 14 * min(1.5, dialScale))).rotationEffect(.degrees(Double(tick) * 30))
                        .accessibilityHidden(true)
                }
                if access.isCounting {
                    Circle().trim(from: 0, to: fraction)
                        .stroke(GateTheme.blue, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90)).accessibilityHidden(true)
                    Circle().fill(GateTheme.blue).frame(width: 6, height: 6)
                        .offset(y: -radius).rotationEffect(.degrees(fraction * 360)).accessibilityHidden(true)
                }
                if access.remaining > 0 {
                    Circle().fill(GateTheme.blue).frame(width: 6, height: 6).offset(y: -radius).accessibilityHidden(true)
                }
                VStack(spacing: 9 * min(1.6, dialScale)) {
                    Text(state).font(.system(size: labelSize, weight: .medium))
                        .foregroundStyle(access.isCounting ? GateTheme.blue : GateTheme.secondary)
                    Text(digits).font(.system(size: dialDiameter * 0.23, weight: .medium)).monospacedDigit().tracking(-2)
                        .accessibilityLabel("\(seconds / 60) minutes \(seconds % 60) seconds left today")
                    Text("remaining today").font(.system(size: labelSize)).foregroundStyle(.secondary)
                    if access.isCounting {
                        Text("Ends at \(min(access.budget.resetsAt, Date().addingTimeInterval(access.remaining)).formatted(date: .omitted, time: .shortened))")
                            .font(.system(size: max(10, labelSize - 1))).foregroundStyle(.secondary)
                    }
                }
            }.frame(width: dialDiameter, height: dialDiameter).padding(4)
        }
    }
    @ViewBuilder private var action: some View {
        if access.accessStarted {
            Button { access.endAccess() } label: {
                Label("End access", systemImage: "stop.fill")
                    .font(.system(size: compact ? 12 : 14, weight: .semibold)).frame(maxWidth: .infinity)
            }.buttonStyle(GateButtonStyle(primary: true))
        } else {
            Button { store.startDailyAccess() } label: {
                Label("Start access", systemImage: "play.fill")
                    .font(.system(size: compact ? 12 : 14, weight: .semibold)).frame(maxWidth: .infinity)
            }.buttonStyle(GateButtonStyle(primary: true))
                .disabled(!access.canStart || store.normalAccess || store.needsRecovery)
        }
    }
    private var appStrip: some View {
        VStack(spacing: 13) {
            Rectangle().fill(GateTheme.line).frame(height: 1)
            HStack(spacing: 9) {
                ForEach(Array(apps.prefix(5))) { app in
                    MacAppIcon(app: app).help(app.name).accessibilityHidden(false).accessibilityLabel(app.name)
                }
                if apps.count > 5 {
                    Text("+\(apps.count - 5)").font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary).accessibilityLabel("\(apps.count - 5) more blocked apps")
                }
            }.frame(maxWidth: .infinity).accessibilityElement(children: .contain).accessibilityLabel("Included blocked apps")
            HStack(spacing: 6) {
                Text("Resets at \(access.budget.resetsAt.formatted(date: .omitted, time: .shortened))")
                Text("·").accessibilityHidden(true)
                Label(store.normalAccess ? "Websites available" : "Websites stay protected", systemImage: store.normalAccess ? "checkmark.shield" : "lock.shield")
                Button { store.requestTemporaryAccess(settings: true) } label: { Image(systemName: "gearshape") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Daily allowance settings")
                    .accessibilityLabel("Daily allowance settings")
            }.font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(width: min(availableSize.width, 440))
    }
    @ViewBuilder private var warning: some View {
        if access.remaining > 0 && access.remaining <= 60 {
            Text("One minute or less left today").font(.system(size: 10, weight: .medium)).foregroundStyle(.orange)
        }
    }
    @ViewBuilder private var storageProblem: some View {
        if !access.issue.isEmpty {
            Text(access.issue).font(.system(size: 10)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
            if access.issue.hasPrefix("Daily allowance could not be saved.") {
                Button("Retry storage") { access.retryStorage() }.buttonStyle(GateButtonStyle())
            }
        }
    }
}
