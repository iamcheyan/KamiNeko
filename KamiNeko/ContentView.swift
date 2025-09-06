//
//  ContentView.swift
//  KamiNeko
//
//  Created by tetsuya on 2025/09/06.
//

import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var store = DocumentStore()
    @State private var isShowingOpenPanel = false
    @AppStorage("preferredColorScheme") private var preferredSchemeRaw: String = "system"
    private let tabHeight: CGFloat = 28

    private var preferredScheme: ColorScheme? {
        switch preferredSchemeRaw {
        case "light": return .light
        case "dark": return .dark
        default: return nil // follow system
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Editor area
            if let doc = store.selectedDocument() {
                EditorTextView(document: doc)
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                        SessionManager.shared.saveSession(store: store)
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .editorFontSizeChanged)) { output in
                        if let size = output.userInfo?["fontSize"] as? CGFloat, let sdoc = store.selectedDocument() {
                            sdoc.fontSize = size
                        }
                    }
                    .onAppear(perform: setupShortcuts)
            } else {
                ZStack {
                    Color(NSColor.textBackgroundColor)
                    Text("新建文档或打开文件")
                        .foregroundColor(.secondary)
                }
            }
        }
        .onAppear {
            // If this is the first window (no documents yet), restore session; otherwise create a fresh empty doc
            if store.documents.isEmpty {
                let restored = SessionManager.shared.restoreSession()
                if restored.isEmpty {
                    store.newUntitled()
                } else {
                    store.documents = restored
                    store.selectedDocumentID = restored.first?.id
                }
            } else if store.selectedDocument() == nil {
                store.newUntitled()
            }
            SessionManager.shared.startAutoSave(store: store)
            updateWindowTitle()
        }
        .onDisappear { SessionManager.shared.stopAutoSave() }
        .toolbar {
            // 左侧按钮（撤销、重做、新建、打开、保存）
            ToolbarItemGroup(placement: .navigation) {
                Button(action: performUndo) { Image(systemName: "arrow.uturn.backward") }
                Button(action: performRedo) { Image(systemName: "arrow.uturn.forward") }
                Divider().frame(height: 16)
                Button(action: { store.newUntitled() }) { Image(systemName: "doc") }
                Button(action: openFile) { Image(systemName: "folder") }
                Button(action: { SessionManager.shared.saveAllStores() }) { Image(systemName: "tray.and.arrow.down") }
            }
            // 中部标题胶囊
            // 中央标题留空，隐藏默认大标题视觉
            ToolbarItem(placement: .principal) { EmptyView() }
            // 右侧功能按钮（主题、新建Tab、显示所有Tab）
            ToolbarItemGroup(placement: .automatic) {
                Button(action: toggleAppearance) { Image(systemName: preferredScheme == .dark ? "sun.max" : "moon") }
                Button(action: newTab) { Image(systemName: "plus") }
                Button(action: showAllTabs) { Image(systemName: "square.grid.2x2") }
            }
        }
        .preferredColorScheme(preferredScheme)
        .onAppear { applyWindowAppearance() }
        .onChange(of: preferredSchemeRaw) { _ in applyWindowAppearance() }
        .onChange(of: store.selectedDocumentID) { _ in updateWindowTitle() }
        .onChange(of: store.selectedDocumentID) { _ in
            if let title = store.selectedDocument()?.title {
                NotificationCenter.default.post(name: .documentTitleChanged, object: nil, userInfo: ["title": title])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appZoomIn)) { _ in store.adjustFontSize(delta: 1) }
        .onReceive(NotificationCenter.default.publisher(for: .appZoomOut)) { _ in store.adjustFontSize(delta: -1) }
        .onReceive(NotificationCenter.default.publisher(for: .appZoomReset)) { _ in
            if let doc = store.selectedDocument() { doc.fontSize = 14 }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { _ in
            // Keep container width updated after scroll/resize
            if let tv = (NSApp.keyWindow?.contentView?.subviews.compactMap { $0 as? NSScrollView }.first?.documentView as? NSTextView), let container = tv.textContainer, let sv = tv.enclosingScrollView {
                container.containerSize = NSSize(width: sv.contentSize.width, height: .greatestFiniteMagnitude)
            }
        }
        // Bind Toolbar actions to app behaviors
        .onReceive(NotificationCenter.default.publisher(for: .toolbarUndo)) { _ in performUndo() }
        .onReceive(NotificationCenter.default.publisher(for: .toolbarRedo)) { _ in performRedo() }
        .onReceive(NotificationCenter.default.publisher(for: .toolbarNewDoc)) { _ in store.newUntitled() }
        .onReceive(NotificationCenter.default.publisher(for: .toolbarOpenFile)) { _ in openFile() }
        .onReceive(NotificationCenter.default.publisher(for: .toolbarSaveSession)) { _ in SessionManager.shared.saveAllStores() }
        .onReceive(NotificationCenter.default.publisher(for: .toolbarToggleTheme)) { _ in toggleAppearance() }
        .onReceive(NotificationCenter.default.publisher(for: .toolbarNewTab)) { _ in newTab() }
        .onReceive(NotificationCenter.default.publisher(for: .toolbarShowAllTabs)) { _ in showAllTabs() }
    }

    private func openFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.item]
        if panel.runModal() == .OK, let url = panel.url {
            store.open(url: url)
            updateWindowTitle()
        }
    }

    private func setupShortcuts() {
        // Cmd+ / Cmd-
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.modifierFlags.contains(.command) else { return event }
            if event.characters == "+" || event.characters == "=" { // = is same key for +
                store.adjustFontSize(delta: 1)
                return nil
            } else if event.characters == "-" {
                store.adjustFontSize(delta: -1)
                return nil
            }
            return event
        }
    }

    private func toggleAppearance() {
        if preferredScheme == .dark {
            preferredSchemeRaw = "light"
        } else if preferredScheme == .light {
            preferredSchemeRaw = "dark"
        } else {
            // if system, switch to dark first
            preferredSchemeRaw = "dark"
        }
    }

    private func applyWindowAppearance() {
        let name: NSAppearance.Name? = {
            switch preferredScheme {
            case .some(.dark): return .darkAqua
            case .some(.light): return .aqua
            default: return nil
            }
        }()
        for window in NSApp.windows {
            window.appearance = name.flatMap { NSAppearance(named: $0) }
        }
    }

    private func updateWindowTitle() {
        guard let window = NSApp.keyWindow ?? NSApp.windows.first, let doc = store.selectedDocument() else { return }
        window.title = doc.title
    }

    private func performUndo() { NSApp.sendAction(#selector(UndoManager.undo), to: nil, from: nil) }
    private func performRedo() { NSApp.sendAction(#selector(UndoManager.redo), to: nil, from: nil) }
    private func newTab() { NSApp.keyWindow?.newWindowForTab(nil) }
    private func showAllTabs() {
        if let window = NSApp.keyWindow { _ = window.perform(NSSelectorFromString("toggleTabOverview:"), with: nil) }
    }
}

