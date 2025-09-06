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
            CommandMenu("文件") {
                Button("保存") {
                    NotificationCenter.default.post(name: .appSaveFile, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command])
            }
            CommandGroup(replacing: .appSettings) {
                Button("设置…") {
                    NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: [.command])
            }
            CommandMenu("工作目录") {
                Button("显示当前工作目录") {
                    if let url = WorkingDirectoryManager.shared.directoryURL {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])

                Button("重新设置工作目录…") {
                    _ = WorkingDirectoryManager.shared.promptUserToChooseDirectory()
                }
            }
        }
        Settings {
            SettingsView()
        }
    }
}
