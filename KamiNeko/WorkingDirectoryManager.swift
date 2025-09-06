//
//  WorkingDirectoryManager.swift
//  KamiNeko
//
//  Manages the user-selected working directory and basic file ops.
//

import Foundation
import AppKit

final class WorkingDirectoryManager {
    static let shared = WorkingDirectoryManager()

    private init() {}

    private let userDefaultsKey = "KamiNeko.WorkingDirectoryPath"
    private let bookmarkKey = "KamiNeko.WorkingDirectoryBookmark"
    private let fileManager = FileManager.default

    var directoryURL: URL? {
        get {
            let defaults = UserDefaults.standard
            if let bookmark = defaults.data(forKey: bookmarkKey) {
                var isStale = false
                if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                    return url
                }
            }
            if let path = defaults.string(forKey: userDefaultsKey) {
                return URL(fileURLWithPath: path)
            }
            return nil
        }
        set {
            let defaults = UserDefaults.standard
            if let url = newValue {
                defaults.set(url.path, forKey: userDefaultsKey)
                if let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
                    defaults.set(data, forKey: bookmarkKey)
                }
                NotificationCenter.default.post(name: .workingDirectoryChanged, object: nil, userInfo: ["url": url])
            } else {
                defaults.removeObject(forKey: userDefaultsKey)
                defaults.removeObject(forKey: bookmarkKey)
                NotificationCenter.default.post(name: .workingDirectoryChanged, object: nil)
            }
        }
    }

    @discardableResult
    func promptUserToChooseDirectory() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            directoryURL = url
            return url
        }
        return nil
    }

    func listFiles() -> [URL] {
        guard let dir = directoryURL else { return [] }
        var didStart = false
        if dir.startAccessingSecurityScopedResource() { didStart = true }
        defer { if didStart { dir.stopAccessingSecurityScopedResource() } }
        let urls = (try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.creationDateKey], options: [.skipsHiddenFiles])) ?? []
        return urls.filter { $0.hasDirectoryPath == false }
            .sorted { (a, b) in
                let ad = (try? a.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                let bd = (try? b.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? Date.distantPast
                return ad < bd
            }
    }

    func createNewEmptyFile(preferredBaseName: String? = nil, ext: String = "json") throws -> URL {
        guard let dir = directoryURL else { throw NSError(domain: "WorkingDirectory", code: 1, userInfo: [NSLocalizedDescriptionKey: "Working directory not set"]) }
        var didStart = false
        if dir.startAccessingSecurityScopedResource() { didStart = true }
        defer { if didStart { dir.stopAccessingSecurityScopedResource() } }
        let base: String = preferredBaseName ?? timestampString()
        var candidate = dir.appendingPathComponent("\(base).\(ext)")
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(index).\(ext)")
            index += 1
        }
        // 创建默认的本地文档JSON结构
        let now = Date()
        let defaultDoc = [
            "id": UUID().uuidString,
            "title": base,
            "type": "local_document",
            "content": "",
            "path": NSNull(),
            "createdAt": ISO8601DateFormatter().string(from: now),
            "lastModified": ISO8601DateFormatter().string(from: now),
            "fontSize": 14,
            "contentFilePath": NSNull(),
            "filePath": NSNull(),
            "isUntitled": true
        ] as [String : Any]
        
        let jsonData = try JSONSerialization.data(withJSONObject: defaultDoc, options: [.prettyPrinted, .withoutEscapingSlashes])
        try jsonData.write(to: candidate)
        return candidate
    }

    func renameFile(at url: URL, to newBaseName: String, ext: String = "json") throws -> URL {
        guard let dir = directoryURL else { throw NSError(domain: "WorkingDirectory", code: 2, userInfo: [NSLocalizedDescriptionKey: "Working directory not set"]) }
        var didStart = false
        if dir.startAccessingSecurityScopedResource() { didStart = true }
        defer { if didStart { dir.stopAccessingSecurityScopedResource() } }
        var dest = dir.appendingPathComponent("\(newBaseName).\(ext)")
        var index = 2
        while fileManager.fileExists(atPath: dest.path) {
            dest = dir.appendingPathComponent("\(newBaseName) \(index).\(ext)")
            index += 1
        }
        try fileManager.moveItem(at: url, to: dest)
        return dest
    }

    // 以目录安全访问包裹执行文件写入等操作
    func withDirectoryAccess<T>(_ work: () throws -> T) rethrows -> T {
        guard let dir = directoryURL else { return try work() }
        var didStart = false
        if dir.startAccessingSecurityScopedResource() { didStart = true }
        defer { if didStart { dir.stopAccessingSecurityScopedResource() } }
        return try work()
    }

    func isWhitespaceOnly(_ url: URL) -> Bool {
        return withDirectoryAccess {
            // 先用文件大小快速判断
            if let attrs = try? fileManager.attributesOfItem(atPath: url.path), let size = attrs[.size] as? NSNumber {
                if size.intValue == 0 { return true }
            }
            // 再尝试按 UTF-8 解码，无法解码则视为非空（避免误删二进制或非 UTF-8 文本）
            if let data = try? Data(contentsOf: url) {
                if let str = String(data: data, encoding: .utf8) {
                    return str.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                } else {
                    return false
                }
            }
            return false
        }
    }

    func deleteFile(at url: URL) throws {
        try withDirectoryAccess {
            if fileManager.fileExists(atPath: url.path) {
                try fileManager.removeItem(at: url)
            }
        }
    }

    // 从JSON文件加载文档信息
    func loadDocumentFromJSON(at url: URL) -> DocumentModel? {
        return withDirectoryAccess {
            guard let data = try? Data(contentsOf: url) else { return nil }
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            
            let id = UUID(uuidString: json["id"] as? String ?? "") ?? UUID()
            let title = json["title"] as? String ?? url.deletingPathExtension().lastPathComponent
            let typeString = json["type"] as? String ?? "local_document"
            let type = DocumentType(rawValue: typeString) ?? .localDocument
            let fontSize = json["fontSize"] as? Double ?? 14.0
            
            let dateFormatter = ISO8601DateFormatter()
            let createdAt = (json["createdAt"] as? String).flatMap { dateFormatter.date(from: $0) } ?? Date()
            let lastModified = (json["lastModified"] as? String).flatMap { dateFormatter.date(from: $0) } ?? Date()
            
            var content = ""
            var path: String? = nil
            // JSON 包装文件本身就是当前 url
            let fileURL: URL? = url
            
            switch type {
            case .localDocument:
                content = json["content"] as? String ?? ""
            case .openedDocument:
                path = json["path"] as? String
                if let pathString = path {
                    var externalURL = URL(fileURLWithPath: pathString)
                    // 优先使用安全书签恢复 URL 访问
                    if let b64 = json["securityBookmark"] as? String, let data = Data(base64Encoded: b64) {
                        var isStale = false
                        if let resolved = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &isStale) {
                            externalURL = resolved
                        }
                    }
                    var didStart = false
                    if externalURL.startAccessingSecurityScopedResource() { didStart = true }
                    defer { if didStart { externalURL.stopAccessingSecurityScopedResource() } }
                    content = (try? String(contentsOf: externalURL)) ?? ""
                }
            }
            
            return DocumentModel(
                id: id,
                title: title,
                content: content,
                fileURL: fileURL,
                fontSize: CGFloat(fontSize),
                isDirty: false,
                type: type,
                path: path,
                createdAt: createdAt,
                lastModified: lastModified
            )
        }
    }
    
    // 将文档保存为JSON文件
    func saveDocumentToJSON(_ document: DocumentModel, at url: URL) throws {
        try withDirectoryAccess {
            let jsonData = [
                "id": document.id.uuidString,
                "title": document.title,
                "type": document.type.rawValue,
                "content": document.type == .localDocument ? document.content : NSNull(),
                "path": document.type == .openedDocument ? (document.path as Any? ?? NSNull()) : NSNull(),
                "createdAt": ISO8601DateFormatter().string(from: document.createdAt),
                "lastModified": ISO8601DateFormatter().string(from: document.lastModified),
                "fontSize": Double(document.fontSize),
                "contentFilePath": NSNull(),
                "filePath": document.fileURL?.path ?? NSNull(),
                "isUntitled": document.isUntitled
            ] as [String : Any]
            
            let data = try JSONSerialization.data(withJSONObject: jsonData, options: [.prettyPrinted, .withoutEscapingSlashes])
            try data.write(to: url)
        }
    }

    /// 为外部文件创建一个放在工作目录的同名 JSON 包装文件（type = opened_document）
    /// 返回创建的 JSON 文件 URL
    func createJSONWrapperForExternalFile(_ externalURL: URL) throws -> URL {
        guard let dir = directoryURL else {
            throw NSError(domain: "WorkingDirectory", code: 3, userInfo: [NSLocalizedDescriptionKey: "Working directory not set"])
        }
        var didStart = false
        if dir.startAccessingSecurityScopedResource() { didStart = true }
        defer { if didStart { dir.stopAccessingSecurityScopedResource() } }

        let base = externalURL.deletingPathExtension().lastPathComponent
        var candidate = dir.appendingPathComponent("\(base).json")
        var index = 2
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("\(base) \(index).json")
            index += 1
        }

        let now = Date()
        let bookmarkData = try? externalURL.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
        let bookmarkBase64 = bookmarkData?.base64EncodedString()
        let wrapper: [String: Any] = [
            "id": UUID().uuidString,
            "title": externalURL.lastPathComponent,
            "type": "opened_document",
            "content": NSNull(),
            "path": externalURL.path,
            "createdAt": ISO8601DateFormatter().string(from: now),
            "lastModified": ISO8601DateFormatter().string(from: now),
            "fontSize": 14,
            "contentFilePath": NSNull(),
            "filePath": externalURL.path,
            "isUntitled": false,
            "securityBookmark": bookmarkBase64 ?? NSNull()
        ]
        let data = try JSONSerialization.data(withJSONObject: wrapper, options: [.prettyPrinted, .withoutEscapingSlashes])
        try data.write(to: candidate)
        return candidate
    }

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        // 年月日时分秒毫秒，无分隔符，例如：20250906212332123
        formatter.dateFormat = "yyyyMMddHHmmssSSS"
        return formatter.string(from: Date())
    }
}

extension Notification.Name {
    static let workingDirectoryChanged = Notification.Name("KamiNekoWorkingDirectoryChanged")
}


