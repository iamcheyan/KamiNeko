//
//  KamiNekoApp.swift
//  KamiNeko
//
//  Created by tetsuya on 2025/09/06.
//

import SwiftUI
import AppKit

@main
struct KamiNekoApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 980, height: 700)
        // 移除自定义菜单
        Settings {
            SettingsView()
        }
    }
}
