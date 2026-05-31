//
//  SafariWebExtensionHandler.swift
//  jumpapp Extension
//

import SafariServices
import UIKit
import os.log

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    private let logger = Logger(subsystem: "com.cassaicus.jumpapp", category: "ExtensionHandler")
    private let downloader = GigaViewerDownloader()

    func beginRequest(with context: NSExtensionContext) {
        let item = context.inputItems.first as? NSExtensionItem
        let message = Self.extractMessage(from: item)

        Task {
            let responsePayload: [String: Any]
            do {
                responsePayload = try await self.handle(message: message)
            } catch let error as GigaViewerError {
                responsePayload = [
                    "ok": false,
                    "error": error.localizedDescription,
                ]
            } catch {
                responsePayload = [
                    "ok": false,
                    "error": error.localizedDescription,
                ]
            }

            let response = NSExtensionItem()
            if #available(iOS 15.0, macOS 11.0, *) {
                response.userInfo = [SFExtensionMessageKey: responsePayload]
            } else {
                response.userInfo = ["message": responsePayload]
            }
            context.completeRequest(returningItems: [response], completionHandler: nil)
        }
    }

    private func handle(message: [String: Any]?) async throws -> [String: Any] {
        guard let message else {
            return ["ok": false, "error": "メッセージがありません"]
        }

        let action = message["action"] as? String
        switch action {
        case "downloadEpisode":
            guard let url = message["url"] as? String else {
                return ["ok": false, "error": "URLが指定されていません"]
            }
            logger.info("Downloading episode: \(url, privacy: .public)")
            let meta = try await downloader.downloadEpisode(from: url)
            return [
                "ok": true,
                "episode": [
                    "id": meta.id,
                    "title": meta.title,
                    "seriesTitle": meta.seriesTitle,
                    "pageCount": meta.pageCount,
                ],
            ]
        case "ping":
            return ["ok": true, "pong": true]
        case "getEpisodeInfo":
            guard let episodeID = message["episodeID"] as? String else {
                return ["ok": false, "error": "episodeIDが指定されていません"]
            }
            let pageCount = EpisodeStore.pageURLs(for: episodeID).count
            return ["ok": true, "episodeID": episodeID, "downloaded": pageCount > 0, "pageCount": pageCount]
        case "getProcessedPage":
            guard let episodeID = message["episodeID"] as? String else {
                return ["ok": false, "error": "episodeIDが指定されていません"]
            }
            let pageIndex = (message["pageIndex"] as? Int) ?? 0
            guard let dataURL = Self.flippedPageDataURL(episodeID: episodeID, pageIndex: pageIndex) else {
                return ["ok": false, "error": "ページ画像が見つかりません"]
            }
            return ["ok": true, "episodeID": episodeID, "pageIndex": pageIndex, "dataURL": dataURL]
        default:
            return ["ok": false, "error": "不明な操作です"]
        }
    }

    /// PoC: read a stored page (upright) and draw a large page number in the
    /// center, then return it as a base64 JPEG data URL so the Safari content
    /// script can swap it in place of the live page image.
    private static func flippedPageDataURL(episodeID: String, pageIndex: Int) -> String? {
        let pages = EpisodeStore.pageURLs(for: episodeID)
        guard pageIndex >= 0, pageIndex < pages.count else { return nil }
        guard let data = try? Data(contentsOf: pages[pageIndex]),
              let image = UIImage(data: data) else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let size = image.size
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(at: .zero)

            let text = "\(pageIndex + 1)"
            let fontSize = min(size.width, size.height) * 0.5
            let font = UIFont.systemFont(ofSize: fontSize, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .foregroundColor: UIColor.systemRed,
                .strokeColor: UIColor.white,
                .strokeWidth: -6.0,
            ]
            let attributed = NSAttributedString(string: text, attributes: attributes)
            let textSize = attributed.size()
            let origin = CGPoint(
                x: (size.width - textSize.width) / 2,
                y: (size.height - textSize.height) / 2
            )
            attributed.draw(at: origin)
        }

        guard let jpeg = rendered.jpegData(compressionQuality: 0.85) else { return nil }
        return "data:image/jpeg;base64," + jpeg.base64EncodedString()
    }

    private static func extractMessage(from item: NSExtensionItem?) -> [String: Any]? {
        if #available(iOS 15.0, macOS 11.0, *) {
            return item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        }
        return item?.userInfo?["message"] as? [String: Any]
    }
}
