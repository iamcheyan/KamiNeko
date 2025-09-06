//
//  AppDelegate.swift
//  KamiNeko
//
//  Bridge for App life-cycle hooks if needed.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillTerminate(_ notification: Notification) {
        // Hook reserved; saving handled in ContentView toolbar or termination observer
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Prefer using native NSWindow Tab Bar
        NSWindow.allowsAutomaticWindowTabbing = true
        NSApp.windows.forEach { window in
            window.tabbingMode = .preferred
        }
    }
}


