//
//  GigaViewerDownloader.swift
//  jumpapp Extension
//
//  GigaViewer episode fetch + tile unscramble (see eggplants/getjump).
//

import Foundation
import UIKit

enum GigaViewerError: LocalizedError {
    case invalidURL
    case unsupportedHost
    case network(Error)
    case invalidResponse
    case notPublic
    case noPages
    case imageProcessing

    var errorDescription: String? {
        switch self {
        case .invalidURL: "URLが正しくありません"
        case .unsupportedHost: "このサイトには対応していません（となりのヤングジャンプのみ）"
        case .network(let error): error.localizedDescription
        case .invalidResponse: "話の情報を取得できませんでした"
        case .notPublic: "この話は閲覧できません（ログイン・購入が必要な可能性があります）"
        case .noPages: "ページ画像が見つかりませんでした"
        case .imageProcessing: "画像の処理に失敗しました"
        }
    }
}

struct GigaViewerDownloader {
    private static let validHost = "tonarinoyj.jp"
    private static let userAgent =
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1"

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func downloadEpisode(from urlString: String) async throws -> EpisodeMeta {
        let normalized = try Self.normalizeEpisodeURL(urlString)
        let product = try await fetchReadableProduct(url: normalized)
        let pages = product.pageStructure.pages.filter { $0.src != nil }

        guard product.isPublic || product.hasPurchased else {
            throw GigaViewerError.notPublic
        }
        guard !pages.isEmpty else {
            throw GigaViewerError.noPages
        }

        var pageData: [Data] = []
        pageData.reserveCapacity(pages.count)

        for page in pages {
            guard let src = page.src, let imageURL = URL(string: src) else { continue }
            let data = try await downloadImageData(from: imageURL)
            let jpeg = try unscrambleJPEG(data: data)
            pageData.append(jpeg)
        }

        guard !pageData.isEmpty else {
            throw GigaViewerError.noPages
        }

        let episodeID = Self.episodeID(from: normalized)
        let seriesTitle = product.series?.title ?? "不明"
        let title = product.title

        let meta = EpisodeMeta(
            id: episodeID,
            title: title,
            seriesTitle: seriesTitle,
            sourceURL: normalized.absoluteString,
            downloadedAt: Date(),
            pageCount: pageData.count
        )

        try EpisodeStore.save(meta: meta, pageData: pageData)
        return meta
    }

    // MARK: - URL

