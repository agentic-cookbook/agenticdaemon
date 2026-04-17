import AppKit
import Foundation
import DaemonKit

/// A bundle of menu items a client contributes to the status-bar menu.
///
/// Sections are rendered top-to-bottom in the order registered with
/// ``MenuComposer``. Each section decides whether it's visible based on the
/// current snapshot (return an empty array to hide).
///
/// Typical built-ins:
/// - ``HealthMenuSection`` (header with status + uptime)
/// - ``TimingStrategySection`` (timing strategy work units)
/// - ``EventStrategySection`` (event strategy indicators)
/// - ``CrashesMenuSection`` (recent crashes)
/// - ``DaemonControlsSection`` (Start/Stop/Restart + Quit)
///
/// Daemons also implement their own sections for domain-specific views
/// (e.g. stenographer's "Sessions" list).
public protocol MenuSection: Sendable {
    /// Produce menu items for this refresh. Return empty to hide the section.
    /// The renderer inserts a separator after each non-empty section.
    func items(snapshot: MenuSnapshot) -> [NSMenuItem]
}

/// Point-in-time data passed to every section's render.
///
/// Extensible: sections that need richer data can subclass ``MenuSnapshot``
/// or attach data to ``userInfo``. The basic fields cover most needs.
public struct MenuSnapshot: Sendable {
    /// `true` if the daemon's `/health` responded successfully on the last refresh.
    public let isReachable: Bool
    /// Parsed `/health` response if reachable.
    public let health: HealthStatus?
    /// Arbitrary per-daemon data sections can read (e.g. crash lists,
    /// session lists). Keyed by a string the section and fetcher agree on.
    public let userInfo: [String: any Sendable]
    public let now: Date

    public init(
        isReachable: Bool,
        health: HealthStatus? = nil,
        userInfo: [String: any Sendable] = [:],
        now: Date = Date.now
    ) {
        self.isReachable = isReachable
        self.health = health
        self.userInfo = userInfo
        self.now = now
    }
}

/// Assembles an ``NSMenu`` from a declared list of sections.
///
/// Stateless — call `build(snapshot:)` on every refresh. Sections that
/// render no items are skipped (no dangling separators).
public final class MenuComposer: @unchecked Sendable {
    public let sections: [any MenuSection]

    public init(sections: [any MenuSection]) {
        self.sections = sections
    }

    public func build(snapshot: MenuSnapshot) -> NSMenu {
        let menu = NSMenu()
        var first = true
        for section in sections {
            let items = section.items(snapshot: snapshot)
            guard !items.isEmpty else { continue }
            if !first { menu.addItem(.separator()) }
            for item in items { menu.addItem(item) }
            first = false
        }
        return menu
    }
}

/// NSMenuItem subclass that dispatches to a closure on click.
/// Exposed publicly because client sections need to build actionable items.
public final class BlockMenuItem: NSMenuItem {
    private let block: @Sendable () -> Void

    public init(title: String, action block: @escaping @Sendable () -> Void) {
        self.block = block
        super.init(title: title, action: #selector(invoke), keyEquivalent: "")
        self.target = self
    }

    public required init(coder: NSCoder) { fatalError("not implemented") }

    @objc private func invoke() { block() }
}

/// Small rendering helpers sections can share.
public enum MenuBarKitHelpers {

    public static func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    public static func headerItem(_ title: String) -> NSMenuItem {
        disabledItem(title)
    }

    public static func infoItem(label: String, value: String, indent: Int = 1) -> NSMenuItem {
        let item = NSMenuItem(title: "\(label):  \(value)", action: nil, keyEquivalent: "")
        item.isEnabled = false
        item.indentationLevel = indent
        return item
    }

    public static func formatUptime(_ seconds: TimeInterval) -> String {
        let s = Int(seconds)
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m \(s % 60)s" }
        return "\(s / 3600)h \(s % 3600 / 60)m"
    }
}
