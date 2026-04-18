import AppKit
import Foundation
import DaemonKit

/// Generic status-bar app driver. Polls the daemon's `/health` on a timer,
/// assembles a menu via ``MenuComposer``, and keeps an `NSStatusItem`
/// up-to-date.
///
/// Typical `main.swift`:
///
///     let delegate = StatusBarAppDelegate(
///         http: DaemonHTTPClient(baseURL: "http://127.0.0.1:22847"),
///         menuIcon: "⚙",
///         composer: MenuComposer(sections: [
///             HealthMenuSection(daemonName: "mydaemon"),
///             TimingStrategyMenuSection(onTrigger: { /* XPC call */ }),
///             ControlsMenuSection(onQuit: { NSApp.terminate(nil) })
///         ])
///     )
///     let app = NSApplication.shared
///     app.delegate = delegate
///     app.setActivationPolicy(.accessory)
///     app.run()
@MainActor
public final class StatusBarAppDelegate: NSObject, NSApplicationDelegate {
    private let http: DaemonHTTPClient
    private let composer: MenuComposer
    private let menuIcon: String
    private let menuImage: NSImage?
    private let refreshInterval: TimeInterval
    private let userInfoProvider: (@Sendable (DaemonHTTPClient) async -> [String: any Sendable])?

    private var statusItem: NSStatusItem?
    private var timer: Timer?
    private var unreachableBadge: NSImageView?

    public init(
        http: DaemonHTTPClient,
        composer: MenuComposer,
        menuIcon: String = "⚙",
        menuImage: NSImage? = nil,
        refreshInterval: TimeInterval = 5,
        userInfoProvider: (@Sendable (DaemonHTTPClient) async -> [String: any Sendable])? = nil
    ) {
        self.http = http
        self.composer = composer
        self.menuIcon = menuIcon
        self.menuImage = menuImage
        self.refreshInterval = refreshInterval
        self.userInfoProvider = userInfoProvider
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let menuImage {
            item.button?.image = menuImage
        } else {
            item.button?.title = menuIcon
        }
        item.menu = composer.build(snapshot: MenuSnapshot(isReachable: false))
        self.statusItem = item

        refresh()

        let timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    /// Force a refresh. Safe to call from tests via a direct-constructed
    /// delegate (without launching the app).
    ///
    /// Reachability is determined by whether `/health` returned any response
    /// (HTTP 200), not by whether the body decodes into ``HealthStatus``.
    /// Some daemons emit a different health schema; those should still show
    /// as reachable when their HTTP server responds.
    public func refresh() {
        let http = self.http
        let composer = self.composer
        let userInfoProvider = self.userInfoProvider
        Task { [weak self] in
            let healthData = http.getData("/health")
            let isReachable = healthData != nil
            let health: HealthStatus? = healthData.flatMap {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .iso8601
                return try? decoder.decode(HealthStatus.self, from: $0)
            }
            let userInfo: [String: any Sendable] = await userInfoProvider?(http) ?? [:]
            await MainActor.run { [weak self] in
                guard let self else { return }
                let snapshot = MenuSnapshot(
                    isReachable: isReachable,
                    health: health,
                    userInfo: userInfo
                )
                self.statusItem?.menu = composer.build(snapshot: snapshot)
                self.updateIcon(isReachable: isReachable)
            }
        }
    }

    private func updateIcon(isReachable: Bool) {
        guard let button = statusItem?.button else { return }
        if let menuImage {
            button.image = menuImage
            button.title = ""
            updateUnreachableBadge(on: button, visible: !isReachable)
        } else {
            button.title = isReachable ? menuIcon : "●"
        }
    }

    /// Show or hide a yellow `exclamationmark.circle.fill` overlay in the
    /// lower-right of the status bar button. We keep the base image as a
    /// template (so AppKit handles light/dark inversion) and layer the badge
    /// as a subview, which preserves the yellow tint without fighting the
    /// menubar's appearance heuristics.
    private func updateUnreachableBadge(on button: NSStatusBarButton, visible: Bool) {
        if visible {
            if unreachableBadge == nil {
                let badge = NSImageView()
                badge.translatesAutoresizingMaskIntoConstraints = false
                let config = NSImage.SymbolConfiguration(pointSize: 10, weight: .heavy)
                badge.image = NSImage(
                    systemSymbolName: "exclamationmark.circle.fill",
                    accessibilityDescription: "daemon unreachable"
                )?.withSymbolConfiguration(config)
                badge.contentTintColor = .systemYellow
                button.addSubview(badge)
                NSLayoutConstraint.activate([
                    badge.widthAnchor.constraint(equalToConstant: 11),
                    badge.heightAnchor.constraint(equalToConstant: 11),
                    badge.trailingAnchor.constraint(equalTo: button.trailingAnchor, constant: -1),
                    badge.bottomAnchor.constraint(equalTo: button.bottomAnchor, constant: -1),
                ])
                unreachableBadge = badge
            }
            unreachableBadge?.isHidden = false
        } else {
            unreachableBadge?.isHidden = true
        }
    }
}
