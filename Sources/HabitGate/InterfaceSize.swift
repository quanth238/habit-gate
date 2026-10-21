import SwiftUI
import AppKit

enum InterfaceSize: String, CaseIterable, Identifiable {
    case compact, standard, large
    static let preferenceKey = "interfaceSize"
    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var scale: CGFloat {
        switch self {
        case .compact: return 0.9
        case .standard: return 1
        case .large: return 1.1
        }
    }
    var percentage: String { "\(Int((scale * 100).rounded()))%" }
}

// Appearance is immediate and separate from protection rules and the daily ledger.
@MainActor final class InterfacePreferences: ObservableObject {
    @Published private(set) var size: InterfaceSize
    private let defaults: UserDefaults
    var didChange: (() -> Void)?
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        size = defaults.string(forKey: InterfaceSize.preferenceKey).flatMap(InterfaceSize.init(rawValue:)) ?? .standard
    }
    func select(_ size: InterfaceSize) {
        guard self.size != size else { return }
        defaults.set(size.rawValue, forKey: InterfaceSize.preferenceKey)
        self.size = size
        didChange?()
    }
}

// Scaling alone only changes drawing bounds. Compensate the layout proposal too,
// so scrolling, hit testing and the footer use the actual available window area.
struct ScaledInterface<Content: View>: View {
    var scale: CGFloat
    @ViewBuilder var content: () -> Content
    var body: some View {
        GeometryReader { viewport in
            content()
                .frame(width: viewport.size.width / scale, height: viewport.size.height / scale)
                .scaleEffect(scale, anchor: .topLeading)
                .frame(width: viewport.size.width, height: viewport.size.height, alignment: .topLeading)
        }.background(GateTheme.canvas)
    }
}

struct MainWindowView: View {
    @ObservedObject var store: GateStore
    @ObservedObject var interface: InterfacePreferences
    var body: some View {
        ScaledInterface(scale: interface.size.scale) {
            SettingsView(store: store, interface: interface)
        }
    }
}

struct InterfaceSizeSettingsView: View {
    @ObservedObject var interface: InterfacePreferences
    var body: some View {
        GateCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 9) {
                    Text("Interface size").font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Label("Fixed across displays", systemImage: "lock")
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                }
                Picker("Interface size", selection: Binding(get: { interface.size }, set: { interface.select($0) })) {
                    ForEach(InterfaceSize.allCases) { size in
                        Text("\(size.title) · \(size.percentage)").tag(size)
                    }
                }.pickerStyle(.segmented).labelsHidden().accessibilityLabel("Interface size")
                Text("Your choice is saved and stays the same on your Mac and external display. Applies immediately to this window.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

@MainActor extension NSWindow {
    func applyInterfaceSize(_ size: InterfaceSize) {
        let scale = size.scale
        let screenSize = (self.screen ?? NSScreen.main)?.visibleFrame.size ?? NSSize(width: 880, height: 680)
        let minimum = NSSize(width: min(880 * scale, screenSize.width), height: min(680 * scale, screenSize.height))
        self.minSize = minimum
        // Keep a user's larger or full-screen window. Grow a smaller window only
        // when its chosen preset needs room, keeping its top edge anchored.
        guard !self.styleMask.contains(.fullScreen) else { return }
        var frame = self.frame
        frame.size.width = min(frame.width, screenSize.width)
        frame.size.height = min(frame.height, screenSize.height)
        let height = max(frame.height, minimum.height)
        frame.origin.y -= height - frame.height
        frame.size = NSSize(width: max(frame.width, minimum.width), height: height)
        if let screen = self.screen {
            frame.origin.x = min(max(frame.origin.x, screen.visibleFrame.minX), screen.visibleFrame.maxX - frame.width)
            frame.origin.y = min(max(frame.origin.y, screen.visibleFrame.minY), screen.visibleFrame.maxY - frame.height)
        }
        if frame != self.frame { self.setFrame(frame, display: true) }
    }
}
