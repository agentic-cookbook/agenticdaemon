import AppKit
import Foundation
import DaemonKit

/// Renders timing-strategy work units from the generic `StrategySnapshot`
/// inside ``HealthStatus``. Finds the first `timing`-kind child (or the
/// top-level strategy if it's `timing`) and lists its units.
///
/// Optional `onTrigger` closure renders per-unit "Trigger Now" actions.
/// If nil, units are shown as passive info items.
public struct TimingStrategyMenuSection: MenuSection {
    public let onTrigger: (@Sendable (String) -> Void)?

    public init(onTrigger: (@Sendable (String) -> Void)? = nil) {
        self.onTrigger = onTrigger
    }

    public func items(snapshot: MenuSnapshot) -> [NSMenuItem] {
        guard let strategy = findTimingStrategy(snapshot.health?.strategy) else { return [] }
        guard !strategy.workUnits.isEmpty else { return [] }

        var items: [NSMenuItem] = [MenuBarKitHelpers.headerItem("JOBS (\(strategy.workUnits.count))")]
        for unit in strategy.workUnits.sorted(by: { $0.name < $1.name }) {
            items.append(makeItem(unit))
        }
        return items
    }

    private func makeItem(_ unit: WorkUnitSnapshot) -> NSMenuItem {
        let marker = markerFor(unit.state)
        let suffix = suffixFor(unit)
        let title = "\(marker) \(unit.name)   \(suffix)"

        guard let onTrigger else {
            return MenuBarKitHelpers.disabledItem(title)
        }

        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        let header = MenuBarKitHelpers.disabledItem(unit.name)
        submenu.addItem(header)
        submenu.addItem(MenuBarKitHelpers.infoItem(label: "State", value: unit.state.rawValue))
        submenu.addItem(MenuBarKitHelpers.infoItem(label: "Failures", value: "\(unit.consecutiveFailures)"))
        if unit.isBlocklisted {
            submenu.addItem(MenuBarKitHelpers.infoItem(label: "Blacklisted", value: "Yes"))
        }
        submenu.addItem(.separator())
        let unitName = unit.name
        submenu.addItem(BlockMenuItem(title: "Trigger Now") {
            onTrigger(unitName)
        })
        item.submenu = submenu
        return item
    }

    private func markerFor(_ state: WorkUnitSnapshot.WorkUnitState) -> String {
        switch state {
        case .running:     "●"
        case .idle:        "●"
        case .disabled:    "○"
        case .blocklisted: "⚠"
        }
    }

    private func suffixFor(_ unit: WorkUnitSnapshot) -> String {
        switch unit.state {
        case .running:
            return "running…"
        case .disabled:
            return "disabled"
        case .blocklisted:
            return "blacklisted"
        case .idle:
            guard let next = unit.nextActivation else { return "idle" }
            let secs = Int(max(0, next.timeIntervalSinceNow))
            return secs < 60 ? "next: \(secs)s" : "next: \(secs / 60)m"
        }
    }

    /// Find the first timing-kind strategy in a snapshot tree (DFS).
    private func findTimingStrategy(_ snap: StrategySnapshot?) -> StrategySnapshot? {
        guard let snap else { return nil }
        if snap.kind == TimingStrategy.kind { return snap }
        for child in snap.children {
            if let found = findTimingStrategy(child) { return found }
        }
        return nil
    }
}
