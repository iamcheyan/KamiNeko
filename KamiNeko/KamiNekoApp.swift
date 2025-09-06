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
        .commands {
            CommandMenu("字体") {
                Button("放大") {
                    NotificationCenter.default.post(name: .appZoomIn, object: nil)
                }
                .keyboardShortcut("+", modifiers: [.command])

                Button("缩小") {
                    NotificationCenter.default.post(name: .appZoomOut, object: nil)
                }
                .keyboardShortcut("-", modifiers: [.command])
            }
        }
    }
}
