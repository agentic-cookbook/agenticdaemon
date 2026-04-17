import Testing
import Foundation
import AppKit
@testable import MenuBarKit
@testable import DaemonKit

// MARK: - Helpers

private func snapshot(
    reachable: Bool = true,
    strategy: StrategySnapshot? = nil,
    userInfo: [String: any Sendable] = [:]
) -> MenuSnapshot {
    let defaultStrategy = StrategySnapshot(name: "daemon", kind: "timing", workUnits: [])
    let health: HealthStatus? = reachable ? HealthStatus(
        status: "ok",
        version: "1.0.0",
        uptimeSeconds: 60,
        strategy: strategy ?? defaultStrategy
    ) : nil
    return MenuSnapshot(
        isReachable: reachable,
        health: health,
        userInfo: userInfo
    )
}

// MARK: - MenuComposer

@Suite("MenuComposer", .serialized)
@MainActor
struct MenuComposerTests {

    @Test("builds a menu from sections in order")
    func buildsInOrder() {
        let composer = MenuComposer(sections: [
            TitleSection(title: "First"),
            TitleSection(title: "Second")
        ])
        let menu = composer.build(snapshot: snapshot())
        let titles = menu.items.map(\.title)
        // Separator appears between sections
        #expect(titles == ["First", "", "Second"])
        #expect(menu.items.count == 3)
    }

    @Test("skips sections that return no items — no dangling separators")
    func skipsEmptySections() {
        let composer = MenuComposer(sections: [
            TitleSection(title: "A"),
            EmptySection(),
            TitleSection(title: "B")
        ])
        let menu = composer.build(snapshot: snapshot())
        let titles = menu.items.map(\.title)
        #expect(titles == ["A", "", "B"])
    }

    @Test("all-empty composer yields an empty menu")
    func allEmpty() {
        let composer = MenuComposer(sections: [EmptySection(), EmptySection()])
        let menu = composer.build(snapshot: snapshot())
        #expect(menu.items.isEmpty)
    }
}

// MARK: - HealthMenuSection

@Suite("HealthMenuSection", .serialized)
@MainActor
struct HealthMenuSectionTests {

    @Test("shows stopped header when daemon is not reachable")
    func unreachable() {
        let section = HealthMenuSection(daemonName: "mydaemon")
        let items = section.items(snapshot: snapshot(reachable: false))
        #expect(items.count == 1)
        #expect(items[0].title.contains("mydaemon not running"))
    }

    @Test("shows running header with uptime when reachable")
    func reachable() {
        let section = HealthMenuSection(daemonName: "mydaemon")
        let items = section.items(snapshot: snapshot(reachable: true))
        #expect(items.count >= 1)
        #expect(items[0].title.contains("mydaemon"))
        #expect(items[0].title.contains("uptime"))
    }
}

// MARK: - TimingStrategyMenuSection

@Suite("TimingStrategyMenuSection", .serialized)
@MainActor
struct TimingStrategyMenuSectionTests {

    @Test("hidden when no timing strategy in snapshot")
    func noTimingHides() {
        let section = TimingStrategyMenuSection()
        let items = section.items(snapshot: snapshot(strategy: StrategySnapshot(name: "e", kind: "event", workUnits: [])))
        #expect(items.isEmpty)
    }

    @Test("renders JOBS header + unit rows")
    func rendersJobs() {
        let strat = StrategySnapshot(name: "t", kind: "timing", workUnits: [
            WorkUnitSnapshot(name: "a", state: .idle, nextActivation: Date(timeIntervalSinceNow: 30)),
            WorkUnitSnapshot(name: "b", state: .running)
        ])
        let section = TimingStrategyMenuSection()
        let items = section.items(snapshot: snapshot(strategy: strat))
        #expect(items.count == 3)
        #expect(items[0].title.contains("JOBS"))
        #expect(items[1].title.contains("a"))
        #expect(items[2].title.contains("b"))
    }

    @Test("with onTrigger provided, unit items expose submenu")
    func submenuOnTrigger() {
        let strat = StrategySnapshot(name: "t", kind: "timing", workUnits: [
            WorkUnitSnapshot(name: "job1", state: .idle, nextActivation: Date(timeIntervalSinceNow: 30))
        ])
        let section = TimingStrategyMenuSection(onTrigger: { _ in })
        let items = section.items(snapshot: snapshot(strategy: strat))
        let jobItem = items.last!
        #expect(jobItem.submenu != nil)
        let submenuTitles = jobItem.submenu?.items.map(\.title) ?? []
        #expect(submenuTitles.contains(where: { $0.contains("Trigger Now") }))
    }

