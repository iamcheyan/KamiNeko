//
//  DocumentModel.swift
//  KamiNeko
//
//  Core document model and store for multi-tab editing
//

import Foundation
import SwiftUI

/// Serializable snapshot used for session persistence
struct DocumentSession: Codable, Identifiable {
    let id: UUID
    var title: String
    var contentFilePath: String? // for untitled, path to temp content file
    var filePath: String?        // for named files
    var isUntitled: Bool
    var fontSize: Double
}

final class DocumentModel: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    @Published var content: String
    @Published var fontSize: CGFloat
    @Published var isDirty: Bool
    var fileURL: URL?

    init(id: UUID = UUID(), title: String, content: String = "", fileURL: URL? = nil, fontSize: CGFloat = 14, isDirty: Bool = false) {
        self.id = id
        self.title = title
        self.content = content
        self.fileURL = fileURL
        self.fontSize = fontSize
        self.isDirty = isDirty
    }

    var isUntitled: Bool { fileURL == nil }

    func toSession(tempContentPath: String?) -> DocumentSession {
        DocumentSession(
            id: id,
            title: title,
            contentFilePath: isUntitled ? tempContentPath : nil,
            filePath: fileURL?.path,
            isUntitled: isUntitled,
            fontSize: Double(fontSize)
        )
    }
}

final class DocumentStore: ObservableObject {
    @Published var documents: [DocumentModel] = []
    @Published var selectedDocumentID: UUID? = nil

    // Weak registry of all stores for session aggregation across tabs/windows
    static let allStores: NSHashTable<DocumentStore> = NSHashTable<DocumentStore>.weakObjects()

    init() {
        DocumentStore.allStores.add(self)
    }

    deinit {
        DocumentStore.allStores.remove(self)
    }

    func newUntitled() {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        let timestamp = formatter.string(from: Date())
        let doc = DocumentModel(title: timestamp, content: "")
        documents.append(doc)
        selectedDocumentID = doc.id
    }

    func open(url: URL) {
        let title = url.lastPathComponent
        let content = (try? String(contentsOf: url)) ?? ""
        let doc = DocumentModel(title: title, content: content, fileURL: url, isDirty: false)
        documents.append(doc)
        selectedDocumentID = doc.id
    }

    func close(_ doc: DocumentModel) {
        if let idx = documents.firstIndex(where: { $0.id == doc.id }) {
            documents.remove(at: idx)
            if selectedDocumentID == doc.id {
                selectedDocumentID = documents.last?.id
            }
        }
    }

    func select(_ doc: DocumentModel) {
        selectedDocumentID = doc.id
    }

    func selectedDocument() -> DocumentModel? {
        documents.first(where: { $0.id == selectedDocumentID })
    }

    func adjustFontSize(delta: CGFloat) {
        guard let doc = selectedDocument() else { return }
        let newSize = max(8, min(64, doc.fontSize + delta))
        if newSize != doc.fontSize {
            doc.fontSize = newSize
        }
    }
}


