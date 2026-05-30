//
//  AppGroup.swift
//  jumpapp Extension
//

import Foundation

enum AppGroup {
    static let identifier = "group.com.cassaicus.jumpapp"
    static let episodeDownloadedNotification = "com.cassaicus.jumpapp.episodeDownloaded"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: identifier)
    }

    static var episodesDirectory: URL? {
        containerURL?.appendingPathComponent("episodes", isDirectory: true)
    }
}
