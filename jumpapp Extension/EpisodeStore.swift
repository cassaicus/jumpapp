//
//  EpisodeStore.swift
//  jumpapp Extension
//

import Foundation

struct EpisodeMeta: Codable, Identifiable, Hashable {
    let id: String
    let title: String
    let seriesTitle: String
    let sourceURL: String
    let downloadedAt: Date
    let pageCount: Int
}

enum EpisodeStoreError: Error {
    case appGroupUnavailable
    case episodeNotFound
}

enum EpisodeStore {
    private static let libraryFileName = "library.json"

    static func episodeDirectory(id: String) -> URL? {
        AppGroup.episodesDirectory?.appendingPathComponent(id, isDirectory: true)
    }

    static func pageURLs(for episodeID: String) -> [URL] {
        guard let directory = episodeDirectory(id: episodeID) else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil
        )) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    static func loadLibrary() -> [EpisodeMeta] {
        guard let container = AppGroup.containerURL else { return [] }
        let libraryURL = container.appendingPathComponent(libraryFileName)
        guard let data = try? Data(contentsOf: libraryURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([EpisodeMeta].self, from: data)) ?? []
    }

    @discardableResult
    static func save(meta: EpisodeMeta, pageData: [Data]) throws -> URL {
        guard let episodesRoot = AppGroup.episodesDirectory else {
            throw EpisodeStoreError.appGroupUnavailable
        }

        try FileManager.default.createDirectory(at: episodesRoot, withIntermediateDirectories: true)

        let episodeDir = episodesRoot.appendingPathComponent(meta.id, isDirectory: true)
        if FileManager.default.fileExists(atPath: episodeDir.path) {
            try FileManager.default.removeItem(at: episodeDir)
        }
        try FileManager.default.createDirectory(at: episodeDir, withIntermediateDirectories: true)

        let digitCount = max(3, String(pageData.count).count)
        for (index, data) in pageData.enumerated() {
            let name = String(format: "%0\(digitCount)d.jpg", index)
            try data.write(to: episodeDir.appendingPathComponent(name), options: .atomic)
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let metaData = try encoder.encode(meta)
        try metaData.write(to: episodeDir.appendingPathComponent("meta.json"), options: .atomic)

        var library = loadLibrary().filter { $0.id != meta.id }
        library.insert(meta, at: 0)
        let libraryURL = episodesRoot.deletingLastPathComponent().appendingPathComponent(libraryFileName)
        try encoder.encode(library).write(to: libraryURL, options: .atomic)

        CFNotificationCenterPostNotification(
            CFNotificationCenterGetDarwinNotifyCenter(),
            CFNotificationName(AppGroup.episodeDownloadedNotification as CFString),
            nil,
            nil,
            true
        )

        return episodeDir
    }
}
