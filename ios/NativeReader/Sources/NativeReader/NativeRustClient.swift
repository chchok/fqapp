import SwiftUI
import Foundation
import Combine
import Security

struct NativeHomeTab: Identifiable, Hashable {
    let id: Int
    let title: String
    let type: Int
}

struct NativeChapter: Identifiable, Hashable {
    let id: String
    let title: String
}

struct NativeBook: Identifiable, Hashable, Codable {
    let id: String
    let title: String
    let author: String
    let category: String
    let kind: String
    let coverURL: URL?

    var progress: String { UserDefaults.standard.string(forKey: "xiaoman.progress.\(id)").map { "读至 \($0)" } ?? "尚未阅读" }
    var color: Color {
        let palette: [Color] = [Color(red: 0.79, green: 0.56, blue: 0.43), Color(red: 0.40, green: 0.51, blue: 0.47), Color(red: 0.75, green: 0.69, blue: 0.49)]
        return palette[abs(id.hashValue) % palette.count]
    }
}

private let nativeFallbackHomeTabs = [
    NativeHomeTab(id: 0, title: "推荐", type: 2),
    NativeHomeTab(id: 1, title: "小说", type: 2),
    NativeHomeTab(id: 2, title: "短剧", type: 8),
    NativeHomeTab(id: 3, title: "漫剧", type: 24),
    NativeHomeTab(id: 4, title: "漫画", type: 9),
    NativeHomeTab(id: 5, title: "听书", type: 5)
]

@MainActor
final class NativeReadingStore: ObservableObject {
    @Published private(set) var results: [NativeBook] = []
    @Published private(set) var homeTabs: [NativeHomeTab] = nativeFallbackHomeTabs
    @Published private(set) var homeItems: [NativeBook] = []
    @Published private(set) var homeLoading = false
    @Published private(set) var homeMessage: String?
    @Published private(set) var shelf: [NativeBook] = UserDefaults.standard.data(forKey: "xiaoman.shelf").flatMap { try? JSONDecoder().decode([NativeBook].self, from: $0) } ?? []
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    private var initialized = false
    private var lastQuery = ""
    private var loadedHomeTab: Int?

    func recordProgress(for book: NativeBook, chapter: NativeChapter) {
        UserDefaults.standard.set(chapter.title, forKey: "xiaoman.progress.\(book.id)")
        UserDefaults.standard.set(chapter.id, forKey: "xiaoman.chapter.\(book.id)")
        objectWillChange.send()
    }

    func savedChapterId(for book: NativeBook) -> String? {
        UserDefaults.standard.string(forKey: "xiaoman.chapter.\(book.id)")
    }

    func addToShelf(_ book: NativeBook) {
        guard !shelf.contains(where: { $0.id == book.id }) else { return }
        shelf.insert(book, at: 0)
        if let data = try? JSONEncoder().encode(shelf) { UserDefaults.standard.set(data, forKey: "xiaoman.shelf") }
    }

    func directory(for book: NativeBook) async throws -> [NativeChapter] {
        try await initializeIfNeeded()
        return try await Task.detached(priority: .userInitiated) {
            try Self.fetchDirectory(book.id)
        }.value
    }

    func content(for chapter: NativeChapter, book: NativeBook) async throws -> String {
        try await initializeIfNeeded()
        return try await Task.detached(priority: .userInitiated) {
            try Self.fetchChapter(chapter.id, bookId: book.id)
        }.value
    }

    func loadHome(tabIndex: Int = 0, force: Bool = false) async {
        guard force || loadedHomeTab != tabIndex else { return }
        guard !homeLoading else { return }
        homeLoading = true
        homeMessage = nil
        defer { homeLoading = false }
        do {
            try await initializeIfNeeded()
            let tabs = homeTabs
              let tab = tabs.indices.contains(tabIndex) ? tabs[tabIndex] : nativeFallbackHomeTabs[0]
            guard tab.type > 1 else {
                homeItems = []
                homeMessage = "此分类暂不支持直接推荐，请使用搜索查看作品。"
                return
            }
            let result = try await Task.detached(priority: .userInitiated) {
                try Self.performHome(tab: tab, tabIndex: tabIndex)
            }.value
            homeItems = result.items
            loadedHomeTab = tabIndex
            if homeItems.isEmpty { homeMessage = "该分类暂时没有推荐内容" }
        } catch {
            homeMessage = error.localizedDescription
        }
    }

