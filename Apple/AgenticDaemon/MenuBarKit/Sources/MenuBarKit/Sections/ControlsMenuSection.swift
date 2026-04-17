import AppKit
import Foundation

/// Renders daemon lifecycle controls (Start / Stop / Restart) and a Quit
/// item. Visibility of Start vs Stop/Restart tracks `snapshot.isReachable`.
///
/// Clients supply the closures; this section doesn't assume any particular
/// launchctl / XPC mechanism.
public struct ControlsMenuSection: MenuSection {
    public let onStart: (@Sendable () -> Void)?
    public let onStop: (@Sendable () -> Void)?
    public let onRestart: (@Sendable () -> Void)?
    public let onQuit: @Sendable () -> Void

    public init(
        onStart: (@Sendable () -> Void)? = nil,
        onStop: (@Sendable () -> Void)? = nil,
        onRestart: (@Sendable () -> Void)? = nil,
        onQuit: @escaping @Sendable () -> Void
    ) {
        self.onStart = onStart
        self.onStop = onStop
        self.onRestart = onRestart
        self.onQuit = onQuit
    }

    public func items(snapshot: MenuSnapshot) -> [NSMenuItem] {
        var items: [NSMenuItem] = []
        if snapshot.isReachable {
            if let onRestart {
                items.append(BlockMenuItem(title: "Restart Daemon", action: onRestart))
            }
            if let onStop {
                items.append(BlockMenuItem(title: "Stop Daemon", action: onStop))
            }
        } else if let onStart {
            items.append(BlockMenuItem(title: "Start Daemon", action: onStart))
        }
        items.append(BlockMenuItem(title: "Quit", action: onQuit))
        return items
    }
}
