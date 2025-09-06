//
//  AppDelegate.swift
//  KamiNeko
//
//  Bridge for App life-cycle hooks if needed.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldRestoreWindows(_ app: NSApplication) -> Bool { false }
    @available(macOS 13.0, *)
    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { false }
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