    func search(_ query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query != lastQuery else { return }
        lastQuery = query
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            try await initializeIfNeeded()
            results = try await Task.detached(priority: .userInitiated) {
                try Self.performSearch(query)
            }.value
            if results.isEmpty { message = "没有找到相关作品" }
        } catch {
            message = error.localizedDescription
        }
    }

    func mediaDetails(for item: NativeBook) async throws -> [String: String] {
        try await initializeIfNeeded()
        return try await Task.detached(priority: .userInitiated) {
            try Self.fetchMediaDetails(item)
        }.value
    }

    private func initializeIfNeeded() async throws {
        guard !initialized else { return }
        guard let config = Bundle.main.path(forResource: "config", ofType: "json"),
              let filters = Bundle.main.path(forResource: "filter", ofType: "json") else {
            throw NativeClientError.missingResources
        }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        let runtime = support.appendingPathComponent("FqRuntime", isDirectory: true)
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        let pool = runtime.appendingPathComponent("device_pool.json")
        let runtimePath = runtime.path
        try await Task.detached(priority: .userInitiated) {
            try Self.initialize(config: config, pool: pool.path, filters: filters, runtime: runtimePath)
        }.value
        initialized = true
    }


    nonisolated private static func provisionPoolKey() throws {
        let service = "com.chchok.xiaomanreading"
        let account = "device-pool-key"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var result: CFTypeRef?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        var key = result as? Data
        if status == errSecItemNotFound {
            var bytes = [UInt8](repeating: 0, count: 32)
            guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { throw NativeClientError.message("无法创建本地加密密钥") }
            let data = Data(bytes)
            var add: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account, kSecValueData as String: data]
            #if os(iOS)
            add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            #endif
            status = SecItemAdd(add as CFDictionary, nil)
            if status == errSecDuplicateItem {
                result = nil
                status = SecItemCopyMatching(query as CFDictionary, &result)
                key = result as? Data
            } else if status == errSecSuccess {
                key = data
            }
        }
        guard status == errSecSuccess, let key, key.count == 32 else { throw NativeClientError.message("无法读取本地加密密钥（\(status)）") }
        let provisioned = key.withUnsafeBytes { bytes -> UnsafeMutablePointer<CChar>? in
            guard let base = bytes.bindMemory(to: UInt8.self).baseAddress else { return nil }
            return fq_native_set_device_pool_key(base, key.count)
        }
        try decodeValue(provisioned)
    }

    nonisolated private static func initialize(config: String, pool: String, filters: String, runtime: String) throws {
        try config.withCString { configPtr in
            try pool.withCString { poolPtr in
                try filters.withCString { filterPtr in
                    try runtime.withCString { runtimePtr in
                        let pointer = fq_native_init(configPtr, poolPtr, filterPtr, runtimePtr, 0)
                        try decodeValue(pointer)
                    }
                }
            }
        }
    }

    nonisolated private static func performHome(tab: NativeHomeTab, tabIndex: Int) throws -> (tabs: [NativeHomeTab], items: [NativeBook]) {
        let payload = try performJSONRequest(path: "/api/v1/recommend/homepage", parameters: [
            URLQueryItem(name: "tab_type", value: String(tab.type)),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "tab_index", value: String(tabIndex)),
            URLQueryItem(name: "last_tab_index", value: String(tabIndex))
        ])
        return (nativeFallbackHomeTabs, parseBooks(payload, category: tab.title))
    }

    nonisolated private static func fetchMediaDetails(_ item: NativeBook) throws -> [String: String] {
        let route: String
        switch item.kind {
        case "video", "manju": route = "/api/v1/videos/\(item.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.id)/detail"
        case "audio": route = "/api/v1/audio/books/\(item.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.id)"
        case "manga": route = "/api/v1/books/\(item.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.id)/detail"
        default: route = "/api/v1/books/\(item.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? item.id)/detail"
        }
        let payload = try performJSONRequest(path: route, parameters: [])
        var result: [String: String] = ["作品类型": item.category]
        let names: [(String, String)] = [
            ("作者", "author"), ("简介", "series_intro"), ("作品简介", "abstract"),
            ("分类", "category_name"), ("状态", "creation_status"),
            ("集数", "episode_count"), ("评分", "score"), ("字数", "word_number"),
            ("追剧人数", "followed_cnt"), ("标签", "tags")
        ]
        func walk(_ value: Any, depth: Int) {
            guard depth < 8 else { return }
            if let map = value as? [String: Any] {
                for (label, key) in names where result[label] == nil {
                    if let text = string(map, keys: [key], fallback: [:]) { result[label] = text }
                    else if let list = map[key] as? [String], !list.isEmpty { result[label] = list.joined(separator: "、") }
                }
                for (key, child) in map where ["data", "book_data", "video_detail", "series_detail", "detail"].contains(key) {
                    walk(child, depth: depth + 1)
                }
            }
        }
        walk(payload, depth: 0)
        return result
    }

    nonisolated private static func performSearch(_ query: String) throws -> [NativeBook] {
        let payload = try performJSONRequest(path: "/api/v1/search", parameters: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "count", value: "10")
        ])
        return parseBooks(payload)
    }

    nonisolated private static func fetchDirectory(_ bookId: String) throws -> [NativeChapter] {
        let id = bookId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bookId
        let payload = try performJSONRequest(path: "/api/v1/books/\(id)/directory", parameters: [])
        return parseChapters(payload)
    }

    nonisolated private static func fetchChapter(_ chapterId: String, bookId: String) throws -> String {
        let id = chapterId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? chapterId
        let payload = try performJSONRequest(path: "/api/v1/chapters/\(id)/novel", parameters: [URLQueryItem(name: "book_id", value: bookId)])
        guard let root = payload as? [String: Any],
              let data = root["data"] as? [String: Any],
              data["content_decrypted"] as? Bool == true,
              let content = data["content"] as? String, !content.isEmpty else {
            throw NativeClientError.message("正文暂不可用，服务端没有确认解密成功")
        }
        return content
    }

    nonisolated private static func performJSONRequest(path: String, parameters: [URLQueryItem]) throws -> Any {
        var components = URLComponents()
        components.queryItems = parameters.isEmpty ? nil : parameters
        let query = components.percentEncodedQuery ?? ""
        let response = try "GET".withCString { methodPtr in
            try path.withCString { pathPtr in
                try query.withCString { queryPtr in
                    let envelope = fq_native_request(methodPtr, pathPtr, queryPtr, nil, 0)
                    return try decodeEnvelope(envelope)
                }
            }
        }
        guard (200..<300).contains(response.status) else { throw NativeClientError.backend(response.status) }
        return try JSONSerialization.jsonObject(with: response.body)
    }

    nonisolated private static func parseChapters(_ payload: Any) -> [NativeChapter] {
        var output: [NativeChapter] = []
        var seen = Set<String>()
        func visit(_ value: Any, depth: Int) {
            guard depth < 12 else { return }
            if let array = value as? [Any] {
                for (index, item) in array.enumerated() {
                    if let map = item as? [String: Any],
                       let id = string(map, keys: ["item_id", "itemId", "chapter_id", "id"], fallback: [:]),
                       !id.isEmpty, seen.insert(id).inserted {
                        let rawTitle = string(map, keys: ["title", "chapter_title", "name", "item_title"], fallback: [:]) ?? ""
                        output.append(NativeChapter(id: id, title: rawTitle.isEmpty ? "第\(index + 1)章" : rawTitle))
                    }
                    visit(item, depth: depth + 1)
                }
                return
            }
            guard let map = value as? [String: Any] else { return }
            for (key, child) in map where ["item_data_list", "chapterListWithVolume", "chapterList", "data", "chapter_list"].contains(key) {
                visit(child, depth: depth + 1)
            }
        }
        visit(payload, depth: 0)
        return output
    }

    nonisolated private static func decodeValue(_ pointer: UnsafeMutablePointer<CChar>?) throws {
        guard let pointer else { throw NativeClientError.emptyResponse }
        defer { fq_native_string_free(pointer) }
        let data = Data(bytes: pointer, count: strlen(pointer))
        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard envelope?["ok"] as? Bool == true else {
            throw NativeClientError.message(envelope?["error"] as? String ?? "Rust 核心初始化失败")
        }
    }

    nonisolated private static func decodeEnvelope(_ pointer: UnsafeMutablePointer<CChar>?) throws -> NativeHTTPResponse {
        guard let pointer else { throw NativeClientError.emptyResponse }
        defer { fq_native_string_free(pointer) }
        let data = Data(bytes: pointer, count: strlen(pointer))
        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard envelope?["ok"] as? Bool == true,
              let value = envelope?["value"] as? String,
              let valueData = value.data(using: .utf8),
              let payload = try JSONSerialization.jsonObject(with: valueData) as? [String: Any],
              let status = payload["status"] as? Int,
              let encoded = payload["bodyBase64"] as? String,
              let body = Data(base64Encoded: encoded) else {
            let error = envelope?["error"] as? String ?? "无法解析 Rust 响应"
            throw NativeClientError.message(error)
        }
        return NativeHTTPResponse(status: status, body: body)
    }

    nonisolated private static func parseBooks(_ payload: Any, category: String? = nil) -> [NativeBook] {
        var output: [NativeBook] = []
        var seen = Set<String>()
        func visit(_ value: Any, depth: Int) {
            guard depth < 14 else { return }
            if let array = value as? [Any] { array.forEach { visit($0, depth: depth + 1) }; return }
            guard let map = value as? [String: Any] else { return }
            if let nested = map["book_data"] as? [String: Any] {
                add(map, fallback: nested)
            } else {
                add(map, fallback: map)
            }
            for key in ["data", "search_tabs", "tab_list", "tab_item", "cell_data", "items", "book_list", "books", "result_list", "search_result_list", "data_list"] {
                if let child = map[key] { visit(child, depth: depth + 1) }
            }
            for (key, child) in map where ["data", "search_tabs", "tab_list", "tab_item", "cell_data", "items", "book_list", "books", "result_list", "search_result_list", "data_list"].contains(key) == false {
                if child is [Any] || child is [String: Any] { visit(child, depth: depth + 1) }
            }
        }
        func add(_ card: [String: Any], fallback: [String: Any]) {
            let id = string(card, keys: ["series_id_str", "pseries_id", "audio_book_id", "audio_id", "manga_id", "comic_id", "book_id", "video_id", "vid", "item_id", "id", "cell_id"], fallback: fallback) ?? ""
            guard !id.isEmpty, seen.insert(id).inserted else { return }
            let title = string(card, keys: ["title", "book_name", "name"], fallback: fallback) ?? ""
            guard !title.isEmpty else { return }
            let author = string(card, keys: ["author", "author_name"], fallback: fallback) ?? ""
            let cover = string(card, keys: ["series_cover", "cover", "thumb_url", "thumb", "cover_url", "poster"], fallback: fallback) ?? ""
            let kind: String
            if ["series_id", "series_id_str", "pseries_id", "video_id", "vid"].contains(where: { card[$0] != nil || fallback[$0] != nil }) { kind = "video" }
            else if ["audio_book_id", "audio_id", "album_id"].contains(where: { card[$0] != nil || fallback[$0] != nil }) { kind = "audio" }
            else if ["manga_id", "comic_id"].contains(where: { card[$0] != nil || fallback[$0] != nil }) { kind = "manga" }
            else { kind = "book" }
            let inferredCategory = kind == "video" ? "短剧" : kind == "audio" ? "听书" : kind == "manga" ? "漫画" : "小说"
            let displayKind = category ?? inferredCategory
            let finalKind = displayKind == "漫剧" ? "manju" : displayKind == "漫画" ? "manga" : displayKind == "听书" ? "audio" : displayKind == "短剧" ? "video" : kind
            output.append(NativeBook(id: id, title: title, author: author, category: displayKind, kind: finalKind, coverURL: URL(string: cover)))
        }
        visit(payload, depth: 0)
        return output
    }

    nonisolated private static func string(_ primary: [String: Any], keys: [String], fallback: [String: Any]) -> String? {
        for map in [primary, fallback] {
            for key in keys {
                if let value = map[key] as? String, !value.isEmpty { return value }
                if let value = map[key] as? NSNumber, value.intValue != 0 { return value.stringValue }
                if let value = map[key] as? [String: Any], let text = value["text"] as? String, !text.isEmpty { return text }
            }
        }
        return nil
    }
}

private struct NativeHTTPResponse { let status: Int; let body: Data }
private enum NativeClientError: LocalizedError {
    case missingResources, emptyResponse, backend(Int), message(String)
    var errorDescription: String? {
        switch self {
        case .missingResources: "应用资源缺少配置文件"
        case .emptyResponse: "Rust 核心没有返回数据"
        case .backend(let status): "服务请求失败（\(status)）"
        case .message(let text): text
        }
    }
}
