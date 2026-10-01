import Foundation

/// Bing Visual Search（以图搜图）的结果。
struct VisualSearchResult: Sendable {
    /// 识别出的标签 / 实体名（可能直接就是人名）
    var tags: [String]
    /// 包含这张图的网页
    var pages: [VisualSearchPage]
    /// 相似图片
    var similarImages: [VisualSearchImage]

    var isEmpty: Bool { tags.isEmpty && pages.isEmpty && similarImages.isEmpty }
}

struct VisualSearchPage: Identifiable, Sendable {
    let id = UUID()
    var name: String
    var url: String
    var host: String?
}

struct VisualSearchImage: Identifiable, Sendable {
    let id = UUID()
    var name: String
    var thumbnailURL: String?
    var contentURL: String?
}

enum VisualSearchError: LocalizedError {
    case missingAPIKey
    case badStatus(Int, String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "还没有填写 Bing Visual Search 密钥（设置 → 网络识别）。"
        case .badStatus(let code, let body):
            return "服务返回 \(code)。\(body.isEmpty ? "" : "\n\(body)")"
        case .invalidResponse:
            return "返回内容无法解析。"
        }
    }
}

/// 以图搜图：把一张照片 POST 到 Bing Visual Search，解析出标签 / 网页 / 相似图。
///
/// 只有用户主动点「网络识别人像」时才会调用；App 其余部分仍然完全本地。
enum VisualSearchService {

    static let endpoint = URL(string: "https://api.bing.microsoft.com/v7.0/images/visualsearch")!

    static func search(imageData: Data, apiKey: String) async throws -> VisualSearchResult {
        let key = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { throw VisualSearchError.missingAPIKey }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "Ocp-Apim-Subscription-Key")
        let boundary = "Boundary-\(UUID().uuidString)"
        request.setValue("multipart/form-data; boundary=\(boundary)",
                         forHTTPHeaderField: "Content-Type")
        request.httpBody = multipartBody(imageData: imageData, boundary: boundary)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw VisualSearchError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data.prefix(400), encoding: .utf8) ?? ""
            throw VisualSearchError.badStatus(http.statusCode, body)
        }
        return try parse(data)
    }

    private static func multipartBody(imageData: Data, boundary: String) -> Data {
        var body = Data()
        func append(_ text: String) { body.append(Data(text.utf8)) }
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"image\"; filename=\"image.jpg\"\r\n")
        append("Content-Type: application/octet-stream\r\n\r\n")
        body.append(imageData)
        append("\r\n--\(boundary)--\r\n")
        return body
    }

    /// 解析 Bing Visual Search 的 JSON（抽出来便于单测）
    static func parse(_ data: Data) throws -> VisualSearchResult {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw VisualSearchError.invalidResponse
        }

        var tags: [String] = []
        var pages: [VisualSearchPage] = []
        var images: [VisualSearchImage] = []

        for tag in root["tags"] as? [[String: Any]] ?? [] {
            if let name = tag["displayName"] as? String, !name.isEmpty, !tags.contains(name) {
                tags.append(name)
            }
            for action in tag["actions"] as? [[String: Any]] ?? [] {
                let actionType = action["actionType"] as? String ?? ""
                guard let dataDict = action["data"] as? [String: Any],
                      let value = dataDict["value"] as? [[String: Any]] else { continue }
                if actionType == "PagesIncluding" {
                    for item in value {
                        let url = (item["hostPageUrl"] as? String)
                            ?? (item["contentUrl"] as? String) ?? ""
                        guard !url.isEmpty else { continue }
                        pages.append(VisualSearchPage(name: item["name"] as? String ?? url,
                                                      url: url,
                                                      host: item["hostPageDisplayUrl"] as? String))
                    }
                } else if actionType == "VisualSearch" || actionType == "SimilarImages" {
                    for item in value {
                        images.append(VisualSearchImage(name: item["name"] as? String ?? "",
                                                        thumbnailURL: item["thumbnailUrl"] as? String,
                                                        contentURL: item["contentUrl"] as? String))
                    }
                }
            }
        }

        return VisualSearchResult(tags: tags, pages: pages, similarImages: images)
    }
}
