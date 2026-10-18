import SwiftUI
import GateCore

struct PolicySummaryView: View {
    @ObservedObject var store: GateStore
    var body: some View {
        GateCard(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Active essentials · today").font(.system(size: 13, weight: .semibold))
                Text(names(store.configuration.active?.habitIDs ?? []))
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                if let pending = store.configuration.pending, Set(pending.policy.habitIDs) != Set(store.configuration.active?.habitIDs ?? []) {
                    Divider()
                    Text("Scheduled · \(pending.effectiveAt.formatted(date: .abbreviated, time: .shortened))")
                        .font(.system(size: 12, weight: .semibold))
                    Text(names(pending.policy.habitIDs)).font(.system(size: 12)).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
    private func names(_ ids: [String]) -> String {
        ids.map { id in store.catalog.first(where: { $0.id == id })?.name ?? store.snapshot.habits.first(where: { $0.id == id })?.name ?? "Unavailable habit — review selection" }.joined(separator: " · ")
    }
}

struct ChromeCoverageView: View {
    @ObservedObject var store: GateStore
    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            Text("Detected Chrome profiles").font(.system(size: 14, weight: .semibold))
            if store.clients.isEmpty {
                GateNotice(text: "No recent extension report. Open Habit Gate in the Chrome profile you use. Selection alone does not verify website protection.", warning: true)
            }
            ForEach(store.clients, id: \.id) { client in
                VStack(alignment: .leading, spacing: 7) {
                    Text(client.label?.isEmpty == false ? client.label! : "Chrome profile \(client.id.prefix(6))")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Native connection: responding · Extension \(client.extensionVersion ?? "needs update")")
                    Text(client.permissionsOK ? "Website permissions: granted for the reported domain list" :
                         "Missing website access: \(client.missingDomains?.joined(separator: ", ") ?? "open the extension to check")")
                    if let issue = client.permissionIssue, !issue.isEmpty { Text(issue).foregroundStyle(.orange) }
                    Text(client.rulesOK == true ? "Network rules and site guards: installed" : "Network rules: not yet verified — reload the updated extension")
                    Text(client.privateAccess ? "Private windows: enabled for this profile" : "Private windows: not protected")
                    Text(client.testPassed == true ? "Live website redirect: passed \(client.testedAt?.formatted(date: .abbreviated, time: .shortened) ?? "")" : "Live website redirect: not verified in this session")
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true).padding(13)
                    .frame(maxWidth: .infinity, alignment: .leading).background(GateTheme.inset, in: RoundedRectangle(cornerRadius: 10))
            }
            Button("Check protection status") { store.checkProtection() }.buttonStyle(GateButtonStyle())
            Text("Open the extension and choose Test protection for a live redirect check while access is locked. Profile labels are set in the extension; Chrome does not share its account/profile name with Habit Gate. Other profiles and browsers are not protected automatically.")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}
