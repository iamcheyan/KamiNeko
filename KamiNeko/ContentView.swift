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
                        SessionManager.shared.saveAllStores()
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
            if store.documents.isEmpty {
                // Check if this is app startup (first store) or a new tab
                let allStores = DocumentStore.allStores.allObjects
                let isAppStartup = allStores.count <= 1 && allStores.allSatisfy { ($0 as? DocumentStore)?.documents.isEmpty ?? true }
                
                if isAppStartup {
                    // App startup: restore documents and fan out to multiple tabs
                    let restored = SessionManager.shared.restoreSession()
                    if restored.isEmpty {
                        store.newUntitled()
                    } else {
                        // Assign the first document to this store
                        let firstDoc = restored.first!
                        store.documents = [firstDoc]
                        store.selectedDocumentID = firstDoc.id
                        
                        // For remaining documents, create additional tabs; each new tab
                        // will pick up one unassigned restored document on its own appear
                        if restored.count > 1 {
                            for _ in 1..<restored.count {
                                newTab()
                            }
                        }
                    }
                } else {
                    // New tab: try to take one of the restored documents not yet assigned
                    let restored = SessionManager.shared.restoreSession()
                    let assignedIDs = Set(DocumentStore.allStores.allObjects.flatMap { ($0 as? DocumentStore)?.documents.map { $0.id } ?? [] })
                    if let docToAssign = restored.first(where: { !assignedIDs.contains($0.id) }) {
                        store.documents = [docToAssign]
                        store.selectedDocumentID = docToAssign.id
                    } else {
                        // No pending restored docs, create an empty one
                        store.newUntitled()
                    }
                }
            } else if store.selectedDocument() == nil {
                store.newUntitled()
            }
            SessionManager.shared.startAutoSave(store: store)
            updateWindowTitle()
            applyWindowAppearance()
        }
        .onDisappear { SessionManager.shared.stopAutoSave() }
        .preferredColorScheme(preferredScheme)
        .onChange(of: preferredSchemeRaw) { _ in applyWindowAppearance() }
        .onChange(of: store.selectedDocumentID) { _ in
            updateWindowTitle()
            if let title = store.selectedDocument()?.title {
                NotificationCenter.default.post(name: .documentTitleChanged, object: nil, userInfo: ["title": title])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appZoomIn)) { _ in store.adjustFontSize(delta: 1) }
        .onReceive(NotificationCenter.default.publisher(for: .appZoomOut)) { _ in store.adjustFontSize(delta: -1) }
        .onReceive(NotificationCenter.default.publisher(for: .appZoomReset)) { _ in
            if let doc = store.selectedDocument() { doc.fontSize = 14 }
        }
        .onReceive(NotificationCenter.default.publisher(for: .documentRenameRequested)) { note in
            if let name = note.userInfo?["title"] as? String, let doc = store.selectedDocument() {
                doc.title = name
                updateWindowTitle()
                NotificationCenter.default.post(name: .documentTitleChanged, object: nil, userInfo: ["title": name])
            }
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

