import AppKit
import Foundation
import Testing
@testable import TorqueController

private func makeSettings() -> PanelSettings {
    let name = "torque-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return PanelSettings(defaults: defaults)
}

@Test func defaultsAreBottomRightHalfSecondAndUnscaled() {
    let settings = makeSettings()
    #expect(settings.corners == [.bottomRight])
    #expect(settings.dwell == 0.5)
    #expect(settings.keepsInScreen)
    #expect(settings.mirrorsCandidates)
    for panel in PanelID.allCases {
        #expect(settings.scale(of: panel) == 1)
    }
    #expect(settings.origin(of: .flick) == nil)
}

@Test func originAndScaleAreRestored() {
    let settings = makeSettings()
    settings.setOrigin(NSPoint(x: 120, y: 340), of: .flick)
    settings.setScale(1.3, of: .flick)
    let restored = PanelSettings(defaults: settings.defaults)
    #expect(restored.origin(of: .flick) == NSPoint(x: 120, y: 340))
    #expect(restored.origin(of: .compact) == nil)
    #expect(restored.scale(of: .flick) == 1.3)
    #expect(restored.scale(of: .qwerty) == 1)
    restored.setOrigin(nil, of: .flick)
    #expect(restored.origin(of: .flick) == nil)
}

@Test func scaleIsClampedToAllowedRange() {
    let settings = makeSettings()
    settings.setScale(3, of: .compact)
    #expect(settings.scale(of: .compact) == 2)
    settings.setScale(0.1, of: .compact)
    #expect(settings.scale(of: .compact) == 0.7)
}

@Test func opacityDefaultsToOpaqueAndIsRestoredPerPanel() {
    let settings = makeSettings()
    for panel in PanelID.allCases {
        #expect(settings.opacity(of: panel) == 1)
    }
    settings.setOpacity(0.5, of: .compact)
    settings.setOpacity(0.75, of: .qwerty)
    let restored = PanelSettings(defaults: settings.defaults)
    #expect(restored.opacity(of: .compact) == 0.5)
    #expect(restored.opacity(of: .flick) == 1)
    #expect(restored.opacity(of: .qwerty) == 0.75)
    #expect(PanelSettings.opacityChoices == [1, 0.9, 0.75, 0.5])
}

@Test func opacityIsClampedToAllowedRange() {
    let settings = makeSettings()
    settings.setOpacity(3, of: .flick)
    #expect(settings.opacity(of: .flick) == 1)
    settings.setOpacity(0.1, of: .flick)
    #expect(settings.opacity(of: .flick) == 0.5)
    settings.setOpacity(0, of: .flick)
    #expect(settings.opacity(of: .flick) == 1)
}

@MainActor @Test func opacityAppliesToPanelsButNotToGuidesOrCandidates() {
    let flick = FlickPanel(origin: .zero, converter: nil, learningURL: URL(fileURLWithPath: "/dev/null"))
    flick.setOpacity(0.5)
    #expect(flick.panel.alphaValue == 0.5)
    #expect(flick.compositionPanel.alphaValue == 0.5)
    #expect(flick.guidePanel.alphaValue == 1)
    #expect(flick.overlayPanel.alphaValue == 1)

    let compact = CompactPanel(origin: .zero, qwertyOrigin: .zero, shortcuts: [])
    compact.setOpacity(0.75)
    compact.qwerty.setOpacity(0.9)
    #expect(compact.panel.alphaValue == 0.75)
    #expect(compact.qwerty.panel.alphaValue == 0.9)
    #expect(compact.radialPanel.alphaValue == 1)
}

/// 項目のアクションを、メニューから選んだときと同じように実行する。
@MainActor private func choose(_ title: String, in item: NSMenuItem?) throws {
    let choice = try #require(item?.submenu?.item(withTitle: title))
    let target = try #require(choice.target as? NSObject)
    target.perform(choice.action, with: choice)
}

@MainActor private func checked(in item: NSMenuItem?) -> [String] {
    (item?.submenu?.items ?? []).filter { $0.state == .on }.map(\.title)
}

@MainActor @Test func gripMenuChangesOnlyThatPanelAndMarksCurrentValue() throws {
    let settings = makeSettings()
    let delegate = AppDelegate(settings: settings)

    var menu = delegate.makePanelMenu(for: .flick)
    #expect(menu.items.map(\.title) == ["不透明度", "倍率"])
    #expect(menu.items[0].submenu?.items.map(\.title) == ["100%", "90%", "75%", "50%"])
    #expect(checked(in: menu.items[0]) == ["100%"])
    #expect(checked(in: menu.items[1]) == ["100%"])

    try choose("50%", in: menu.items[0])
    try choose("130%", in: menu.items[1])
    #expect(settings.opacity(of: .flick) == 0.5)
    #expect(settings.scale(of: .flick) == 1.3)
    #expect(settings.opacity(of: .compact) == 1)
    #expect(settings.scale(of: .qwerty) == 1)

    menu = delegate.makePanelMenu(for: .flick)
    #expect(checked(in: menu.items[0]) == ["50%"])
    #expect(checked(in: menu.items[1]) == ["130%"])
    #expect(checked(in: delegate.makePanelMenu(for: .compact).items[0]) == ["100%"])
}

