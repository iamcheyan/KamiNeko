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
            // 使用系统提供的 Settings 窗口（由 Settings 场景生成），避免重复菜单
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
            CommandMenu("文件") {
                Divider()
                Button("删除当前文件并关闭标签") {
                    NotificationCenter.default.post(name: .appDeleteCurrent, object: nil)
                }
                .keyboardShortcut(.delete, modifiers: [.command])
            }
        }
        Settings {
            SettingsView()
        }
    }
}
