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
            try? data.write(to: sessionFileURL)
        }
    }

    // Aggregate save across all open stores (multiple windows/tabs)
    func saveAllStores() {
        prepareDirectories()
        var allSessions: [DocumentSession] = []
        
        // Collect all documents from all stores
        for case let store as DocumentStore in DocumentStore.allStores.allObjects {
            let sessions: [DocumentSession] = store.documents.map { doc in
                let tempURL = tempContentURL(for: doc.id)
                // Always write snapshot for recovery (both untitled and named)
                if doc.isDirty || !fileManager.fileExists(atPath: tempURL.path) {
                    try? doc.content.data(using: .utf8)?.write(to: tempURL)
                    doc.isDirty = false
                }
                return doc.toSession(tempContentPath: tempURL.path)
            }
            allSessions.append(contentsOf: sessions)
        }
        
        // Save all sessions to one file
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        if let data = try? encoder.encode(allSessions) {
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

    func startAutoSave(store: DocumentStore) {
        stopAutoSave()
        autosaveTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            self.saveAllStores()
        }
        RunLoop.main.add(autosaveTimer!, forMode: .common)
    }

    func stopAutoSave() {
        autosaveTimer?.invalidate()
        autosaveTimer = nil
    }
}