@MainActor @Test func appMenuHasOpacityForEachPanelAndQuit() throws {
    let settings = makeSettings()
    settings.setOpacity(0.75, of: .qwerty)
    let menu = AppDelegate(settings: settings).makeAppMenu()
    let opacity = try #require(menu.item(withTitle: "パネルの不透明度を変更"))
    #expect(menu.item(withTitle: "パネルの倍率を変更") != nil)
    #expect(opacity.submenu?.items.map(\.title) == ["コンパクト", "フリック", "QWERTY"])
    #expect(checked(in: opacity.submenu?.item(withTitle: "QWERTY")) == ["75%"])
    let quit = try #require(menu.item(withTitle: "TorqueController を終了"))
    #expect(quit.action == #selector(NSApplication.terminate(_:)))
}

@MainActor @Test func rightClickGoesToHandlerAndNotToKeys() throws {
    let panel = FloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 100, height: 100))
    let key = KeyView(label: "a")
    key.frame = panel.contentRect(forFrameRect: panel.frame)
    panel.contentView = key
    var keyBegan = false
    key.onBegin = { _ in keyBegan = true }
    var menuRequests = 0
    FloatingPanel.onRightClick = { _, _ in menuRequests += 1 }
    defer { FloatingPanel.onRightClick = nil }

    let event = try #require(NSEvent.mouseEvent(
        with: .rightMouseDown, location: NSPoint(x: 50, y: 50), modifierFlags: [], timestamp: 0,
        windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
    ))
    panel.sendEvent(event)
    #expect(menuRequests == 1)
    #expect(!keyBegan)
}

@Test func cornersCanBeEmptyOrSeveral() {
    let settings = makeSettings()
    settings.corners = []
    #expect(settings.corners.isEmpty)
    settings.corners = [.topLeft, .bottomRight]
    #expect(settings.corners == [.topLeft, .bottomRight])
}

@Test func offScreenPanelIsNotReachable() {
    let screens = [CGRect(x: 0, y: 0, width: 1440, height: 900)]
    #expect(PanelSettings.isReachable(CGRect(x: 100, y: 100, width: 200, height: 200), screens: screens))
    #expect(!PanelSettings.isReachable(CGRect(x: 2000, y: 100, width: 200, height: 200), screens: screens))
}

@Test func cornerHitTestUsesTolerance() {
    let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
    #expect(ScreenCorner.bottomRight.contains(CGPoint(x: 1439, y: 1), in: frame, tolerance: 6))
    #expect(!ScreenCorner.bottomRight.contains(CGPoint(x: 1400, y: 1), in: frame, tolerance: 6))
    #expect(ScreenCorner.topLeft.contains(CGPoint(x: 1, y: 899), in: frame, tolerance: 6))
}

@Test func dwellFiresOnceAfterDuration() {
    var dwell = CornerDwell(duration: 1)
    var fired = 0
    for _ in 0..<40 where dwell.update(isInCorner: true, delta: 0.05) {
        fired += 1
    }
    #expect(fired == 1)
    #expect(dwell.progress == 0)
}

@Test func dwellResetsWhenLeavingAndReArms() {
    var dwell = CornerDwell(duration: 1)
    _ = dwell.update(isInCorner: true, delta: 0.5)
    #expect(dwell.progress == 0.5)
    _ = dwell.update(isInCorner: false, delta: 0.05)
    #expect(dwell.progress == 0)

    let first = dwell.update(isInCorner: true, delta: 1)
    #expect(first)
    let stillThere = dwell.update(isInCorner: true, delta: 5)
    #expect(!stillThere)
    _ = dwell.update(isInCorner: false, delta: 0.05)
    let again = dwell.update(isInCorner: true, delta: 1)
    #expect(again)
}

@Test func clampKeepsExtentInsideBounds() {
    let bounds = CGRect(x: 0, y: 0, width: 1000, height: 800)
    // パネルは 200×300 で、ガイドが左と下に 50、右に 100 はみ出す
    let extent = CGRect(x: -50, y: -50, width: 350, height: 350)
    #expect(PanelSettings.clampedOrigin(NSPoint(x: 400, y: 300), extent: extent, bounds: bounds) == NSPoint(x: 400, y: 300))
    #expect(PanelSettings.clampedOrigin(NSPoint(x: 0, y: 0), extent: extent, bounds: bounds) == NSPoint(x: 50, y: 50))
    #expect(PanelSettings.clampedOrigin(NSPoint(x: 5000, y: 5000), extent: extent, bounds: bounds) == NSPoint(x: 700, y: 500))
}

@Test func clampWithTooLargeExtentAlignsLowerLeft() {
    let bounds = CGRect(x: 0, y: 0, width: 100, height: 100)
    let extent = CGRect(x: -10, y: -10, width: 300, height: 300)
    #expect(PanelSettings.clampedOrigin(NSPoint(x: 50, y: 50), extent: extent, bounds: bounds) == NSPoint(x: 10, y: 10))
}

@MainActor @Test func extentsIncludeGuidesAndPanels() {
    let compact = CompactPanel(origin: .zero, qwertyOrigin: .zero, shortcuts: ShortcutStore.parse(Shortcut.defaults))
    let extent = compact.logicalExtent
    #expect(extent.minX < 0)
    #expect(extent.minY < 0)
    #expect(extent.maxX > CompactPanel.width)
    let flick = FlickPanel(origin: .zero, converter: nil, learningURL: URL(fileURLWithPath: "/dev/null"))
    let flickExtent = flick.logicalExtent
    #expect(flickExtent.minY < 0)
    #expect(flickExtent.maxY >= FlickPanel.panelHeight)
}
