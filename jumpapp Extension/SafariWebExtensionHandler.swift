//
//  SafariWebExtensionHandler.swift
//  jumpapp Extension
//

import SafariServices
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
        default:
            return ["ok": false, "error": "不明な操作です"]
        }
    }

    private static func extractMessage(from item: NSExtensionItem?) -> [String: Any]? {
        if #available(iOS 15.0, macOS 11.0, *) {
            return item?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        }
        return item?.userInfo?["message"] as? [String: Any]
    }
}
