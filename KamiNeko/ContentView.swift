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
    // Using system window tabs; no custom tab height needed

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
                // Check if this is app startup or a new tab
                let allStores = DocumentStore.allStores.allObjects.compactMap { $0 as DocumentStore }
                let isAppStartup = allStores.count <= 1 && allStores.allSatisfy { $0.documents.isEmpty }
                
                if isAppStartup {
                    // App startup: restore documents and fan out to multiple system tabs
                    let restored = SessionManager.shared.restoreSession()
                    if restored.isEmpty {
                        store.newUntitled()
                    } else {
                        // Assign the first document to this tab/store
                        let firstDoc = restored[0]
                        store.documents = [firstDoc]
                        store.selectedDocumentID = firstDoc.id

                        // Create additional system tabs for remaining documents
                        if restored.count > 1 {
                            DispatchQueue.main.async {
                                for _ in 1..<restored.count {
                                    createSystemTabWindow()
                                }
                            }
                        }
                    }
                } else {
                    // New tab: check if there's a document waiting to be assigned
                    let restored = SessionManager.shared.restoreSession()
                    let assignedCount = allStores.filter { !$0.documents.isEmpty }.count
                    
                    if assignedCount < restored.count {
                        // There's still a document to assign to this tab
                        let docToAssign = restored[assignedCount]
                        store.documents = [docToAssign]
                        store.selectedDocumentID = docToAssign.id
                    } else {
                        // All restored documents are assigned, create new empty document
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
        .onChange(of: preferredSchemeRaw) { applyWindowAppearance() }
        .onChange(of: store.selectedDocumentID) {
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
    private func newTab() { 
        // Create a new system tab hosting a fresh ContentView
        createSystemTabWindow()
    }
    private func showAllTabs() {
        if let window = NSApp.keyWindow { _ = window.perform(NSSelectorFromString("toggleTabOverview:"), with: nil) }
    }

    private func createSystemTabWindow() {
        let controller = NSHostingController(rootView: ContentView())
        let newWindow = NSWindow(contentViewController: controller)
        newWindow.title = "Untitled"
        if let key = NSApp.keyWindow {
            key.addTabbedWindow(newWindow, ordered: .above)
        } else {
            newWindow.makeKeyAndOrderFront(nil)
        }
    }
}

