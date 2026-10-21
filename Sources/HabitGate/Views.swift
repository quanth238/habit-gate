import SwiftUI
import AppKit
import GateCore

private typealias LocalState<Value> = SwiftUI.State<Value>

struct TodayView: View {
    @ObservedObject var store: GateStore
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                GateBrand(compact: true)
                Spacer()
                Button { store.requestTemporaryAccess(settings: true) } label: { Image(systemName: "gearshape").frame(width: 28, height: 28) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help("Open Habit Gate settings")
                    .accessibilityLabel("Open Habit Gate settings")
            }.padding(.bottom, 20)
            Text(GatePresentation.date(store.snapshot.habitDate, long: true)).font(.system(size: 11)).foregroundStyle(.secondary)
            Text(GatePresentation.headline(store).replacingOccurrences(of: "Make room for what matters.", with: "Make room for\nwhat matters."))
                .font(.system(size: 25, weight: .bold))
                .tracking(-0.6).fixedSize(horizontal: false, vertical: true).padding(.top, 6)
            GatePill(text: GatePresentation.status(store), symbol: store.snapshot.access == "allowed" ? "checkmark.shield.fill" : "lock.shield.fill", positive: store.snapshot.access == "allowed")
                .padding(.top, 12)
            if store.snapshot.dueCount > 0 {
                GateProgress(snapshot: store.snapshot).padding(.top, 17)
                Text("\(store.snapshot.completedCount) of \(store.snapshot.dueCount) essentials complete")
                    .font(.system(size: 11)).foregroundStyle(.secondary).padding(.top, 7)
            }
            Divider().overlay(GateTheme.line).padding(.vertical, 16)
            if !store.normalAccess && !(store.configuration.active?.apps.isEmpty ?? true) {
                DailyAccessCard(store: store, access: store.temporaryAccess, compact: true)
            } else {
            HStack {
                GateOverline(text: "Your essentials")
                Spacer()
                Text(store.snapshot.dueCount == 0 && store.snapshot.access == "allowed" ? "Rest day" : "Complete in Habitify")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }.padding(.bottom, 8)
            if store.snapshot.access == "allowed" {
                Text(store.snapshot.dueCount == 0 ? "Verified rest day. No essentials are scheduled." : "All scheduled essentials are complete.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 12)
            } else if store.snapshot.habits.isEmpty {
                Text(store.snapshot.reason).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.vertical, 12)
            } else {
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(store.snapshot.habits.filter { $0.due && $0.status != "completed" }.enumerated()), id: \.element.id) { index, habit in
                            GateHabitRow(habit: habit, number: index + 1, compact: true)
                                .padding(.horizontal, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(GateTheme.card, in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(GateTheme.line))
                        }
                    }.padding(1)
                }.frame(height: min(268, CGFloat(store.snapshot.remainingCount) * 70))
            }
            }
            Divider().overlay(GateTheme.line).padding(.vertical, 15)
            GateSyncStatus(store: store)
            Label(chromeSummary + " · \(store.configuration.active?.apps.count ?? 0) Mac apps", systemImage: "laptopcomputer")
                .font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 7)
            if let notice = store.credentialNotice {
                Text(notice).font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 7)
            }
            if let error = store.snapshot.syncError {
                Text(error).font(.system(size: 10)).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true).padding(.top, 7)
            }
            if !store.appProtectionIssue.isEmpty {
                Text(store.appProtectionIssue).font(.system(size: 10)).foregroundStyle(.orange).padding(.top, 5)
            }
            HStack(spacing: 9) {
                Button { store.configuration.active == nil ? store.showSettings?() : store.openHabitify() } label: {
                    HStack { Text(store.configuration.active == nil ? "Set up protection" : "Open Habitify"); Spacer(); Image(systemName: "arrow.right") }
                }.buttonStyle(GateButtonStyle(primary: true))
                Button { store.tick(forceSync: true) } label: {
                    Image(systemName: "arrow.clockwise").frame(width: 15)
                }.buttonStyle(GateButtonStyle()).disabled(store.isSyncing || !store.hasKey)
                    .help("Sync now").accessibilityLabel(store.isSyncing ? "Syncing" : "Sync now")
            }.padding(.top, 17)
            HStack {
                Text("Habit day \(GatePresentation.date(store.snapshot.habitDate)) · Resets at 4 AM")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                Menu { Button("Quit Habit Gate") { NSApp.terminate(nil) } } label: { Image(systemName: "ellipsis") }
                    .menuStyle(.borderlessButton).fixedSize().accessibilityLabel("More options")
            }.padding(.top, 14)
                .help("Before 4 AM, record late check-ins against this habit date in Habitify.")
        }.padding(22).frame(width: 390).background(GateTheme.canvas).tint(GateTheme.blue).onAppear { store.tick() }
    }
    private var chromeSummary: String {
        if store.clients.isEmpty { return "Chrome not connected" }
        return store.clients.allSatisfy { $0.permissionsOK && $0.rulesOK == true } ? "Reported Chrome rules ready" : "Chrome needs attention"
    }
}

