import SwiftUI
import AppKit
import GateCore

// Local, adaptive colors keep the interface native without images or background animation.
enum GateTheme {
    static let blue = Color(nsColor: adaptive(light: 0x2164F3, dark: 0x729CFF))
    static let buttonBlue = Color(red: 0.13, green: 0.36, blue: 0.93)
    static let canvas = Color(nsColor: adaptive(light: 0xF8F9FC, dark: 0x17191F))
    static let sidebar = Color(nsColor: adaptive(light: 0xF0F2F7, dark: 0x1D2028))
    static let card = Color(nsColor: adaptive(light: 0xFFFFFF, dark: 0x222630))
    static let inset = Color(nsColor: adaptive(light: 0xF4F6FA, dark: 0x2B303C))
    static let hero = Color(nsColor: adaptive(light: 0xEAF1FF, dark: 0x242F48))
    static let line = Color(nsColor: adaptive(light: 0xE3E7EF, dark: 0x363D4B))
    static let secondary = Color(nsColor: .secondaryLabelColor)
    static let green = Color(nsColor: adaptive(light: 0x23794B, dark: 0x79D5A5))

    private static func adaptive(light: UInt32, dark: UInt32) -> NSColor {
        NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: Double((hex >> 16) & 255) / 255,
                           green: Double((hex >> 8) & 255) / 255,
                           blue: Double(hex & 255) / 255, alpha: 1)
        }
    }
}

struct GateCard<Content: View>: View {
    var padding: CGFloat = 20
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(GateTheme.card, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(GateTheme.line, lineWidth: 1))
    }
}

struct GateBrand: View {
    var compact = false
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.shield.fill")
                .font(.system(size: compact ? 25 : 31, weight: .medium))
                .foregroundStyle(GateTheme.blue).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text("Habit Gate").font(.system(size: compact ? 16 : 18, weight: .bold))
                if !compact { Text("A little focus. Every day.").font(.system(size: 10)).foregroundStyle(.secondary) }
            }
        }
    }
}

struct GateOverline: View {
    var text: String
    var body: some View {
        Text(text.uppercased()).font(.system(size: 10, weight: .semibold))
            .tracking(1.1).foregroundStyle(.secondary)
    }
}

struct GatePill: View {
    var text: String
    var symbol = "lock.shield.fill"
    var positive = false
    var body: some View {
        Label(text, systemImage: symbol).font(.system(size: 11, weight: .medium))
            .foregroundStyle(positive ? GateTheme.green : GateTheme.blue)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background((positive ? GateTheme.green : GateTheme.blue).opacity(0.09), in: RoundedRectangle(cornerRadius: 7))
    }
}

struct GateButtonStyle: ButtonStyle {
    var primary = false
    @Environment(\.isEnabled) private var enabled
    @Environment(\.isFocused) private var focused
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        configuration.label.font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 15).padding(.vertical, 11)
            .foregroundStyle(primary ? Color.white : Color.primary)
            .background(primary ? GateTheme.buttonBlue : GateTheme.inset, in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(primary ? Color.clear : GateTheme.line))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(focused ? GateTheme.blue : Color.clear, lineWidth: 2).padding(-3))
            .opacity(enabled ? (configuration.isPressed ? 0.72 : 1) : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: 9))
    }
}

struct GateProgress: View {
    var snapshot: GateSnapshot
    var body: some View {
        let total = min(12, max(1, snapshot.dueCount))
        HStack(spacing: 4) {
            ForEach(0..<total, id: \.self) { index in
                RoundedRectangle(cornerRadius: 3)
                    .fill(Double(index) / Double(total) < fraction ? GateTheme.blue : GateTheme.line)
                    .frame(height: 6)
            }
        }.accessibilityElement(children: .ignore)
            .accessibilityLabel("\(snapshot.completedCount) of \(snapshot.dueCount) essentials complete")
    }
    private var fraction: Double {
        guard snapshot.dueCount > 0 else { return 0 }
        return Double(snapshot.completedCount) / Double(snapshot.dueCount)
    }
}

