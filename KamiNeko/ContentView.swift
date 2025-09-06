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
    // When provided, this document will be used to initialize the store
    private var initialDocument: DocumentModel? = nil

    init(initialDocument: DocumentModel? = nil) {
        self.initialDocument = initialDocument
    }
    @StateObject private var store = DocumentStore()
    @State private var isShowingOpenPanel = false
    @AppStorage("preferredColorScheme") private var preferredSchemeRaw: String = "system"
    // Using system window tabs; no custom tab height needed
    @State private var tabCount: Int = 1
    @State private var owningWindow: NSWindow? = nil

    private var preferredScheme: ColorScheme? {
        switch preferredSchemeRaw {
        case "light": return .light
        case "dark": return .dark
        default: return nil // follow system
        }
    }

    var body: some View {
        applyGlobalHandlers(
            AnyView(
                rootView()
                    .background(WindowAccessor { win in
                        // 只绑定一次所属窗口，避免不同实例互相覆盖
                        if owningWindow == nil {
                            owningWindow = win
                            updateWindowTitle()
                        }
                    })
            )
        )
    }

    // 将全局事件与修饰器集中，降低 body 表达式复杂度
    private func applyGlobalHandlers(_ base: AnyView) -> AnyView {
        var view = base
        view = AnyView(view.onAppear {
            if store.documents.isEmpty {
                // Check if this is app startup or a new tab
                let allStores = DocumentStore.allStores.allObjects
                let isAppStartup = allStores.count <= 1 && allStores.allSatisfy { $0.documents.isEmpty }
                
                if isAppStartup {
                    // 优先使用工作目录模式：按目录中文件构建标签；若未设置目录，则提示选择
                    if let _ = WorkingDirectoryManager.shared.directoryURL ?? WorkingDirectoryManager.shared.promptUserToChooseDirectory() {
                        var files = WorkingDirectoryManager.shared.listFiles()
                        // 启动时先清理空白文件（仅空白字符），并从加载列表中过滤掉
                        files = files.filter { url in
                            if WorkingDirectoryManager.shared.isWhitespaceOnly(url) {
                                try? WorkingDirectoryManager.shared.deleteFile(at: url)
                                return false
                            }
                            return true
                        }
                        if files.isEmpty {
                            // 目录为空：自动创建一个新文件与标签
                            if let newURL = try? WorkingDirectoryManager.shared.createNewEmptyFile() {
                                let doc = makeDoc(for: newURL)
                                store.documents = [doc]
                                store.selectedDocumentID = doc.id
                            } else {
                                store.newUntitled()
                            }
                        } else {
                            // 目录已有文件：首个在当前标签，其余扇出
                            let firstURL = files[0]
                            let firstDoc = makeDoc(for: firstURL)
                            store.documents = [firstDoc]
                            store.selectedDocumentID = firstDoc.id
                            if files.count > 1 {
                                let rest = Array(files.dropFirst()).map { makeDoc(for: $0) }
                                fanOutRestoredDocs(rest)
                            }
                        }
                    } else {
                        // 无目录：退回到会话恢复
                        let restored = SessionManager.shared.restoreSession()
                        if restored.isEmpty {
                            if let doc = initialDocument {
                                store.documents = [doc]
                                store.selectedDocumentID = doc.id
                            } else {
                                store.newUntitled()
                            }
                        } else {
                            let first = restored[0]
                            store.documents = [first]
                            store.selectedDocumentID = first.id
                            if restored.count > 1 {
                                fanOutRestoredDocs(Array(restored.dropFirst()))
                            }
                        }
                    }
                } else {
                    // New tab: if initial doc provided, use it; otherwise create empty
                    if let doc = initialDocument {
                        store.documents = [doc]
                        store.selectedDocumentID = doc.id
                    } else {
                        if WorkingDirectoryManager.shared.directoryURL != nil, let newURL = try? WorkingDirectoryManager.shared.createNewEmptyFile() {
                            let doc = makeDoc(for: newURL)
                            store.documents = [doc]
                            store.selectedDocumentID = doc.id
                        } else {
                            store.newUntitled()
                        }
                    }
                }
            } else if store.selectedDocument() == nil {
                store.newUntitled()
            }
            SessionManager.shared.startAutoSave(store: store)
            updateWindowTitle()
            applyWindowAppearance()
            updateTabCount()
        })
        view = AnyView(view.onDisappear { SessionManager.shared.stopAutoSave() })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .workingDirectoryChanged)) { _ in
            // 目录变更后：清空当前文档并从新目录创建首个文件
            if let url = try? WorkingDirectoryManager.shared.createNewEmptyFile() {
                let doc = makeDoc(for: url)
                store.documents = [doc]
                store.selectedDocumentID = doc.id
                updateWindowTitle()
            }
        })
        view = AnyView(view.preferredColorScheme(preferredScheme))
        view = AnyView(view.onChange(of: preferredSchemeRaw) { applyWindowAppearance() })
        view = AnyView(view.onChange(of: store.selectedDocumentID) {
            updateWindowTitle()
            if let title = store.selectedDocument()?.title {
                NotificationCenter.default.post(name: .documentTitleChanged, object: nil, userInfo: ["title": title])
            }
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .appZoomIn)) { _ in store.adjustFontSize(delta: 1) })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .appZoomOut)) { _ in store.adjustFontSize(delta: -1) })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .appZoomReset)) { _ in
            if let doc = store.selectedDocument() { doc.fontSize = 14 }
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .appPreferencesChanged)) { _ in
            // 行号显示切换
            if let sv = (NSApp.keyWindow?.contentView?.subviews.compactMap { $0 as? NSScrollView }.first) {
                let on = UserDefaults.standard.bool(forKey: "showLineNumbers")
                sv.hasVerticalRuler = on
                sv.rulersVisible = on
            }
            // 自动保存开关
            if UserDefaults.standard.bool(forKey: "enableAutoSave") {
                SessionManager.shared.startAutoSave(store: store)
            } else {
                SessionManager.shared.stopAutoSave()
            }
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .documentRenameRequested)) { note in
            if let name = note.userInfo?["title"] as? String, let doc = store.selectedDocument() {
                doc.title = name
                updateWindowTitle()
                NotificationCenter.default.post(name: .documentTitleChanged, object: nil, userInfo: ["title": name])
            }
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: NSWindow.didResizeNotification)) { _ in
            if let tv = (NSApp.keyWindow?.contentView?.subviews.compactMap { $0 as? NSScrollView }.first?.documentView as? NSTextView), let container = tv.textContainer, let sv = tv.enclosingScrollView {
                container.containerSize = NSSize(width: sv.contentSize.width, height: .greatestFiniteMagnitude)
            }
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .toolbarUndo)) { _ in performUndo() })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .toolbarRedo)) { _ in performRedo() })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .toolbarNewDoc)) { _ in newTab() })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .toolbarOpenFile)) { _ in openFile() })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .appSaveFile)) { _ in
            // 写入所有文件并保存整个会话
            SessionManager.shared.saveFileBackedDocumentsToDisk()
            SessionManager.shared.saveAllStores()
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .appDeleteCurrent)) { _ in
            // 统一由 willClose 分支执行删除逻辑
            NSApp.keyWindow?.performClose(nil)
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .toolbarToggleTheme)) { _ in
            toggleAppearance()
            NotificationCenter.default.post(name: .appAppearanceChanged, object: nil)
        })
        // 仍保留 .toolbarNewTab 的响应以兼容未来入口
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .toolbarNewTab)) { _ in newTab() })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .toolbarShowAllTabs)) { _ in showAllTabs() })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .documentTitleChanged)) { _ in syncRenameIfNeeded() })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: .documentContentChanged)) { note in
            // 仅当变更的是当前选中文档，才更新标题
            if let changedDoc = note.object as? DocumentModel, changedDoc.id == store.selectedDocumentID {
                updateWindowTitle()
            }
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { note in
            if let win = note.object as? NSWindow, win === owningWindow {
                updateWindowTitle()
            }
            updateTabCount()
        })
        view = AnyView(view.onReceive(NotificationCenter.default.publisher(for: NSWindow.willCloseNotification)) { note in
            // 应用退出时不做任何删除
            if SessionManager.shared.isTerminating { return }
            // 仅处理当前视图所属窗口的关闭事件，避免误删其它窗口文件
            guard let closingWindow = note.object as? NSWindow, closingWindow === owningWindow else { return }
            if let url = store.selectedDocument()?.fileURL {
                _ = WorkingDirectoryManager.shared.withDirectoryAccess {
                    try? WorkingDirectoryManager.shared.deleteFile(at: url)
                }
            }
        })
        return view
    }

    private func rootView() -> AnyView {
        AnyView(
            ZStack(alignment: .bottom) {
                editorArea()
            }
        )
    }

    // MARK: - Subviews

    @ViewBuilder
    private func editorArea() -> some View {
        VStack(spacing: 0) {
            if let doc = store.selectedDocument() {
                EditorTextView(document: doc)
                    .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                        SessionManager.shared.saveFileBackedDocumentsToDisk()
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
    }

    @ViewBuilder
    private func bottomTabCounter() -> some View {
        HStack {
            Text("已打开标签：\(tabCount)")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color(NSColor.windowBackgroundColor).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .padding(.bottom, 6)
        .allowsHitTesting(false)
    }

    // 在 Tab Overview（九宫格）模式下追加一个只读 overlay 窗口显示计数
    private func showTabCountOverlay() {
        guard let key = NSApp.keyWindow else { return }
        let overlayTag = 0xC0FFEE
        if let existing = key.contentView?.viewWithTag(overlayTag) { existing.removeFromSuperview() }

        let label = NSTextField(labelWithString: "已打开标签：\( (key.tabbedWindows?.count ?? 1) )")
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.wantsLayer = true
        label.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.6).cgColor
        label.layer?.cornerRadius = 8
        label.tag = overlayTag

        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        label.translatesAutoresizingMaskIntoConstraints = false

        key.contentView?.addSubview(container)
        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: key.contentView!.centerXAnchor),
            container.bottomAnchor.constraint(equalTo: key.contentView!.bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6)
        ])

        // 自动隐藏（离开九宫格或3秒后）
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            container.removeFromSuperview()
        }
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
        guard let window = owningWindow, let doc = store.selectedDocument() else { return }
        let fallback = doc.fileURL?.lastPathComponent ?? doc.title
        let display = computeDisplayTitle(from: doc.content, fallback: fallback)
        let truncated = display.count > 40 ? String(display.prefix(40)) : display
        window.title = truncated
        if let url = doc.fileURL { window.representedURL = url } else { window.representedURL = nil }
        NotificationCenter.default.post(name: .documentTitleChanged, object: nil, userInfo: ["title": window.representedURL != nil ? (window.representedURL!.path) : truncated])
    }

    private func updateWindowTitleFromContent(maxLength: Int = 40) {
        guard let window = owningWindow, let doc = store.selectedDocument() else { return }
        let raw = doc.content
        let display: String = computeDisplayTitle(from: raw, fallback: doc.fileURL?.lastPathComponent ?? doc.title)
        let truncated = display.count > maxLength ? String(display.prefix(maxLength)) : display
        window.title = truncated
        NotificationCenter.default.post(name: .documentTitleChanged, object: nil, userInfo: ["title": window.representedURL != nil ? (window.representedURL!.path) : truncated])
    }

    private func computeDisplayTitle(from content: String, fallback: String) -> String {
        let lines = content.split(maxSplits: 10, omittingEmptySubsequences: true, whereSeparator: { $0 == "\n" || $0 == "\r" })
        guard let first = lines.first else { return fallback }
        let firstLine = String(first)
        // Pattern like Swift header comments
        if firstLine.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).hasPrefix("//") {
            // 优先使用第一行注释内容（去掉开头标点），若为空再向下找
            let firstSanitized = sanitizeLeadingPunctuation(firstLine.replacingOccurrences(of: "//", with: ""))
            if firstSanitized.isEmpty == false { return firstSanitized }
            for lineSub in lines.prefix(5) {
                var s = String(lineSub)
                s = s.replacingOccurrences(of: "//", with: "").trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                if s.hasSuffix(".swift") || s.hasSuffix(".txt") { return s }
            }
            if let nonComment = lines.drop(while: { $0.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).hasPrefix("//") }).first {
                return sanitizeLeadingPunctuation(String(nonComment))
            }
            return fallback
        }
        return sanitizeLeadingPunctuation(firstLine)
    }

    private func sanitizeLeadingPunctuation(_ s: String) -> String {
        var result = s.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        var charset = CharacterSet.punctuationCharacters
        charset.formUnion(.symbols)
        charset.formUnion(.whitespacesAndNewlines)
        let extra = CharacterSet(charactersIn: "／、，。！？；：—…·・*_#-=+|<>[](){}\\/\"'`~“”‘’《》【】（）")
        charset.formUnion(extra)
        while let first = result.first, String(first).rangeOfCharacter(from: charset) != nil {
            result.removeFirst()
        }
        return result
    }

    private func performUndo() { NSApp.sendAction(#selector(UndoManager.undo), to: nil, from: nil) }
    private func performRedo() { NSApp.sendAction(#selector(UndoManager.redo), to: nil, from: nil) }
    private func newTab() { 
        // 基于当前激活窗口创建系统标签
        createSystemTabWindow(with: nil, baseWindow: NSApp.keyWindow)
        updateTabCount()
    }
    private func showAllTabs() {
        if let window = NSApp.keyWindow {
            _ = window.perform(NSSelectorFromString("toggleTabOverview:"), with: nil)
            showTabCountOverlay()
        }
    }

    private func createSystemTabWindow(with doc: DocumentModel? = nil, baseWindow: NSWindow? = NSApp.keyWindow) {
        guard let base = baseWindow else { return }
        let controller = NSHostingController(rootView: ContentView(initialDocument: doc))
        let newWindow = NSWindow(contentViewController: controller)
        if let doc = doc {
            let fallback = doc.fileURL?.lastPathComponent ?? doc.title
            let display = computeDisplayTitle(from: doc.content, fallback: fallback)
            newWindow.title = display.count > 40 ? String(display.prefix(40)) : display
            newWindow.representedURL = doc.fileURL
        } else {
            newWindow.title = "Untitled"
            newWindow.representedURL = nil
        }
        newWindow.tabbingMode = .preferred
        // 先附加工具栏，避免 nil toolbar
        BrowserToolbarController.shared.attach(to: newWindow)
        base.addTabbedWindow(newWindow, ordered: .above)
        newWindow.makeKeyAndOrderFront(nil)
        updateTabCount()
    }

    // 在首个窗口成为 key 后，将其余文档扇出为系统标签；若暂未有 keyWindow，则重试数次
    private func fanOutRestoredDocs(_ docs: [DocumentModel], attempt: Int = 0) {
        if let base = NSApp.keyWindow {
            for doc in docs {
                createSystemTabWindow(with: doc, baseWindow: base)
            }
            return
        }
        if attempt >= 30 { // 最长约 1.5s
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            fanOutRestoredDocs(docs, attempt: attempt + 1)
        }
    }

    private func updateTabCount() {
        if let key = NSApp.keyWindow, let tabs = key.tabbedWindows {
            tabCount = max(1, tabs.count)
        } else {
            // 回退到全局 store 数量（跨窗口合计）
            let count = DocumentStore.allStores.allObjects.count
            tabCount = max(1, count)
        }
    }

    private func syncRenameIfNeeded() {
        guard let doc = store.selectedDocument() else { return }
        // 仅处理文件型文档：把标题作为新文件名
        if let url = doc.fileURL {
            do {
                let currentBase = url.deletingPathExtension().lastPathComponent
                // 仅当标题与当前文件名不同才重命名，避免无意义的“ 2”后缀
                if doc.title != currentBase && doc.title.isEmpty == false {
                    let newURL = try WorkingDirectoryManager.shared.renameFile(at: url, to: doc.title)
                    doc.fileURL = newURL
                }
            } catch {
                // 忽略重命名失败
            }
        }
    }

    private func makeDoc(for url: URL) -> DocumentModel {
        let title = url.deletingPathExtension().lastPathComponent
        let content: String = WorkingDirectoryManager.shared.withDirectoryAccess {
            (try? String(contentsOf: url)) ?? ""
        }
        return DocumentModel(title: title, content: content, fileURL: url, isDirty: false)
    }
}

// MARK: - WindowAccessor: 捕获 NSWindow 引用
private struct WindowAccessor: NSViewRepresentable {
    let onResolve: (NSWindow) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            if let win = view?.window { onResolve(win) }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            if let win = nsView?.window { onResolve(win) }
        }
    }
}

