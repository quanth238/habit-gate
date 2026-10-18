import SwiftUI
import AppKit
import UniformTypeIdentifiers
import GateCore

private typealias AppViewState<Value> = SwiftUI.State<Value>

struct MacAppsSettingsView: View {
    @ObservedObject var store: GateStore
    var onContinue: (() -> Void)? = nil
    @AppViewState private var catalog: [BlockedApp] = []
    @AppViewState private var selected = Set<String>()
    @AppViewState private var filter = ""
    @AppViewState private var error = ""
    private var visible: [BlockedApp] {
        catalog.filter { filter.isEmpty || $0.name.localizedCaseInsensitiveContains(filter) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("Search installed apps", text: $filter).textFieldStyle(.plain)
                }.font(.system(size: 12)).padding(11)
                    .background(GateTheme.card, in: RoundedRectangle(cornerRadius: 9))
                    .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(GateTheme.line))
                Button("Add app…") { addApp() }.buttonStyle(GateButtonStyle())
            }
            HStack {
                GatePill(text: "\(selected.count) selected", symbol: "app.badge")
                Spacer()
                Text("Watching \(store.configuration.active?.apps.count ?? 0) · Hide verified: \(store.guardedAppIDs.count)").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            GateCard(padding: 8) {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(visible.sorted { lhs, rhs in
                            if selected.contains(lhs.id) != selected.contains(rhs.id) { return selected.contains(lhs.id) }
                            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
                        }) { app in
                            Toggle(isOn: Binding(get: { selected.contains(app.id) }, set: {
                                if $0 { selected.insert(app.id) } else { selected.remove(app.id) }
                            })) {
                                HStack(spacing: 11) {
                                    MacAppIcon(app: app).frame(width: 30, height: 30)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(app.name).font(.system(size: 12, weight: .medium))
                                        if selected.contains(app.id) || store.configuration.active?.apps.contains(where: { $0.id == app.id }) == true {
                                            Text(rowStatus(app)).font(.system(size: 10)).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                }.padding(.leading, 5)
                            }.toggleStyle(.checkbox).padding(12)
                            Divider().overlay(GateTheme.line).padding(.horizontal, 12)
                        }
                        if visible.isEmpty { Text("No apps match your search.").font(.system(size: 12)).foregroundStyle(.secondary).padding(25) }
                    }
                }.frame(height: 300)
            }
            GateNotice(text: "While blocked, selected apps are hidden when they open or come forward. Their background sessions and drafts stay intact. Habitify and essential system apps stay accessible.", symbol: "lock.shield")
            GateNotice(text: timing, symbol: "clock")
            if !store.appProtectionIssue.isEmpty { GateNotice(text: store.appProtectionIssue, warning: true) }
            if !error.isEmpty { GateNotice(text: error, symbol: "exclamationmark.circle", warning: true) }
            Button(store.configuration.active == nil ? "Save apps & review setup" : "Save apps") {
                do { try store.saveApps(catalog.filter { selected.contains($0.id) }); error = ""; if store.configuration.active == nil { onContinue?() } }
                catch { self.error = error.localizedDescription }
            }.buttonStyle(GateButtonStyle(primary: true))
        }.onAppear { load() }
    }
    private func rowStatus(_ app: BlockedApp) -> String {
        let active = store.configuration.active?.apps.contains(where: { $0.id == app.id }) == true
        if active && !selected.contains(app.id) { return "Removal at 4 AM · still watched today" }
        if store.guardedAppIDs.contains(app.id) { return "Window hide verified this session" }
        return active ? "Watching · hide not yet tested this session" : store.configuration.active == nil ? "Setup choice · starts after review" : "Added when saved"
    }
    private var timing: String {
        let current = Set(store.configuration.active?.apps.map(\.id) ?? [])
        let desired = Set(store.configuration.pending?.policy.apps.map(\.id) ?? store.configuration.active?.apps.map(\.id) ?? [])
        let removed = current.subtracting(desired).count
        var text = store.configuration.active == nil ? "Optional: select apps now. All setup choices start together after review." : "New apps apply when saved. Removals take effect \(HabitDay(now: Date()).end.formatted(date: .abbreviated, time: .shortened))."
        if removed > 0, let pending = store.configuration.pending {
            text += " \(removed) app(s) stay protected until \(pending.effectiveAt.formatted(date: .abbreviated, time: .shortened))."
        }
        return text
    }
    private func load() {
        let saved = store.desiredPolicy.apps
        var all = Dictionary(uniqueKeysWithValues: MacAppCatalog.installed().map { ($0.id, $0) })
        for app in saved + (store.configuration.active?.apps ?? []) { all[app.id] = app }
        catalog = all.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        selected = Set(saved.map(\.id))
    }
    private func addApp() {
        let panel = NSOpenPanel()
        panel.title = "Choose an app to block"
        panel.allowedContentTypes = [.applicationBundle]
        panel.allowsMultipleSelection = true
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            guard let app = MacAppCatalog.app(at: url) else {
                error = "Choose an app bundle. Habitify, Habit Gate and essential system apps stay accessible."
                continue
            }
            if !catalog.contains(where: { $0.id == app.id }) { catalog.append(app) }
            selected.insert(app.id)
        }
        catalog.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}

