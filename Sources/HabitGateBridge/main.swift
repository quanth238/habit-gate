import Foundation
import AppKit
import GateCore

let input = FileHandle.standardInput
let output = FileHandle.standardOutput
let executable = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let bundle = executable.deletingLastPathComponent().deletingLastPathComponent()
let idFile = bundle.appendingPathComponent("Resources/extension-id.txt")
let extensionID = (try? String(contentsOf: idFile, encoding: .utf8).trimmingCharacters(in: .whitespacesAndNewlines)) ?? ""
guard !extensionID.isEmpty, CommandLine.arguments.count > 1,
      CommandLine.arguments[1] == "chrome-extension://\(extensionID)/" else { exit(1) }

func readExactly(_ count: Int) -> Data? {
    var data = Data()
    while data.count < count {
        guard let chunk = try? input.read(upToCount: count - data.count), !chunk.isEmpty else { return nil }
        data.append(chunk)
    }
    return data
}
struct Request: Decodable {
    var command: String
    var clientID: String?
    var privateAccess: Bool?
    var permissionsOK: Bool?
    var label: String?
    var missingDomains: [String]?
    var checkedDomains: [String]?
    var extensionVersion: String?
    var rulesOK: Bool?
    var permissionIssue: String?
    var testedAt: Date?
    var testPassed: Bool?
}
struct Response: Encodable {
    var snapshot: GateSnapshot
    var configured: Bool
    var hostAvailable: Bool = true
}
while let header = readExactly(4) {
    let length = header.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self).littleEndian }
    guard length > 0, length <= 65536, let bytes = readExactly(Int(length)),
          let request = try? GateFiles.decoder().decode(Request.self, from: bytes),
          ["getState", "refresh", "openHabitify", "report"].contains(request.command) else { exit(1) }
    let now = Date()
    if let id = request.clientID, (16...64).contains(id.count), id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }) {
        var client = BrowserClient(id: id, seenAt: now, privateAccess: request.privateAccess ?? false,
                                   permissionsOK: request.permissionsOK ?? false)
        client.label = request.label.map { String($0.filter { !$0.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }.prefix(60)) }
        client.missingDomains = request.missingDomains.flatMap { $0.isEmpty ? [] : try? DomainRules.validated($0) }
        client.checkedDomains = request.checkedDomains.flatMap { try? DomainRules.validated($0) }
        client.extensionVersion = request.extensionVersion.map { String($0.prefix(32)) }
        client.permissionIssue = request.permissionIssue.map { String($0.prefix(240)) }
        client.rulesOK = request.rulesOK; client.testedAt = request.testedAt; client.testPassed = request.testPassed
        try? GateFiles.write(client, "\(id).json", root: GateFiles.root.appendingPathComponent("clients"))
    }
    if NSRunningApplication.runningApplications(withBundleIdentifier: "me.habitgate.app").isEmpty {
        NSWorkspace.shared.open(bundle.deletingLastPathComponent())
    }
    if request.command == "refresh" {
        DistributedNotificationCenter.default().postNotificationName(.init(GateFiles.refreshNotification), object: nil, userInfo: nil, deliverImmediately: true)
    }
    if request.command == "openHabitify" {
        if let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "co.vuvo.habitify") {
            NSWorkspace.shared.open(app)
        } else { NSWorkspace.shared.open(URL(string: "https://app.habitify.me/")!) }
    }
    let loaded = ConfigurationRepository.load()
    var snapshot = ConfigurationRepository.snapshot(for: loaded, cached: GateFiles.read(GateSnapshot.self, "snapshot.json"), now: now)
    if !GateFiles.writable() {
        snapshot.access = "blocked"
        snapshot.reason = "Local storage needs attention. Open Habit Gate on your Mac; access stays locked."
        snapshot.syncError = "Unable to verify writable local storage. Free disk space or restore write access."
    }
    let response = Response(snapshot: snapshot, configured: loaded.configuration.active != nil || loaded.needsRecovery)
    guard let encoded = try? GateFiles.encoder().encode(response), encoded.count < 1_000_000 else { exit(1) }
    var size = UInt32(encoded.count).littleEndian
    output.write(Data(bytes: &size, count: 4)); output.write(encoded)
}
