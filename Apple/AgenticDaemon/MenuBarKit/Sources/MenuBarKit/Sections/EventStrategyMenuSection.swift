import AppKit
import Foundation
import DaemonKit

/// Renders event-strategy status: a header listing the strategy's work units
/// (from the handler's snapshot), and an optional "Open Stream…" quick action
/// clients can wire to an external tool (Terminal, CLI, etc).
public struct EventStrategyMenuSection: MenuSection {
    public let onOpenStream: (@Sendable () -> Void)?

    public init(onOpenStream: (@Sendable () -> Void)? = nil) {
        self.onOpenStream = onOpenStream
    }

    public func items(snapshot: MenuSnapshot) -> [NSMenuItem] {
        guard let strategy = findEventStrategy(snapshot.health?.strategy) else { return [] }

        var items: [NSMenuItem] = [
            MenuBarKitHelpers.headerItem("EVENTS — \(strategy.name)")
        ]
        for unit in strategy.workUnits {
            let marker = unit.state == .running ? "●" : "○"
            items.append(MenuBarKitHelpers.infoItem(
                label: "\(marker) \(unit.name)",
                value: unit.state.rawValue
            ))
        }
        if let onOpenStream {
            items.append(BlockMenuItem(title: "Open Event Stream…", action: onOpenStream))
        }
        return items
    }

    private func findEventStrategy(_ snap: StrategySnapshot?) -> StrategySnapshot? {
        guard let snap else { return nil }
        if snap.kind == EventStrategy.kind { return snap }
        for child in snap.children {
            if let found = findEventStrategy(child) { return found }
        }
        return nil
    }
}
