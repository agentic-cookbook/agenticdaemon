import AppKit
import Foundation
import DaemonKit

/// Renders the top-of-menu health status: daemon reachable / not reachable,
/// version, uptime, strategy name/kind/unit count.
public struct HealthMenuSection: MenuSection {
    public let daemonName: String

    public init(daemonName: String) {
        self.daemonName = daemonName
    }

    public func items(snapshot: MenuSnapshot) -> [NSMenuItem] {
        guard snapshot.isReachable, let health = snapshot.health else {
            return [MenuBarKitHelpers.disabledItem("● \(daemonName) not running")]
        }

        let title = "\(daemonName)  ·  uptime \(MenuBarKitHelpers.formatUptime(health.uptimeSeconds))"
        var items: [NSMenuItem] = [MenuBarKitHelpers.disabledItem(title)]

        let strat = health.strategy
        let unitCount = strat.workUnits.count
        let unitSuffix = unitCount == 1 ? "" : "s"
        items.append(MenuBarKitHelpers.infoItem(
            label: "Strategy",
            value: "\(strat.kind) \"\(strat.name)\" (\(unitCount) unit\(unitSuffix))",
            indent: 0
        ))
        return items
    }
}