struct GateRing: View {
    var snapshot: GateSnapshot
    var body: some View {
        ZStack {
            Circle().stroke(GateTheme.line, lineWidth: 7)
            Circle().trim(from: 0, to: snapshot.dueCount == 0 ? 0 : Double(snapshot.completedCount) / Double(snapshot.dueCount))
                .stroke(GateTheme.blue, style: StrokeStyle(lineWidth: 7, lineCap: .round)).rotationEffect(.degrees(-90))
            if snapshot.dueCount == 0 {
                VStack(spacing: 4) {
                    Image(systemName: snapshot.access == "allowed" ? "moon" : "ellipsis").font(.system(size: 21)).foregroundStyle(GateTheme.blue)
                    Text(snapshot.access == "allowed" ? "rest day" : "checking").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            } else {
                VStack(spacing: 2) {
                    Text("\(snapshot.completedCount)/\(snapshot.dueCount)").font(.system(size: 20, weight: .semibold, design: .rounded)).monospacedDigit()
                    Text("complete").font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
        }.frame(width: 80, height: 80).accessibilityHidden(true)
    }
}

struct GateHabitRow: View {
    var habit: HabitState
    var number: Int
    var compact = false
    private var completed: Bool { habit.status == "completed" }
    private var problem: Bool { habit.status == "configuration" }
    private var stateText: String {
        if problem { return "Needs attention" }
        if !habit.due { return "Rest day" }
        switch habit.status {
        case "completed": return "Complete"
        case "skipped": return "Skipped · still required"
        case "failed": return "Failed · still required"
        case "inprogress", "none": return "Not complete"
        default: return "Not verified"
        }
    }
    private var detailText: String {
        if habit.due && !["inprogress", "none", "completed", "configuration"].contains(habit.status) {
            return stateText + (habit.detail.isEmpty ? "" : " · \(habit.detail)")
        }
        return habit.detail.isEmpty ? stateText : habit.detail
    }
    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(completed ? GateTheme.green.opacity(0.12) : GateTheme.inset)
                if completed || problem || !habit.due {
                    Image(systemName: completed ? "checkmark" : problem ? "exclamationmark" : "moon")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(completed ? GateTheme.green : problem ? Color.orange : GateTheme.secondary)
                } else { Text("\(number)").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary) }
            }.frame(width: 30, height: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(habit.name).font(.system(size: compact ? 12 : 13, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detailText)
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !compact {
                Text(stateText).font(.system(size: 10, weight: .medium))
                    .foregroundStyle(completed ? GateTheme.green : problem ? Color.orange : GateTheme.secondary)
                    .fixedSize().padding(.horizontal, 8).padding(.vertical, 5)
                    .background(GateTheme.inset, in: RoundedRectangle(cornerRadius: 6))
            }
        }.padding(.vertical, compact ? 11 : 8)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(number). \(habit.name). \(habit.detail)")
            .accessibilityValue(stateText)
    }
}

struct GateSyncStatus: View {
    @ObservedObject var store: GateStore
    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 7) {
            Circle().fill(store.snapshot.isWeekendDayOff || (store.hasKey && store.snapshot.syncError == nil && store.snapshot.lastSyncedAt != nil) ? GateTheme.green : Color.orange)
                .frame(width: 6, height: 6).accessibilityHidden(true)
            Text(store.snapshot.isWeekendDayOff ? "Weekend day off · No habit checks required" : store.isLoadingCredentials ? "Waiting for macOS Keychain…" : !store.hasKey ? "Habitify connection needed" : store.isSyncing ? "Checking Habitify…" : store.snapshot.syncError != nil ? "Sync needs attention" :
                 store.snapshot.lastSyncedAt.map { "Verified at \($0.formatted(date: .omitted, time: .shortened))" } ?? "Waiting for verification")
                .font(.system(size: 11)).foregroundStyle(.secondary)
        }.help(store.snapshot.isWeekendDayOff ? "Your local weekend schedule permits access without waiting for Habitify." : store.credentialNotice ?? store.snapshot.syncError ?? "Changes on other devices appear after reaching Habitify’s cloud.")
    }
}

struct GateNotice: View {
    var text: String
    var symbol = "info.circle"
    var warning = false
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol).foregroundStyle(warning ? Color.orange : GateTheme.blue)
            Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }.font(.system(size: 11)).padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(warning ? Color.orange.opacity(0.08) : GateTheme.hero.opacity(0.6), in: RoundedRectangle(cornerRadius: 10))
    }
}

@MainActor enum GatePresentation {
    static func date(_ raw: String, long: Bool = false) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: raw) else { return raw }
        formatter.dateFormat = long ? "EEEE, d MMMM" : "d MMM"
        return formatter.string(from: date)
    }
    static func headline(_ store: GateStore) -> String {
        if store.configuration.active == nil { return "Make room for what matters." }
        if store.snapshot.isWeekendDayOff { return "A little room to recharge." }
        if store.snapshot.access == "allowed" { return store.snapshot.dueCount == 0 ? "A little room to recharge." : "Your effort. Your time." }
        if store.snapshot.habits.contains(where: { $0.status == "configuration" }) { return "Let’s check your essentials." }
        return "Make room for what matters."
    }
    static func status(_ store: GateStore) -> String {
        if store.configuration.active == nil { return "Setup needed" }
        if store.snapshot.isWeekendDayOff { return "Weekend day off" }
        if store.temporaryAccess.grant() != nil { return "App time available · sites locked" }
        return store.snapshot.access == "allowed" ? "Distractions unlocked" : "Distractions locked"
    }
    static func summary(_ store: GateStore) -> String {
        if store.configuration.active == nil { return "Connect Habitify and choose your daily essentials." }
        if store.snapshot.isWeekendDayOff { return "No habit restrictions on Saturday and Sunday. Weekday rules resume Monday at 4 AM." }
        if store.snapshot.access == "allowed" { return "Your selected sites and apps are available until 4 AM." }
        if store.snapshot.habits.isEmpty { return store.snapshot.reason }
        return "\(store.snapshot.remainingCount) essential\(store.snapshot.remainingCount == 1 ? "" : "s") left before social time."
    }
}
