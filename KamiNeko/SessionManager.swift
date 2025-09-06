//
//  SessionManager.swift
//  KamiNeko
//
//  Responsible for saving/restoring documents and temp content files.
//

import Foundation

final class SessionManager {
    static let shared = SessionManager()

    private init() {}

    private let fileManager = FileManager.default
    private var autosaveTimer: Timer?
    var isTerminating: Bool = false

    // Fan-out queue for session restoration across system tabs
    // First ContentView will load sessions here and create (count-1) tabs.
    // Subsequent ContentViews will pop from this queue to get their document.
    private(set) var restoredDocsQueue: [DocumentModel] = []
    private var restoredDocsNextIndex: Int = 0
    private var hasPlannedFanout: Bool = false

    private var appSupportURL: URL {
        let url = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return url.appendingPathComponent("KamiNeko", isDirectory: true)
    }

    private var sessionDirURL: URL { appSupportURL.appendingPathComponent("Sessions", isDirectory: true) }
    private var sessionFileURL: URL { sessionDirURL.appendingPathComponent("session.json") }

    func prepareDirectories() {
        try? fileManager.createDirectory(at: sessionDirURL, withIntermediateDirectories: true)
    }

    func tempContentURL(for id: UUID) -> URL {
        sessionDirURL.appendingPathComponent("\(id.uuidString).txt")
    }

    func saveSession(store: DocumentStore) {
        prepareDirectories()
        let sessions: [DocumentSession] = store.documents.map { doc in
            let tempURL = tempContentURL(for: doc.id)
            // Always write snapshot for recovery (both untitled and named)
            if doc.isDirty || !fileManager.fileExists(atPath: tempURL.path) {
                try? doc.content.data(using: .utf8)?.write(to: tempURL)
                doc.isDirty = false
            }
            return doc.toSession(tempContentPath: tempURL.path)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? encoder.encode(sessions) {
            try? data.write (to: sessionFileURL)
        }
    }

    // Save all tabs (each tab should have one selected document)
    func saveAllStores() {
        prepareDirectories()
        var tabSessions: [DocumentSession] = []
        
        // Collect all documents from each store (each tab)
        for store in DocumentStore.allStores.allObjects {
            for doc in store.documents {
                // 跳过空白未命名文档（只包含空白字符）
                if doc.fileURL == nil {
                    if doc.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        continue
                    }
                }
                let tempURL = tempContentURL(for: doc.id)
                // Always write snapshot for recovery (both untitled and named)
                if doc.isDirty || !fileManager.fileExists(atPath: tempURL.path) {
                    try? doc.content.data(using: .utf8)?.write(to: tempURL)
                    doc.isDirty = false
                }
                tabSessions.append(doc.toSession(tempContentPath: tempURL.path))
            }
        }
        
        // Save all tab sessions to one file
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? encoder.encode(tabSessions) {
            try? data.write(to: sessionFileURL)
        }
    }

    func restoreSession() -> [DocumentModel] {
        prepareDirectories()
        guard let data = try? Data(contentsOf: sessionFileURL) else { return [] }
        let decoder = JSONDecoder()
        guard let sessions = try? decoder.decode([DocumentSession].self, from: data) else { return [] }
        var docs: [DocumentModel] = []
        for s in sessions {
            let snapshot = (s.contentFilePath != nil) ? (try? String(contentsOfFile: s.contentFilePath!)) : nil
            if s.isUntitled {
                let content = snapshot ?? ""
                let doc = DocumentModel(id: s.id, title: s.title, content: content, fileURL: nil, fontSize: CGFloat(s.fontSize), isDirty: false)
                docs.append(doc)
            } else if let path = s.filePath {
                let url = URL(fileURLWithPath: path)
                let content = snapshot ?? ((try? String(contentsOf: url)) ?? "")
                let doc = DocumentModel(id: s.id, title: URL(fileURLWithPath: path).lastPathComponent, content: content, fileURL: url, fontSize: CGFloat(s.fontSize), isDirty: false)
                docs.append(doc)
            }
        }
        return docs
    }

    // MARK: - Restoration fan-out helpers

    func prepareRestoredDocsQueueIfNeeded() -> [DocumentModel] {
        if restoredDocsQueue.isEmpty {
            restoredDocsQueue = restoreSession()
            restoredDocsNextIndex = 0
            hasPlannedFanout = false
        }
        return restoredDocsQueue
    }

    func takeNextRestoredDoc() -> DocumentModel? {
        guard restoredDocsNextIndex < restoredDocsQueue.count else { return nil }
        let doc = restoredDocsQueue[restoredDocsNextIndex]
        restoredDocsNextIndex += 1
        return doc
    }

    func markFanoutPlanned() { hasPlannedFanout = true }
    func fanoutAlreadyPlanned() -> Bool { hasPlannedFanout }

    func clearQueueIfDistributed() {
        if restoredDocsNextIndex >= restoredDocsQueue.count {
            restoredDocsQueue.removeAll()
            restoredDocsNextIndex = 0
            hasPlannedFanout = false
        }
    }

    func startAutoSave(store: DocumentStore) {
        stopAutoSave()
        guard UserDefaults.standard.bool(forKey: "enableAutoSave") else { return }
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.saveFileBackedDocumentsToDisk()
            self.saveAllStores()
        }
        RunLoop.main.add(autosaveTimer!, forMode: .common)
    }

    func stopAutoSave() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
    }

    // 将所有文件型文档写入磁盘
    func saveFileBackedDocumentsToDisk() {
        WorkingDirectoryManager.shared.withDirectoryAccess {
            for s in DocumentStore.allStores.allObjects {
                for d in s.documents {
                    if let url = d.fileURL, d.isDirty {
                        try? d.content.data(using: .utf8)?.write(to: url)
                        d.isDirty = false
                    }
                }
            }
        }
    }
}