    @Test("finds nested timing strategy inside composite")
    func findsNested() {
        let inner = StrategySnapshot(name: "inner", kind: "timing", workUnits: [
            WorkUnitSnapshot(name: "x", state: .idle)
        ])
        let outer = StrategySnapshot(name: "outer", kind: "composite", workUnits: [], children: [inner])
        let section = TimingStrategyMenuSection()
        let items = section.items(snapshot: snapshot(strategy: outer))
        #expect(items.count == 2)
        #expect(items[1].title.contains("x"))
    }
}

// MARK: - EventStrategyMenuSection

@Suite("EventStrategyMenuSection", .serialized)
@MainActor
struct EventStrategyMenuSectionTests {

    @Test("hidden when no event strategy")
    func hidesWhenNone() {
        let section = EventStrategyMenuSection()
        let strat = StrategySnapshot(name: "t", kind: "timing", workUnits: [])
        let items = section.items(snapshot: snapshot(strategy: strat))
        #expect(items.isEmpty)
    }

    @Test("renders header + units")
    func rendersEventUnits() {
        let strat = StrategySnapshot(name: "ingest", kind: "event", workUnits: [
            WorkUnitSnapshot(name: "handler", state: .idle)
        ])
        let section = EventStrategyMenuSection()
        let items = section.items(snapshot: snapshot(strategy: strat))
        #expect(items.count == 2)
        #expect(items[0].title.contains("EVENTS"))
    }

    @Test("includes Open Stream item when onOpenStream provided")
    func openStreamItem() {
        let strat = StrategySnapshot(name: "ingest", kind: "event", workUnits: [])
        let section = EventStrategyMenuSection(onOpenStream: {})
        let items = section.items(snapshot: snapshot(strategy: strat))
        #expect(items.contains(where: { $0.title.contains("Open Event Stream") }))
    }
}

// MARK: - ControlsMenuSection

@Suite("ControlsMenuSection", .serialized)
@MainActor
struct ControlsMenuSectionTests {

    @Test("shows Start when unreachable")
    func startWhenUnreachable() {
        let section = ControlsMenuSection(
            onStart: {},
            onQuit: {}
        )
        let items = section.items(snapshot: snapshot(reachable: false))
        #expect(items.contains(where: { $0.title == "Start Daemon" }))
        #expect(!items.contains(where: { $0.title == "Stop Daemon" }))
    }

    @Test("shows Restart/Stop when reachable")
    func stopWhenReachable() {
        let section = ControlsMenuSection(
            onStop: {},
            onRestart: {},
            onQuit: {}
        )
        let items = section.items(snapshot: snapshot(reachable: true))
        #expect(items.contains(where: { $0.title == "Restart Daemon" }))
        #expect(items.contains(where: { $0.title == "Stop Daemon" }))
    }

    @Test("always includes Quit")
    func alwaysQuit() {
        let section = ControlsMenuSection(onQuit: {})
        let unreachable = section.items(snapshot: snapshot(reachable: false))
        let reachable = section.items(snapshot: snapshot(reachable: true))
        #expect(unreachable.last?.title == "Quit")
        #expect(reachable.last?.title == "Quit")
    }
}

// MARK: - BlockMenuItem

@Suite("BlockMenuItem")
@MainActor
struct BlockMenuItemTests {

    @Test("invokes block when action fires")
    func invokesBlock() async {
        let fired = LockBool()
        let item = BlockMenuItem(title: "t") { fired.set(true) }
        _ = item.target?.perform(item.action)
        #expect(fired.value == true)
    }
}

// MARK: - Test sections

private struct TitleSection: MenuSection {
    let title: String
    func items(snapshot: MenuSnapshot) -> [NSMenuItem] {
        [NSMenuItem(title: title, action: nil, keyEquivalent: "")]
    }
}

private struct EmptySection: MenuSection {
    func items(snapshot: MenuSnapshot) -> [NSMenuItem] { [] }
}

private final class LockBool: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = false
    var value: Bool { lock.withLock { _value } }
    func set(_ v: Bool) { lock.withLock { _value = v } }
}
