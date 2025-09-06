//
//  AppDelegate.swift
//  KamiNeko
//
//  Bridge for App life-cycle hooks if needed.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuObservers: [NSObjectProtocol] = []
    func applicationShouldRestoreWindows(_ app: NSApplication) -> Bool { false }
    @available(macOS 13.0, *)
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // 在任何窗口开始关闭之前标记正在退出，避免 willClose 中误删文件
        SessionManager.shared.isTerminating = true
        return .terminateNow
    }
    func applicationWillTerminate(_ notification: Notification) {
        SessionManager.shared.isTerminating = true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prefer using native NSWindow Tab Bar
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApp.windows.forEach { window in
            window.tabbingMode = .preferred
        }
        // 动态本地化应用主菜单（Application 菜单）
        localizeMainMenu()
        NotificationCenter.default.addObserver(forName: .appPreferencesChanged, object: nil, queue: .main) { [weak self] _ in
            self?.localizeMainMenu()
        }
        // 在应用激活/更新周期内再次应用一次，避免系统后续覆盖标题
        NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            self?.localizeMainMenu()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didUpdateNotification, object: nil, queue: .main) { [weak self] _ in
            // 异步稍后执行，确保菜单已完成系统构建
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self?.localizeMainMenu()
            }
        }

        // 监听所有菜单打开时的回调，做运行时本地化（包含标签右键菜单）
        let willOpen = NotificationCenter.default.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] note in
            guard let menu = note.object as? NSMenu else { return }
            self?.localizeArbitraryMenu(menu)
        }
        let didAdd = NotificationCenter.default.addObserver(forName: NSMenu.didAddItemNotification, object: nil, queue: .main) { [weak self] note in
            if let menu = note.object as? NSMenu { self?.localizeArbitraryMenu(menu) }
        }
        menuObservers.append(contentsOf: [willOpen, didAdd])

        if let window = NSApp.windows.first, window.identifier?.rawValue == "KamiNeko.ContentWindow" {
            BrowserToolbarController.shared.attach(to: window)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            if let window = note.object as? NSWindow, window.identifier?.rawValue == "KamiNeko.ContentWindow" {
                BrowserToolbarController.shared.attach(to: window)
            }
        }
    }

    private func localizeMainMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }
        guard let appMenuItem = mainMenu.items.first, let appSubmenu = appMenuItem.submenu else { return }
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? (Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String ?? "App")
        func fmt(_ key: String) -> String { String(format: Localizer.t(key), appName) }

        for item in appSubmenu.items {
            switch item.action {
            case #selector(NSApplication.orderFrontStandardAboutPanel(_:)):
                item.title = fmt("menu.aboutApp")
            case #selector(NSApplication.hide(_:)):
                item.title = fmt("menu.hideApp")
            case #selector(NSApplication.hideOtherApplications(_:)):
                item.title = Localizer.t("menu.hideOthers")
            case #selector(NSApplication.unhideAllApplications(_:)):
                item.title = Localizer.t("menu.showAll")
            case #selector(NSApplication.terminate(_:)):
                item.title = fmt("menu.quitApp")
            default:
                // Fallback by known titles
                if item.title == "Services" { item.title = Localizer.t("menu.services") }
                // Settings… menu item (SwiftUI inserts with cmd+, but action is private)
                if item.keyEquivalent == "," && item.keyEquivalentModifierMask.contains(.command) {
                    item.title = Localizer.t("menu.settings")
                }
                break
            }
        }
        // 顶部主菜单标题（File/Edit/View/Window/Help）
        let desired = [
            (keys: ["File", "文件", "ファイル"], value: Localizer.t("menu.file")),
            (keys: ["Edit", "编辑", "編集"], value: Localizer.t("menu.edit")),
            (keys: ["View", "显示", "表示"], value: Localizer.t("menu.view")),
            (keys: ["Window", "窗口", "ウインドウ"], value: Localizer.t("menu.window")),
            (keys: ["Help", "帮助", "ヘルプ"], value: Localizer.t("menu.help"))
        ]
        for item in mainMenu.items.dropFirst() { // drop Apple menu
            for group in desired {
                if group.keys.contains(item.title) {
                    item.title = group.value
                }
            }
            // 特别处理 Window 菜单中的标签相关项
            if let submenu = item.submenu {
                localizeWindowMenu(submenu)
                localizeCommonMenuItemsRecursively(submenu)
            }
        }
        // 直接设置系统引用的菜单标题以确保刷新
        if let winMenu = NSApp.windowsMenu { winMenu.title = Localizer.t("menu.window") }
        if let help = NSApp.helpMenu { help.title = Localizer.t("menu.help") }
        // 强制刷新
        mainMenu.update()

        // 兜底：按典型顺序强制写入（App, File, Edit, View, Window, Help）
        let titles = [Localizer.t("menu.file"), Localizer.t("menu.edit"), Localizer.t("menu.view"), Localizer.t("menu.window"), Localizer.t("menu.help")]
        if mainMenu.items.count >= 6 {
            for (idx, title) in titles.enumerated() {
                let i = idx + 1
                if i < mainMenu.items.count {
                    mainMenu.items[i].title = title
                }
            }
        }
    }

    private func localizeWindowMenu(_ menu: NSMenu) {
        for i in menu.items {
            let map: [String: String] = [
                "Close Tab": Localizer.t("menu.closeTab"),
                "Close Other Tabs": Localizer.t("menu.closeOtherTabs"),
                "Move Tab to New Window": Localizer.t("menu.moveTabToNewWindow"),
                "Show All Tabs": Localizer.t("menu.showAllTabs"),
                "Show Tab Bar": Localizer.t("menu.showTabBar"),
                "Hide Tab Bar": Localizer.t("menu.hideTabBar"),
                // File menu items we want to localize when they appear in Window/Tab contexts
                "New Window": Localizer.t("menu.newWindow"),
                "Close Window": Localizer.t("menu.closeWindow")
            ]
            if let s = map[i.title] { i.title = s }
        }
    }

    // 针对任意 NSMenu（包含标签右键菜单）做本地化
    private func localizeArbitraryMenu(_ menu: NSMenu) {
        // 标签右键菜单与 Window 菜单共享相同的英文文案
        localizeWindowMenu(menu)
        // Services/Settings 等常见项
        for i in menu.items {
            if i.title == "Services" { i.title = Localizer.t("menu.services") }
            if i.keyEquivalent == "," && i.keyEquivalentModifierMask.contains(.command) {
                i.title = Localizer.t("menu.settings")
            }
            // File 菜单常见项
            if i.title == "New Window" { i.title = Localizer.t("menu.newWindow") }
            if i.title == "Close Window" { i.title = Localizer.t("menu.closeWindow") }
            if i.title == "Close Tab" { i.title = Localizer.t("menu.closeTabFile") }
        }
    }

    private func localizeCommonMenuItemsRecursively(_ menu: NSMenu) {
        for i in menu.items {
            if i.title == "Services" { i.title = Localizer.t("menu.services") }
            if i.keyEquivalent == "," && i.keyEquivalentModifierMask.contains(.command) {
                i.title = Localizer.t("menu.settings")
            }
            // File items
            if i.title == "New Window" { i.title = Localizer.t("menu.newWindow") }
            if i.title == "Close Window" { i.title = Localizer.t("menu.closeWindow") }
            if i.title == "Close Tab" { i.title = Localizer.t("menu.closeTabFile") }
            // Window / Tab items
            let windowMap: [String: String] = [
                "Close Tab": Localizer.t("menu.closeTab"),
                "Close Other Tabs": Localizer.t("menu.closeOtherTabs"),
                "Move Tab to New Window": Localizer.t("menu.moveTabToNewWindow"),
                "Show All Tabs": Localizer.t("menu.showAllTabs"),
                "Show Tab Bar": Localizer.t("menu.showTabBar"),
                "Hide Tab Bar": Localizer.t("menu.hideTabBar")
            ]
            if let s = windowMap[i.title] { i.title = s }
            if let sub = i.submenu { localizeCommonMenuItemsRecursively(sub) }
        }
    }

    // 处理系统标签栏的“+”按钮动作
    @objc func newWindowForTab(_ sender: Any?) {
        guard let base = NSApp.keyWindow else { return }
        let controller = NSHostingController(rootView: ContentView())
        let newWindow = NSWindow(contentViewController: controller)
        newWindow.tabbingMode = NSWindow.TabbingMode.preferred
        BrowserToolbarController.shared.attach(to: newWindow)
        base.addTabbedWindow(newWindow, ordered: .above)
        newWindow.makeKeyAndOrderFront(nil as Any?)
    }
}


