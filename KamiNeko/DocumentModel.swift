//
//  DocumentModel.swift
//  KamiNeko
//
//  Core document model and store for multi-tab editing
//

import Foundation
import SwiftUI

/// Document type enumeration
enum DocumentType: String, Codable, CaseIterable {
    case localDocument = "local_document"    // 本地文档
    case openedDocument = "opened_document"  // 打开文档
}

/// Serializable snapshot used for session persistence
struct DocumentSession: Codable, Identifiable {
    let id: UUID
    var title: String
    var type: DocumentType
    var content: String?         // 正文（本地文档时使用）
    var path: String?           // 路径（打开文档时使用）
    var createdAt: Date
    var lastModified: Date
    var fontSize: Double
    
    // Legacy fields for backward compatibility
    var contentFilePath: String? // for untitled, path to temp content file
    var filePath: String?        // for named files
    var isUntitled: Bool
}

final class DocumentModel: ObservableObject, Identifiable {
    let id: UUID
    @Published var title: String
    @Published var content: String
    @Published var fontSize: CGFloat
    @Published var isDirty: Bool
    @Published var type: DocumentType
    @Published var path: String?
    @Published var createdAt: Date
    @Published var lastModified: Date
    var fileURL: URL?

    init(id: UUID = UUID(), title: String, content: String = "", fileURL: URL? = nil, fontSize: CGFloat = 14, isDirty: Bool = false, type: DocumentType = .localDocument, path: String? = nil, createdAt: Date = Date(), lastModified: Date = Date()) {
        self.id = id
        self.title = title
        self.content = content
        self.fileURL = fileURL
        self.fontSize = fontSize
        self.isDirty = isDirty
        self.type = type
        self.path = path
        self.createdAt = createdAt
        self.lastModified = lastModified
    }

    var isUntitled: Bool { fileURL == nil }
    
    func updateLastModified() {
        lastModified = Date()
    }

    func toSession(tempContentPath: String?) -> DocumentSession {
        DocumentSession(
            id: id,
            title: title,
            type: type,
            content: type == .localDocument ? content : nil,
            path: type == .openedDocument ? (path ?? fileURL?.path) : nil,
            createdAt: createdAt,
            lastModified: lastModified,
            fontSize: Double(fontSize),
            // Legacy fields for backward compatibility
            contentFilePath: isUntitled ? tempContentPath : nil,
            filePath: fileURL?.path,
            isUntitled: isUntitled
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
        let now = Date()
        let doc = DocumentModel(title: timestamp, content: "", type: .localDocument, createdAt: now, lastModified: now)
        documents.append(doc)
        selectedDocumentID = doc.id
    }

    func open(url: URL) {
        // 如果是外部文件（非 JSON），在工作目录创建 JSON 包装，并从包装加载
        if url.pathExtension.lowercased() != "json" {
            if let wrapperURL = try? WorkingDirectoryManager.shared.createJSONWrapperForExternalFile(url),
               let doc = WorkingDirectoryManager.shared.loadDocumentFromJSON(at: wrapperURL) {
                documents.append(doc)
                selectedDocumentID = doc.id
                return
            }
        }
        // 若已是 JSON 或包装失败，则尝试直接按 JSON 加载
        if let doc = WorkingDirectoryManager.shared.loadDocumentFromJSON(at: url) {
            documents.append(doc)
            selectedDocumentID = doc.id
            return
        }
        // 兜底：当作普通文本（很少触达）
        let title = url.lastPathComponent
        let content = (try? String(contentsOf: url)) ?? ""
        let now = Date()
        let doc = DocumentModel(title: title, content: content, fileURL: url, isDirty: false, type: .openedDocument, path: url.path, createdAt: now, lastModified: now)
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


