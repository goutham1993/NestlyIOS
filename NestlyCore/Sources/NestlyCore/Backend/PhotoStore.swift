import Foundation
import Storage
import Supabase

/// Activity photos in the private `activity-photos` bucket at `{family}/{activity}/{file}`.
/// Downloads are authenticated and cached on disk by storage path.
public struct PhotoStore: Sendable {
    public let backend: Backend

    public init(backend: Backend = .shared) { self.backend = backend }

    private var bucket: StorageFileApi { backend.client.storage.from(AppConfig.photoBucket) }

    /// A path picked on this device that hasn't been uploaded yet.
    public static func isLocal(_ uri: String) -> Bool { uri.hasPrefix("/") || uri.hasPrefix("file:") }

    public static var cacheDir: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("photos", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Writes picked JPEG bytes to a temp file; the returned path goes into the draft until save.
    public static func stageLocal(_ jpeg: Data) throws -> String {
        let url = cacheDir.appendingPathComponent("pending-\(newUUID()).jpg")
        try jpeg.write(to: url)
        return url.path
    }

    public func upload(localPath: String, familyId: String, activityId: String) async throws -> String {
        let url = localPath.hasPrefix("file:") ? URL(string: localPath)! : URL(fileURLWithPath: localPath)
        let data = try Data(contentsOf: url)
        let path = "\(familyId)/\(activityId)/\(newUUID()).jpg"
        try await bucket.upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        try? data.write(to: cachedURL(path))
        return path
    }

    private func cachedURL(_ storagePath: String) -> URL {
        Self.cacheDir.appendingPathComponent(storagePath.replacingOccurrences(of: "/", with: "_"))
    }

    /// Image bytes for a storage path or a staged local path.
    public func data(_ uri: String) async throws -> Data {
        if Self.isLocal(uri) {
            let url = uri.hasPrefix("file:") ? URL(string: uri)! : URL(fileURLWithPath: uri)
            return try Data(contentsOf: url)
        }
        let cached = cachedURL(uri)
        if let data = try? Data(contentsOf: cached) { return data }
        let data = try await bucket.download(path: uri)
        try? data.write(to: cached)
        return data
    }

    /// Removes every object under `{familyId}/` (debug "Clear all data").
    public func deleteAll(familyId: String) async throws {
        let folders = try await bucket.list(path: familyId)
        var paths: [String] = []
        for folder in folders {
            let files = try await bucket.list(path: "\(familyId)/\(folder.name)")
            paths += files.map { "\(familyId)/\(folder.name)/\($0.name)" }
            if files.isEmpty { paths.append("\(familyId)/\(folder.name)") }
        }
        var start = 0
        while start < paths.count {
            _ = try await bucket.remove(paths: Array(paths[start ..< min(paths.count, start + 100)]))
            start += 100
        }
    }
}