private struct MacAppIcon: View {
    var app: BlockedApp
    private var symbol: String {
        switch app.bundleID.lowercased() {
        case "com.hnc.discord": return "bubble.left.and.bubble.right.fill"
        case "com.nvidia.gfnpc.mall": return "gamecontroller.fill"
        case "ru.keepcoder.telegram": return "paperplane.fill"
        case "net.whatsapp.whatsapp": return "phone.bubble.fill"
        case "com.vng.zalo": return "bubble.left.fill"
        default: return "app.fill"
        }
    }
    var body: some View {
        // System symbols avoid decoding and retaining full-resolution application icons.
        Image(systemName: symbol).font(.system(size: 16)).foregroundStyle(GateTheme.blue)
            .frame(width: 30, height: 30).background(GateTheme.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .accessibilityHidden(true)
    }
}

struct BlockedMacAppView: View {
    @ObservedObject var store: GateStore
    var dismiss: () -> Void
    private var allowed: Bool { store.snapshot.access == "allowed" && store.snapshot.valid(at: Date()) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                GateBrand(compact: true)
                Spacer()
                Text("ESSENTIALS FIRST").font(.system(size: 9, weight: .semibold)).tracking(1).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 11) {
                GatePill(text: allowed ? "Ready when you are" : "\(store.blockedApp?.name ?? "This app") is blocked",
                         symbol: allowed ? "checkmark.shield.fill" : "lock.shield.fill", positive: allowed)
                Text(allowed ? "Your effort. Your time." : "Your habits come first.")
                    .font(.system(size: 29, weight: .bold)).tracking(-0.7).fixedSize(horizontal: false, vertical: true)
                Text(allowed ? "Your selected apps are available until the next 4 AM reset." :
                     "This app’s window is temporarily hidden. Complete your essentials in Habitify to open it; its session keeps running.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if store.snapshot.dueCount > 0 {
                    HStack {
                        GateProgress(snapshot: store.snapshot)
                        Text("\(store.snapshot.completedCount)/\(store.snapshot.dueCount)").font(.system(size: 11, weight: .medium)).monospacedDigit()
                    }.padding(.top, 4)
                }
            }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                .background(GateTheme.hero, in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 8) {
                GateOverline(text: "Your essentials")
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(store.snapshot.habits.enumerated()), id: \.element.id) { index, habit in
                            if index > 0 { Divider().overlay(GateTheme.line) }
                            GateHabitRow(habit: habit, number: index + 1, compact: true)
                        }
                        if store.snapshot.habits.isEmpty {
                            Text(store.snapshot.reason).font(.system(size: 12)).foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true).padding(.vertical, 10)
                        }
                    }.padding(.horizontal, 14)
                }.frame(height: min(230, max(60, CGFloat(store.snapshot.habits.count) * 66)))
                    .background(GateTheme.card, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(GateTheme.line))
            }
            if let error = store.snapshot.syncError { GateNotice(text: error, symbol: "wifi.exclamationmark", warning: true) }
            if let notice = store.credentialNotice { GateNotice(text: notice, symbol: "key") }
            HStack {
                GateSyncStatus(store: store)
                Spacer()
                Text("\(GatePresentation.date(store.snapshot.habitDate)) · Resets 4 AM").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            HStack(spacing: 10) {
                if allowed {
                    Button { store.openBlockedApp(); dismiss() } label: {
                        HStack { Text("Continue to \(store.blockedApp?.name ?? "app")"); Spacer(); Image(systemName: "arrow.right") }
                    }.buttonStyle(GateButtonStyle(primary: true))
                } else {
                    Button { store.openHabitify() } label: {
                        HStack { Text("Open Habitify"); Spacer(); Image(systemName: "arrow.up.right") }
                    }.buttonStyle(GateButtonStyle(primary: true))
                }
                Button { store.tick(forceSync: true) } label: { Label("Sync now", systemImage: "arrow.clockwise") }
                    .buttonStyle(GateButtonStyle()).disabled(store.isSyncing || !store.hasKey)
            }
            HStack {
                Text("Your app session stays intact.").font(.system(size: 10)).foregroundStyle(.secondary)
                Spacer()
                Button("Return to work") { dismiss() }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(GateTheme.blue)
            }
        }.padding(26).frame(width: 520).background(GateTheme.canvas).tint(GateTheme.blue)
    }
}
