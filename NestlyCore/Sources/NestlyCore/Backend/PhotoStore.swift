import Foundation
import Storage
import Supabase

/// Activity photos in the private `activity-photos` bucket at `{family}/{activity}/{file}`.
/// Child photos live in `profile-photos` at `{family}/{profile}/{file}`.
/// Downloads are authenticated and cached on disk by bucket and storage path.
public struct PhotoStore: Sendable {
    public let backend: Backend

    public init(backend: Backend = .shared) { self.backend = backend }

    private var bucket: StorageFileApi { backend.client.storage.from(AppConfig.photoBucket) }
    private var profileBucket: StorageFileApi { backend.client.storage.from(AppConfig.profilePhotoBucket) }

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
        let data = try Data(contentsOf: Self.fileURL(localPath))
        let path = "\(familyId)/\(activityId)/\(newUUID()).jpg"
        try await bucket.upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        try? data.write(to: cachedURL(path, bucket: AppConfig.photoBucket))
        return path
    }

    /// Uploads a staged child photo. The returned path is what `profile.photo_path` stores.
    public func uploadProfile(localPath: String, familyId: String, profileId: String) async throws -> String {
        let data = try Data(contentsOf: Self.fileURL(localPath))
        let path = "\(familyId)/\(profileId)/\(newUUID()).jpg"
        try await profileBucket.upload(path, data: data, options: FileOptions(contentType: "image/jpeg", upsert: true))
        try? data.write(to: cachedURL(path, bucket: AppConfig.profilePhotoBucket))
        return path
    }

    /// Best-effort removal of one child photo. Local staged files are ignored.
    public func deleteProfile(path: String) async throws {
        guard !path.isEmpty, !Self.isLocal(path) else { return }
        _ = try await profileBucket.remove(paths: [path])
        try? FileManager.default.removeItem(at: cachedURL(path, bucket: AppConfig.profilePhotoBucket))
    }

    /// Image bytes for an activity storage path or a staged local path.
    public func data(_ uri: String) async throws -> Data {
        try await load(uri, from: bucket, bucketId: AppConfig.photoBucket)
    }

    /// Image bytes for a child-photo storage path or a staged local path.
    public func profileData(_ uri: String) async throws -> Data {
        try await load(uri, from: profileBucket, bucketId: AppConfig.profilePhotoBucket)
    }

    /// Removes every activity photo under `{familyId}/` (debug "Clear all data").
    public func deleteAll(familyId: String) async throws {
        try await removeAll(in: bucket, familyId: familyId)
    }

    /// Removes every child photo under `{familyId}/`.
    public func deleteAllProfiles(familyId: String) async throws {
        try await removeAll(in: profileBucket, familyId: familyId)
    }

    private static func fileURL(_ uri: String) -> URL {
        uri.hasPrefix("file:") ? URL(string: uri)! : URL(fileURLWithPath: uri)
    }

    /// Bucket name is part of the key so an activity path cannot collide with a child photo.
    private func cachedURL(_ storagePath: String, bucket bucketId: String) -> URL {
        Self.cacheDir.appendingPathComponent("\(bucketId)_\(storagePath.replacingOccurrences(of: "/", with: "_"))")
    }

    private func load(_ uri: String, from api: StorageFileApi, bucketId: String) async throws -> Data {
        if Self.isLocal(uri) { return try Data(contentsOf: Self.fileURL(uri)) }
        let cached = cachedURL(uri, bucket: bucketId)
        if let data = try? Data(contentsOf: cached) { return data }
        let data = try await api.download(path: uri)
        try? data.write(to: cached)
        return data
    }

    private func removeAll(in api: StorageFileApi, familyId: String) async throws {
        let folders = try await api.list(path: familyId)
        var paths: [String] = []
        for folder in folders {
            let files = try await api.list(path: "\(familyId)/\(folder.name)")
            paths += files.map { "\(familyId)/\(folder.name)/\($0.name)" }
            if files.isEmpty { paths.append("\(familyId)/\(folder.name)") }
        }
        var start = 0
        while start < paths.count {
            _ = try await api.remove(paths: Array(paths[start ..< min(paths.count, start + 100)]))
            start += 100
        }
    }
}
