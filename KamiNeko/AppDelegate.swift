//
//  AppDelegate.swift
//  KamiNeko
//
//  Bridge for App life-cycle hooks if needed.
//

import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        SessionManager.shared.isTerminating = true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prefer using native NSWindow Tab Bar
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApp.windows.forEach { window in
            window.tabbingMode = .preferred
        }
        if let window = NSApp.windows.first {
            BrowserToolbarController.shared.attach(to: window)
        }
        NotificationCenter.default.addObserver(forName: NSWindow.didBecomeKeyNotification, object: nil, queue: .main) { note in
            if let window = note.object as? NSWindow {
                BrowserToolbarController.shared.attach(to: window)
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