    private static func normalizeEpisodeURL(_ urlString: String) throws -> URL {
        guard var components = URLComponents(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = components.host?.lowercased(),
              host == validHost || host.hasSuffix(".\(validHost)"),
              components.scheme == "https"
        else {
            throw GigaViewerError.invalidURL
        }

        if components.host != validHost {
            components.host = validHost
        }

        var path = components.path
        if path.hasSuffix(".json") {
            path = String(path.dropLast(5))
        }
        let match = path.range(of: #"^/episode/(\d+)$"#, options: .regularExpression)
        guard let match else {
            throw GigaViewerError.invalidURL
        }
        components.path = String(path[match])
        components.query = nil
        components.fragment = nil

        guard let url = components.url else {
            throw GigaViewerError.invalidURL
        }
        return url
    }

    private static func episodeID(from url: URL) -> String {
        url.lastPathComponent
    }

    // MARK: - API

    private func fetchReadableProduct(url: URL) async throws -> ReadableProduct {
        if let product = try? await fetchJSONProduct(jsonURL: url.appendingPathExtension("json")) {
            return product
        }
        return try await fetchHTMLProduct(pageURL: url)
    }

    private func fetchJSONProduct(jsonURL: URL) async throws -> ReadableProduct {
        let data = try await getData(from: jsonURL)
        let envelope = try JSONDecoder().decode(ReadableProductEnvelope.self, from: data)
        return envelope.readableProduct
    }

    private func fetchHTMLProduct(pageURL: URL) async throws -> ReadableProduct {
        let data = try await getData(from: pageURL)
        guard let html = String(data: data, encoding: .utf8) else {
            throw GigaViewerError.invalidResponse
        }

        let pattern = #"id="episode-json"[^>]*data-value="([^"]+)""#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: html, range: NSRange(html.startIndex..., in: html)),
              let jsonRange = Range(match.range(at: 1), in: html)
        else {
            throw GigaViewerError.invalidResponse
        }

        let encoded = String(html[jsonRange])
        guard let jsonData = encoded.data(using: .utf8) else {
            throw GigaViewerError.invalidResponse
        }

        let wrapper = try JSONDecoder().decode(EpisodeJSONWrapper.self, from: jsonData)
        return wrapper.readableProduct
    }

    private func getData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json,text/html", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                throw GigaViewerError.invalidResponse
            }
            return data
        } catch let error as GigaViewerError {
            throw error
        } catch {
            throw GigaViewerError.network(error)
        }
    }

    private func downloadImageData(from url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, (200 ..< 300).contains(http.statusCode) else {
                throw GigaViewerError.invalidResponse
            }
            return data
        } catch let error as GigaViewerError {
            throw error
        } catch {
            throw GigaViewerError.network(error)
        }
    }

    // MARK: - Unscramble (getjump / jump-downloader: div=4, mul=8)

    private func unscrambleJPEG(data: Data, div: Int = 4, mul: Int = 8) throws -> Data {
        guard let loaded = UIImage(data: data) else {
            throw GigaViewerError.imageProcessing
        }

        let image = Self.normalizedImage(loaded)
        guard let cgImage = image.cgImage else {
            throw GigaViewerError.imageProcessing
        }

        let imgWidth = cgImage.width
        let imgHeight = cgImage.height
        let fixedWidth = Int(Double(imgWidth) / Double(div * mul)) * mul
        let fixedHeight = Int(Double(imgHeight) / Double(div * mul)) * mul

        guard fixedWidth > 0, fixedHeight > 0 else {
            throw GigaViewerError.imageProcessing
        }

        // buff[column][row] — crop order matches getjump (outer x, inner y)
        var buff: [[CGImage]] = []
        for column in 0 ..< div {
            var columnTiles: [CGImage] = []
            for row in 0 ..< div {
                let cropRect = CGRect(
                    x: fixedWidth * column,
                    y: fixedHeight * row,
                    width: fixedWidth,
                    height: fixedHeight
                )
                guard let tile = cgImage.cropping(to: cropRect) else {
                    throw GigaViewerError.imageProcessing
                }
                columnTiles.append(tile)
            }
            buff.append(columnTiles)
        }

        let pixelSize = CGSize(width: imgWidth, height: imgHeight)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let unscrambled = UIGraphicsImageRenderer(size: pixelSize, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: pixelSize))

            // Paste buff[column][row] at (fixedWidth * row, fixedHeight * column)
            // — same as getjump: buff[y][x] → (fw*x, fh*y)
            var pasteX = 0
            var pasteY = 0
            for column in buff {
                for tile in column {
                    UIImage(cgImage: tile, scale: 1, orientation: .up).draw(
                        in: CGRect(
                            x: fixedWidth * pasteX,
                            y: fixedHeight * pasteY,
                            width: fixedWidth,
                            height: fixedHeight
                        )
                    )
                    pasteX += 1
                }
                pasteX = 0
                pasteY += 1
            }
        }

        guard let jpeg = unscrambled.jpegData(compressionQuality: 0.92) else {
            throw GigaViewerError.imageProcessing
        }
        return jpeg
    }

    /// Renders UIImage upright so CGImage pixel coordinates match UIKit drawing.
    private static func normalizedImage(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(at: .zero)
        }
    }
}

// MARK: - Codable models

private struct ReadableProductEnvelope: Decodable {
    let readableProduct: ReadableProduct
}

private struct EpisodeJSONWrapper: Decodable {
    let readableProduct: ReadableProduct
}

private struct ReadableProduct: Decodable {
    let title: String
    let isPublic: Bool
    let hasPurchased: Bool
    let series: SeriesInfo?
    let pageStructure: PageStructure

    struct SeriesInfo: Decodable {
        let title: String
    }

    struct PageStructure: Decodable {
        let pages: [Page]
    }

    struct Page: Decodable {
        let src: String?
        let type: String?
    }
}