private enum SettingsPage: String, CaseIterable, Identifiable {
    case overview, habits, websites, apps, temporary, connection, preferences, review
    var id: String { rawValue }
    var title: String {
        switch self {
        case .temporary: return "Temporary access"
        case .review: return "Review & activate"
        case .overview: return "Overview"
        case .habits: return "Essential habits"
        case .websites: return "Websites"
        case .apps: return "Mac apps"
        case .connection: return "Connection"
        case .preferences: return "Settings"
        }
    }
    var symbol: String {
        switch self {
        case .temporary: return "timer"
        case .review: return "checkmark.shield"
        case .overview: return "house.fill"
        case .habits: return "checklist"
        case .websites: return "globe"
        case .apps: return "laptopcomputer"
        case .connection: return "link"
        case .preferences: return "gearshape"
        }
    }
    var headline: String {
        switch self {
        case .temporary: return "Temporary access"
        case .review: return "Your rules. No surprises."
        case .overview: return "Today"
        case .habits: return "Start with what matters."
        case .websites: return "Give your attention space."
        case .apps: return "Keep distractions in their place."
        case .connection: return "Your habits, connected."
        case .preferences: return "Make yourself at home."
        }
    }
    var subtitle: String {
        switch self {
        case .temporary: return "A little time for what you need."
        case .review: return "Review all choices and verify one Chrome profile before protection begins."
        case .overview: return "Access, Habitify verification and protection coverage."
        case .habits: return "Choose the habits that unlock your selected websites and apps."
        case .websites: return "Selected domains and their subdomains stay blocked until you’re done."
        case .apps: return "Your Mac apps follow the same essentials and daily reset."
        case .connection: return "Habitify records your progress. Habit Gate keeps you focused."
        case .preferences: return "Small settings for a quieter daily routine."
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: GateStore
    @LocalState private var apiKey = ""
    @LocalState private var selection = Set<String>()
    @LocalState private var domains = ""
    @LocalState private var page = SettingsPage.temporary
    @LocalState private var localError = ""
    @LocalState private var confirmDeleteKey = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(GateTheme.line).frame(width: 1)
            VStack(spacing: 0) {
                GeometryReader { viewport in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            if !store.storageIssue.isEmpty {
                                GateNotice(text: store.storageIssue, symbol: "externaldrive.badge.exclamationmark", warning: true)
                                if store.needsRecovery {
                                    Button("Restore saved rules") { store.restoreSavedRules(); loadDraft() }.buttonStyle(GateButtonStyle(primary: true))
                                    Button("Choose rules backup…") { store.chooseRecoveryBackup(); loadDraft() }.buttonStyle(GateButtonStyle())
                                    Button("Show support folder") { NSWorkspace.shared.open(store.root) }.buttonStyle(GateButtonStyle())
                                }
                            }
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 9) {
                                    if page != .temporary { GateOverline(text: page == .overview ? "Your focus, protected" : page.title) }
                                    Text(page.headline).font(.system(size: page == .temporary ? 25 : 27, weight: page == .temporary ? .semibold : .bold)).tracking(-0.7)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(page.subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                if page == .temporary {
                                    Spacer(minLength: 12)
                                    GatePill(text: "\(store.temporaryAccess.budget.todayMinutes) min daily", symbol: "clock")
                                }
                            }
                            switch page {
                            case .temporary: TemporaryAccessView(store: store, access: store.temporaryAccess).frame(maxHeight: .infinity)
                            case .review: activationReview
                            case .overview: overview
                            case .habits: habits
                            case .websites: websites
                            case .apps: MacAppsSettingsView(store: store, onContinue: { page = .review })
                            case .connection: connection
                            case .preferences: preferences
                            }
                            if !localError.isEmpty { GateNotice(text: localError, symbol: "exclamationmark.circle", warning: true) }
                        }.padding(page == .temporary ? 24 : 30).frame(maxWidth: 850, alignment: .leading).frame(maxWidth: .infinity)
                            .frame(minHeight: page == .temporary ? viewport.size.height : 0, alignment: .top)
                    }
                }
                footer
            }.background(GateTheme.canvas)
        }.tint(GateTheme.blue).frame(minWidth: 880, idealWidth: 980, minHeight: 648, idealHeight: 748)
             .onAppear {
                 loadDraft()
                 if store.temporaryAccessRequest != nil { page = store.temporaryAccessOpensSettings ? .preferences : .temporary; store.temporaryAccessRequest = nil }
                 else if store.configuration.active == nil { page = store.hasKey ? .habits : .connection }
             }
             .onChange(of: store.temporaryAccessRequest) { request in
                 if request != nil { page = store.temporaryAccessOpensSettings ? .preferences : .temporary; store.temporaryAccessRequest = nil }
             }
            .confirmationDialog("Delete the saved Habitify API key from this Mac?", isPresented: $confirmDeleteKey) {
                Button("Delete API key and disconnect", role: .destructive) { Task { await store.disconnect(deleteKey: true) } }
                Button("Cancel", role: .cancel) { }
            } message: { Text("Your rules stay active and access remains locked until you reconnect. Habitify data and the Orange Pi bridge are not changed.") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            GateBrand(compact: true).padding(.horizontal, 20).padding(.top, 32).padding(.bottom, 30)
            VStack(spacing: 5) {
                ForEach(SettingsPage.allCases.filter { $0 != .review || store.configuration.active == nil }) { item in
                    if item == .connection { Divider().padding(.vertical, 13).padding(.horizontal, 12) }
                    Button {
                        page = item; localError = ""
                    } label: {
                        HStack(spacing: 11) {
                            Image(systemName: item.symbol).font(.system(size: 15)).frame(width: 22)
                            Text(item.title).font(.system(size: 12, weight: page == item ? .semibold : .regular))
                            Spacer(minLength: 0)
                        }.foregroundStyle(page == item ? GateTheme.blue : Color.primary.opacity(0.8))
                            .padding(.horizontal, 13).padding(.vertical, 11)
                            .background(page == item ? GateTheme.blue.opacity(0.1) : Color.clear, in: RoundedRectangle(cornerRadius: 9))
                            .contentShape(RoundedRectangle(cornerRadius: 9))
                    }.buttonStyle(.plain).accessibilityValue(page == item ? "Selected" : "")
                }
            }.padding(.horizontal, 12)
            Spacer()
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 7) {
                    Circle().fill(store.hasKey && store.snapshot.syncError == nil ? GateTheme.green : Color.orange).frame(width: 6, height: 6)
                    Text(store.isLoadingCredentials ? "Opening Keychain…" : !store.hasKey ? "Connect Habitify" : store.snapshot.syncError == nil ? "Habitify connected" : "Check connection").font(.system(size: 11, weight: .medium))
                }
                if page != .temporary { Text("Resets daily at 4 AM").font(.system(size: 10)).foregroundStyle(.secondary).padding(.leading, 13) }
            }.padding(22)
        }.frame(width: 210).background(GateTheme.sidebar)
    }
    private var overview: some View {
        VStack(alignment: .leading, spacing: 18) {
            if let notice = store.credentialNotice {
                GateNotice(text: notice, symbol: "key")
                Button("Connection settings") { page = .connection }.buttonStyle(GateButtonStyle())
            }
            HStack(spacing: 20) {
                Image(systemName: store.snapshot.access == "allowed" ? "checkmark.shield.fill" : "lock.shield.fill")
                    .font(.system(size: 38)).foregroundStyle(GateTheme.blue).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 7) {
                    Text(GatePresentation.status(store)).font(.system(size: 25, weight: .bold))
                    Text(GatePresentation.summary(store)).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    if store.configuration.active != nil {
                        Button("Open Habitify") { store.openHabitify() }.buttonStyle(GateButtonStyle(primary: true))
                    } else {
                        Button("Connect & set up") { page = store.hasKey ? .habits : .connection }.buttonStyle(GateButtonStyle(primary: true))
                    }
                }
                Spacer(minLength: 0)
                GateRing(snapshot: store.snapshot)
            }.padding(23).background(GateTheme.hero, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(GateTheme.blue.opacity(0.14)))
            if let error = store.snapshot.syncError {
                GateNotice(text: error, symbol: "wifi.exclamationmark", warning: true)
                Button("Connection & recovery") { page = .connection }.buttonStyle(GateButtonStyle())
            }
            if store.snapshot.habits.contains(where: { $0.status == "configuration" }) {
                Button("Review unavailable essentials") { page = .habits }.buttonStyle(GateButtonStyle())
            }
            if store.clients.isEmpty || store.clients.contains(where: { !$0.permissionsOK || $0.rulesOK != true }) {
                Button("Resolve Chrome coverage") { page = .websites }.buttonStyle(GateButtonStyle())
            }
            if !store.appProtectionIssue.isEmpty { GateNotice(text: store.appProtectionIssue, warning: true) }
            GateCard(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Text("Your protection").font(.system(size: 14, weight: .semibold))
                    HStack(spacing: 10) {
                        protectionTile("Chrome", value: chromeStatus, symbol: "globe", page: .websites)
                        protectionTile("Foreground apps", value: store.appProtectionIssue.isEmpty ? "Watching \(store.configuration.active?.apps.count ?? 0)" : "Needs attention", symbol: "laptopcomputer", page: .apps)
                        protectionTile("Habitify", value: store.isSyncing ? "Checking…" : store.snapshot.syncError != nil ? "Sync error" : store.hasKey ? "Key connected" : "Reconnect", symbol: "link", page: .connection)
                    }
                }
            }
            GateCard(padding: 18) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Today’s essentials").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Text(store.snapshot.dueCount > 0 ? "\(store.snapshot.completedCount) of \(store.snapshot.dueCount)" : store.snapshot.access == "allowed" ? "Rest day" : "Not verified")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                    }.padding(.bottom, 4)
                    if store.snapshot.habits.isEmpty {
                        Text(store.snapshot.reason).font(.system(size: 12)).foregroundStyle(.secondary).padding(.vertical, 12)
                    } else {
                        ForEach(Array(store.snapshot.habits.enumerated()), id: \.element.id) { index, habit in
                            if index > 0 { Divider().overlay(GateTheme.line) }
                            GateHabitRow(habit: habit, number: index + 1)
                        }
                    }
                    Divider().overlay(GateTheme.line)
                    Label("Habit day \(store.snapshot.habitDate) · Next reset \(store.snapshot.expiresAt.formatted(date: .abbreviated, time: .shortened))", systemImage: "calendar")
                        .font(.system(size: 10)).foregroundStyle(.secondary).padding(.top, 4)
                }
            }
            if let pending = store.configuration.pending {
                GateNotice(text: "Saved habit changes and removals begin \(pending.effectiveAt.formatted(date: .abbreviated, time: .shortened)). New websites and apps apply when saved.", symbol: "clock")
            }
        }
    }
    private func protectionTile(_ title: String, value: String, symbol: String, page target: SettingsPage) -> some View {
        Button { page = target } label: {
            HStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 19)).foregroundStyle(GateTheme.blue)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 11, weight: .medium))
                    Text(value).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(GateTheme.inset.opacity(0.65), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(GateTheme.line))
        }.buttonStyle(.plain)
    }
    private var habits: some View {
        let rows = HabitCatalog.pickerRows(store.catalog, selected: selection)
        return VStack(alignment: .leading, spacing: 17) {
            if store.configuration.active != nil { PolicySummaryView(store: store) }
            HStack {
                GatePill(text: "\(selection.count) in your draft", symbol: "checklist")
                Spacer()
                Button("Refresh habits") { store.tick(forceSync: true) }.buttonStyle(GateButtonStyle()).disabled(!store.hasKey || store.isSyncing)
            }
            GateCard(padding: 8) {
                VStack(spacing: 0) {
                    if rows.isEmpty && selection.isEmpty {
                        Text(store.catalog.isEmpty ? "Connect Habitify to load your habits." : "No supported daily habits found. Add an active daily habit in Habitify, then refresh.")
                            .foregroundStyle(.secondary).padding(20)
                    }
                    ForEach(rows) { habit in
                        Toggle(isOn: Binding(get: { selection.contains(habit.id) }, set: { enabled in
                            if enabled { selection.insert(habit.id) } else { selection.remove(habit.id) }
                        })) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(habit.name).font(.system(size: 13, weight: .medium)).fixedSize(horizontal: false, vertical: true)
                                Text(HabitCatalog.selectionDetail(habit))
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }.padding(.leading, 5)
                        }.toggleStyle(.checkbox).padding(13).frame(maxWidth: .infinity, alignment: .leading)
                            .disabled(!habit.supported && !selection.contains(habit.id))
                        if habit.id != rows.last?.id { Divider().overlay(GateTheme.line).padding(.horizontal, 12) }
                    }
                    ForEach(Array(selection.subtracting(Set(store.catalog.map(\.id)))).sorted(), id: \.self) { id in
                        Toggle("Missing habit — remove from next day’s rules", isOn: Binding(get: { selection.contains(id) }, set: { if !$0 { selection.remove(id) } }))
                            .toggleStyle(.checkbox).font(.system(size: 12)).padding(13)
                    }
                }
            }
            Text("New essentials must have an active daily goal. Archived habits and weekly goals can’t be added.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            GateNotice(text: "Start with 2–4 essentials. Every selected habit due today must be completed in Habitify. Partial, skipped and failed check-ins do not unlock access.", symbol: "checkmark.shield")
            habitTiming
            Button(store.configuration.active == nil ? "Save essentials & choose distractions" : "Save habits for next day") { saveRules(habits: true) }
                .buttonStyle(GateButtonStyle(primary: true)).disabled(!store.hasKey || selection.isEmpty)
        }
    }
    private var websites: some View {
        VStack(alignment: .leading, spacing: 17) {
            GateCard {
                VStack(alignment: .leading, spacing: 13) {
                    HStack { Text("Blocked websites").font(.system(size: 14, weight: .semibold)); Spacer(); GatePill(text: "Chrome", symbol: "globe") }
                    Text("One domain per line. Includes its subdomains.").font(.system(size: 11)).foregroundStyle(.secondary)
                    TextEditor(text: $domains).font(.system(size: 13, design: .monospaced)).scrollContentBackground(.hidden)
                        .padding(10).frame(height: 150).background(GateTheme.inset, in: RoundedRectangle(cornerRadius: 9))
                        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(GateTheme.line))
                        .accessibilityLabel("Blocked website domains, one per line")
                    Text("Example: reddit.com").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }
            if let invalid = domainValidation { GateNotice(text: invalid, warning: true) }
            GateCard {
                VStack(alignment: .leading, spacing: 15) {
                    ChromeCoverageView(store: store)
                    DisclosureGroup("Private alpha installation") {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("This local alpha uses an unpacked extension. Public installation is not available yet. In Chrome, open chrome://extensions, enable Developer mode, choose Load unpacked and select the extension folder.")
                                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button("Show extension folder") { store.showExtensionFolder() }.buttonStyle(GateButtonStyle())
                                Button("Copy Chrome address") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString("chrome://extensions", forType: .string) }.buttonStyle(GateButtonStyle())
                            }
                        }.padding(.top, 10)
                    }.font(.system(size: 12))
                }
            }
            websiteTiming
            Button(store.configuration.active == nil ? "Save websites & choose Mac apps" : "Save websites") { saveRules(habits: false) }
                .buttonStyle(GateButtonStyle(primary: true))
                .disabled(domainValidation != nil || (store.configuration.active == nil && (!store.hasKey || selection.isEmpty)))
        }
    }
    private var connection: some View {
        VStack(alignment: .leading, spacing: 17) {
            if let notice = store.credentialNotice {
                GateNotice(text: notice, symbol: "key")
                Button(store.isLoadingCredentials ? "Opening Keychain…" : "Retry saved Keychain connection") {
                    Task { await store.restoreCredentials() }
                }.buttonStyle(GateButtonStyle()).disabled(store.isLoadingCredentials)
            }
            GateCard {
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Image(systemName: "link.circle.fill").font(.system(size: 34)).foregroundStyle(GateTheme.blue)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Habitify").font(.system(size: 16, weight: .semibold))
                            Text(store.hasKey ? "API key saved securely in macOS Keychain" : "Connect once. Keep using Habitify as usual.")
                                .font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if store.hasKey { Image(systemName: "checkmark.seal.fill").foregroundStyle(GateTheme.green) }
                    }
                    Divider().overlay(GateTheme.line)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(store.hasKey ? "Replace API key" : "Habitify API key").font(.system(size: 12, weight: .medium))
                        SecureField("Habitify API key", text: $apiKey,
                                    prompt: Text(store.hasKey ? "••••••••••••" : "Paste your API key here"))
                            .textFieldStyle(.roundedBorder).controlSize(.large).onSubmit { connect() }
                            .help(store.hasKey ? "A key is saved in Keychain. Type a new key only to replace it." : "Paste your Habitify API key here.")
                            .accessibilityHint(store.hasKey ? "API key already saved. Enter a new key only to replace it." : "Enter your Habitify API key.")
                        Text("On your phone: Habitify → Settings → API Credentials. A paid plan is required. Generating a new key revokes the previous one.")
                            .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Button(store.isSyncing ? "Verifying…" : "Verify & save in Keychain") { connect() }
                        .buttonStyle(GateButtonStyle(primary: true)).disabled(apiKey.isEmpty || store.isSyncing)
                }
            }
            HStack {
                if store.configuration.disconnected == true {
                    Button("Reconnect saved key") { Task { await store.reconnectSavedKey() } }.buttonStyle(GateButtonStyle(primary: true))
                } else if store.hasKey {
                    Button("Disconnect") { Task { await store.disconnect(deleteKey: false) } }.buttonStyle(GateButtonStyle())
                }
                Button("Delete API key…", role: .destructive) { confirmDeleteKey = true }.buttonStyle(GateButtonStyle())
            }.disabled(store.isSyncing || store.isLoadingCredentials)
            GateNotice(text: "Your key stays in macOS Keychain. Habit Gate reads your habits and completion; browser extensions never receive the key.", symbol: "lock.shield")
            GateCard {
                VStack(alignment: .leading, spacing: 13) {
                    Text("A simple daily connection").font(.system(size: 14, weight: .semibold))
                    Text("Syncs every 60 seconds while your Mac is awake, plus on launch, wake and network recovery. Progress recorded elsewhere appears after it reaches Habitify’s cloud.")
                        .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    Link("How to get your API key ↗", destination: URL(string: "https://intercom.help/habitify-app/en/articles/6113937-use-habitify-api-v2")!).font(.system(size: 12))
                    Link("Habitify API documentation ↗", destination: URL(string: "https://api-docs.habitify.me/")!).font(.system(size: 12))
                }
            }
        }
    }
    private var preferences: some View {
        VStack(alignment: .leading, spacing: 17) {
            DailyAccessSettingsView(store: store, access: store.temporaryAccess)
            GateCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text("Your daily routine").font(.system(size: 14, weight: .semibold))
                    Toggle(isOn: Binding(get: { store.loginEnabled }, set: { store.setLogin($0) })) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Launch Habit Gate at login").font(.system(size: 13, weight: .medium))
                            Text("Start quietly in the menu bar for this Mac account.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.toggleStyle(.switch).accessibilityLabel("Launch Habit Gate at login")
                    Divider().overlay(GateTheme.line)
                    Toggle(isOn: Binding(get: { store.configuration.notifyOnUnlock }, set: { store.setNotifications($0) })) {
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Celebrate a clear day").font(.system(size: 13, weight: .medium))
                            Text("One notification when your essentials unlock access.").font(.system(size: 11)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }.toggleStyle(.switch).accessibilityLabel("Notify when essentials unlock access")
                }
            }
            GateNotice(text: "Voluntary protection on this Mac: extensions can be removed, and other browsers remain accessible. Mac app windows are hidden while blocked; apps may keep running in the background.", symbol: "info.circle")
            Text("Habit Gate · Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.2.0")")
                .font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
    private var footer: some View {
        VStack(alignment: .leading, spacing: 9) {
            if !store.message.isEmpty && store.message != "Synced with Habitify." {
                Text(store.message).font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }
            HStack(spacing: 12) {
                Button { store.tick(forceSync: true) } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.plain).foregroundStyle(.secondary).disabled(store.isSyncing || !store.hasKey)
                    .help("Sync now (⌘R)").accessibilityLabel("Sync now").keyboardShortcut("r", modifiers: .command)
                GateSyncStatus(store: store)
                Spacer()
                if page == .temporary {
                    Button { store.openHabitify() } label: { Label("Open Habitify", systemImage: "arrow.up.right") }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                } else if page != .overview {
                    Button { store.openHabitify() } label: { Label("Open Habitify", systemImage: "arrow.up.right") }
                        .buttonStyle(GateButtonStyle(primary: page != .temporary))
                }
            }
        }.padding(.horizontal, 27).padding(.vertical, page == .temporary ? 14 : 16)
            .background(page == .temporary ? GateTheme.canvas : GateTheme.card)
            .overlay(alignment: .top) { Rectangle().fill(GateTheme.line).frame(height: 1) }
    }
    private var habitTiming: some View {
        let changed = store.configuration.pending.map { Set($0.policy.habitIDs) != Set(store.configuration.active?.habitIDs ?? []) } ?? false
        let text: String
        if store.configuration.active == nil { text = "Protection starts when you activate these rules." }
        else if changed, let pending = store.configuration.pending {
            text = "Saved habit changes begin \(pending.effectiveAt.formatted(date: .abbreviated, time: .shortened)). Today's essentials stay the same."
        } else { text = "Save takes effect \(HabitDay(now: Date()).end.formatted(date: .abbreviated, time: .shortened)). Today's essentials stay the same." }
        return GateNotice(text: text, symbol: "clock")
    }
    private var websiteTiming: some View {
        let current = Set(store.configuration.active?.domains ?? [])
        let desired = Set(store.configuration.pending?.policy.domains ?? store.configuration.active?.domains ?? [])
        let removed = current.subtracting(desired).count
        var text = "New websites apply when saved. Removals wait until 4 AM. Chrome normally updates within 30 seconds; custom sites need permission."
        if store.configuration.active == nil { text = "Protection starts when you activate these rules." }
        else if removed > 0, let pending = store.configuration.pending {
            text += " \(removed) website(s) stay protected until \(pending.effectiveAt.formatted(date: .abbreviated, time: .shortened))."
        }
        return GateNotice(text: text, symbol: "clock")
    }
    private var domainValidation: String? {
        do {
            _ = try DomainRules.validated(domains.components(separatedBy: CharacterSet(charactersIn: ",\n")).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
            return nil
        } catch { return error.localizedDescription }
    }
    private var activationReview: some View {
        VStack(alignment: .leading, spacing: 17) {
            GateCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Your initial rules start together").font(.system(size: 16, weight: .semibold))
                    Text("Essentials: \(store.desiredPolicy.habitIDs.map { id in store.catalog.first(where: { $0.id == id })?.name ?? "Unavailable habit" }.joined(separator: " · "))")
                    Text("Websites: \(store.desiredPolicy.domains.joined(separator: ", "))")
                    Text("Foreground apps: \(store.desiredPolicy.apps.isEmpty ? "None selected" : store.desiredPolicy.apps.map(\.name).joined(separator: ", "))")
                }.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
            GateNotice(text: "Complete all essentials scheduled for your habit day to unlock distractions. Partial, skipped, failed or missing evidence does not unlock. A verified rest day can unlock.", symbol: "checkmark.shield")
            GateNotice(text: "Habit day: \(HabitDay(now: Date()).date). Next reset: \(HabitDay(now: Date()).end.formatted(date: .abbreviated, time: .shortened)). Before 4 AM, record late check-ins against the previous date in Habitify, whose reset is midnight.", symbol: "clock")
            GateNotice(text: "Later website/app additions apply when saved. Habit edits and removals wait until 4 AM. This is voluntary protection: other browsers and unconfigured profiles remain accessible; app sessions continue in the background.")
            GateCard { ChromeCoverageView(store: store) }
            if !store.readyToActivate { GateNotice(text: "A current Chrome extension must report rules and permissions for your chosen websites before activation. Open Websites for installation and recovery steps.", warning: true) }
            Button("Activate protection & open Today") {
                do { try store.activateSetup(); localError = "" } catch { localError = error.localizedDescription }
            }.buttonStyle(GateButtonStyle(primary: true)).disabled(!store.readyToActivate)
        }
    }
    private var chromeStatus: String {
        if store.clients.isEmpty { return "Not connected" }
        if !store.clients.allSatisfy(\.permissionsOK) { return "Needs permissions" }
        if store.clients.contains(where: { $0.rulesOK != true }) { return "Check extension update" }
        return "Reported rules ready"
    }
    private func loadDraft() {
        let policy = store.desiredPolicy
        selection = Set(policy.habitIDs)
        domains = (policy.domains).joined(separator: "\n")
    }
    private func saveRules(habits: Bool) {
        do {
            if store.configuration.active == nil {
                if habits { try store.saveSetup(ids: selection); page = .websites }
                else { try store.saveSetup(domains: domains); page = .apps }
            }
            else if habits { try store.saveHabits(selection) }
            else { try store.saveWebsites(domains) }
            localError = ""
        } catch { localError = error.localizedDescription }
    }
    private func connect() {
        guard !apiKey.isEmpty else { return }
        Task { if await store.connect(apiKey) { apiKey = ""; localError = ""; if store.configuration.active == nil { page = .habits } } }
    }
}
