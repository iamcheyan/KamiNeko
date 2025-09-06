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

    func createNewEmptyFile(preferredBaseName: String? = nil, ext: String = "txt") throws -> URL {
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
        try Data().write(to: candidate)
        return candidate
    }

    func renameFile(at url: URL, to newBaseName: String, ext: String = "txt") throws -> URL {
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

    private func timestampString() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }
}

extension Notification.Name {
    static let workingDirectoryChanged = Notification.Name("KamiNekoWorkingDirectoryChanged")
}


