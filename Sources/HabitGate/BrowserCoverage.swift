import GateCore

// seenAt is only a liveness heartbeat, not a visible coverage change.
func sameBrowserCoverage(_ lhs: [BrowserClient], _ rhs: [BrowserClient]) -> Bool {
    func sorted(_ clients: [BrowserClient]) -> [BrowserClient] {
        clients.sorted {
            if $0.id != $1.id { return $0.id < $1.id }
            if $0.permissionsOK != $1.permissionsOK { return !$0.permissionsOK }
            return !$0.privateAccess && $1.privateAccess
        }
    }
    return sorted(lhs).elementsEqual(sorted(rhs)) {
        var a = $0, b = $1
            a.seenAt = .distantPast; b.seenAt = .distantPast
            return a == b
    }
}
