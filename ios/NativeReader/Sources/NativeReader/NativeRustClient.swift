import SwiftUI
import Foundation
import Combine
import Security

struct NativeHomeTab: Identifiable, Hashable {
    let id: Int
    let title: String
    let type: Int
}

struct NativeHomeRank: Identifiable, Hashable {
    let id: String
    let title: String
    let names: [String]
    let algorithms: [Int]
    let books: [NativeBook]
}

struct NativeCategoryChannel: Identifiable, Hashable {
    let id: String
    let title: String
}

struct NativeCategoryDimension: Identifiable, Hashable {
    let id: String
    let title: String
}

struct NativeCategoryTile: Identifiable, Hashable {
    let id: String
    let title: String
    let dimension: String
    let isHot: Bool
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
    let tagText: String?
    let tagColors: [String]?
    let episodeLabel: String?
    let recommendationReason: String?

    var progress: String { UserDefaults.standard.string(forKey: "xiaoman.progress.\(id)").map { "读至 \($0)" } ?? "尚未阅读" }
    var savedChapterTitle: String? { UserDefaults.standard.string(forKey: "xiaoman.progress.\(id)") }
    var progressRatio: Double { min(1, max(0, UserDefaults.standard.double(forKey: "xiaoman.progressRatio.\(id)"))) }
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
private let nativeShortDramaFeedTab = NativeHomeTab(id: 6, title: "短剧", type: 16)

@MainActor
final class NativeReadingStore: ObservableObject {
    @Published private(set) var results: [NativeBook] = []
    @Published private(set) var searchHistory: [String] = UserDefaults.standard.stringArray(forKey: "xiaoman.searchHistory") ?? []
    @Published private(set) var hotSearchTerms: [String] = []
    @Published private(set) var homeTabs: [NativeHomeTab] = nativeFallbackHomeTabs
    @Published var selectedHomeTab = 0
    @Published private(set) var homeItems: [NativeBook] = []
    @Published private(set) var homeRank: NativeHomeRank?
    @Published private(set) var homeLoading = false
    @Published private(set) var homeMessage: String?
    @Published private(set) var categoryChannels: [NativeCategoryChannel] = []
    @Published private(set) var categoryDimensions: [NativeCategoryDimension] = []
    @Published private(set) var categoryTiles: [NativeCategoryTile] = []
    @Published private(set) var categoriesLoading = false
    @Published private(set) var categoriesMessage: String?
    @Published private(set) var resourceBaseURL: URL?
    @Published private(set) var shelf: [NativeBook] = UserDefaults.standard.data(forKey: "xiaoman.shelf").flatMap { try? JSONDecoder().decode([NativeBook].self, from: $0) } ?? []
    @Published private(set) var readingHistory: [NativeBook] = UserDefaults.standard.data(forKey: "xiaoman.history").flatMap { try? JSONDecoder().decode([NativeBook].self, from: $0) } ?? []
    @Published private(set) var favorites: [NativeBook] = UserDefaults.standard.data(forKey: "xiaoman.favorites").flatMap { try? JSONDecoder().decode([NativeBook].self, from: $0) } ?? []
    @Published private(set) var todayReadMinutes = UserDefaults.standard.integer(forKey: NativeReadingStore.todayReadMinutesKey())
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    private var initialized = false
    private var lastQuery = ""
    private var loadedHomeTab: Int?
    private var homeLoadGeneration = 0
    private var categoryLoadGeneration = 0
    private var readingSessionStartedAt: Date?

    private static func todayReadMinutesKey() -> String {
        let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
        return "xiaoman.readMinutes.\(parts.year ?? 0)-\(parts.month ?? 0)-\(parts.day ?? 0)"
    }

    func beginReadingSession() {
        if readingSessionStartedAt == nil { readingSessionStartedAt = Date() }
    }

    func endReadingSession() {
        guard let started = readingSessionStartedAt else { return }
        readingSessionStartedAt = nil
        let minutes = Int(Date().timeIntervalSince(started) / 60)
        guard minutes > 0 else { return }
        todayReadMinutes += minutes
        UserDefaults.standard.set(todayReadMinutes, forKey: Self.todayReadMinutesKey())
        objectWillChange.send()
    }

    func recordProgress(for book: NativeBook, chapter: NativeChapter, progress: Double) {
        UserDefaults.standard.set(chapter.title, forKey: "xiaoman.progress.\(book.id)")
        UserDefaults.standard.set(chapter.id, forKey: "xiaoman.chapter.\(book.id)")
        UserDefaults.standard.set(min(1, max(0, progress)), forKey: "xiaoman.progressRatio.\(book.id)")
        readingHistory.removeAll { $0.id == book.id }
        readingHistory.insert(book, at: 0)
        if let data = try? JSONEncoder().encode(readingHistory) { UserDefaults.standard.set(data, forKey: "xiaoman.history") }
        objectWillChange.send()
    }

    func recordMediaHistory(_ item: NativeBook) {
        readingHistory.removeAll { $0.id == item.id }
        readingHistory.insert(item, at: 0)
        if let data = try? JSONEncoder().encode(readingHistory) { UserDefaults.standard.set(data, forKey: "xiaoman.history") }
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

    func toggleFavorite(_ item: NativeBook) {
        if favorites.contains(where: { $0.id == item.id }) { favorites.removeAll { $0.id == item.id } }
        else { favorites.insert(item, at: 0) }
        if let data = try? JSONEncoder().encode(favorites) { UserDefaults.standard.set(data, forKey: "xiaoman.favorites") }
        objectWillChange.send()
    }

    func clearReadingHistory() {
        readingHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: "xiaoman.history")
        objectWillChange.send()
    }

    func clearSearchHistory() {
        searchHistory.removeAll()
        UserDefaults.standard.removeObject(forKey: "xiaoman.searchHistory")
        objectWillChange.send()
    }

    func loadHotSearchTerms() async {
        guard hotSearchTerms.isEmpty else { return }
        do {
            try await initializeIfNeeded()
            hotSearchTerms = try await Task.detached(priority: .userInitiated) { try Self.fetchHotSearchTerms() }.value
        } catch { /* Search remains available without discovery data. */ }
    }

    func directory(for book: NativeBook) async throws -> [NativeChapter] {
        try await initializeIfNeeded()
        return try await Task.detached(priority: .userInitiated) {
            try Self.fetchDirectory(book.id, kind: book.kind)
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
        homeLoadGeneration += 1
        let generation = homeLoadGeneration
        homeLoading = true
        homeMessage = nil
        if loadedHomeTab != tabIndex { homeItems = []; homeRank = nil }
        defer { if generation == homeLoadGeneration { homeLoading = false } }
        do {
            try await initializeIfNeeded()
            let tabs = homeTabs
            let tab = tabs.indices.contains(tabIndex) ? tabs[tabIndex] : (tabIndex == nativeShortDramaFeedTab.id ? nativeShortDramaFeedTab : nativeFallbackHomeTabs[0])
            guard tab.type > 1 else {
                homeItems = []
                homeMessage = "此分类暂不支持直接推荐，请使用搜索查看作品。"
                return
            }
            let result = try await Task.detached(priority: .userInitiated) {
                try Self.performHome(tab: tab, tabIndex: tabIndex)
            }.value
            guard generation == homeLoadGeneration else { return }
            homeItems = result.items
            homeRank = result.rank
            loadedHomeTab = tabIndex
            if homeItems.isEmpty { homeMessage = "该分类暂时没有推荐内容" }
        } catch {
            if generation == homeLoadGeneration { homeMessage = error.localizedDescription }
        }
    }

    func search(_ query: String) async {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { lastQuery = ""; results = []; message = nil; return }
        guard query != lastQuery else { return }
        lastQuery = query
        isLoading = true
        message = nil
        results = []
        searchHistory.removeAll { $0 == query }
        searchHistory.insert(query, at: 0)
        searchHistory = Array(searchHistory.prefix(20))
        UserDefaults.standard.set(searchHistory, forKey: "xiaoman.searchHistory")
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

    func videoURL(for episode: NativeChapter) async throws -> URL {
        try await initializeIfNeeded()
        guard let base = resourceBaseURL?.absoluteString else { throw NativeClientError.message("媒体服务尚未启动") }
        return try await Task.detached(priority: .userInitiated) {
            try Self.fetchVideoURL(episode.id, resourceBase: base)
        }.value
    }

    func rankBoard(id: String, algorithm: Int, offset: Int = 0) async throws -> [NativeBook] {
        try await initializeIfNeeded()
        let encoded = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        return try await Task.detached(priority: .userInitiated) {
            let payload = try Self.performJSONRequest(path: "/api/v1/rank/\(encoded)", parameters: [
                URLQueryItem(name: "algo_type", value: String(algorithm)),
                URLQueryItem(name: "rank_sub_info_id", value: "0"),
                URLQueryItem(name: "offset", value: String(offset))
            ])
            return Self.parseBooks(payload, category: "小说")
        }.value
    }

    func loadCategories(channel: String = "1") async {
        categoryLoadGeneration += 1
        let generation = categoryLoadGeneration
        categoriesLoading = true
        categoriesMessage = nil
        categoryDimensions = []
        categoryTiles = []
        defer { if generation == categoryLoadGeneration { categoriesLoading = false } }
        do {
            try await initializeIfNeeded()
            let result = try await Task.detached(priority: .userInitiated) {
                try Self.fetchCategories(channel: channel)
            }.value
            guard generation == categoryLoadGeneration else { return }
            categoryChannels = result.channels
            categoryDimensions = result.dimensions
            categoryTiles = result.tiles
            if result.tiles.isEmpty { categoriesMessage = "此分类暂时没有条目" }
        } catch {
            if generation == categoryLoadGeneration { categoriesMessage = error.localizedDescription }
        }
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
        let resourceBase = try await Task.detached(priority: .userInitiated) {
            try Self.initialize(config: config, pool: pool.path, filters: filters, runtime: runtimePath)
            return try Self.resourceBaseURL()
        }.value
        guard let url = URL(string: resourceBase) else { throw NativeClientError.message("媒体服务地址无效") }
        resourceBaseURL = url
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

    nonisolated private static func resourceBaseURL() throws -> String {
        let pointer = fq_native_resource_base_url()
        guard let pointer else { throw NativeClientError.emptyResponse }
        defer { fq_native_string_free(pointer) }
        let data = Data(bytes: pointer, count: strlen(pointer))
        let envelope = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard envelope?["ok"] as? Bool == true, let value = envelope?["value"] as? String else {
            throw NativeClientError.message(envelope?["error"] as? String ?? "无法取得本地媒体服务地址")
        }
        return value
    }

    nonisolated private static func performHome(tab: NativeHomeTab, tabIndex: Int) throws -> (tabs: [NativeHomeTab], items: [NativeBook], rank: NativeHomeRank?) {
        let payload = try performJSONRequest(path: "/api/v1/recommend/homepage", parameters: [
            URLQueryItem(name: "tab_type", value: String(tab.type)),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "tab_index", value: String(tabIndex)),
            URLQueryItem(name: "last_tab_index", value: String(tabIndex))
        ])
        let contentKind = tab.type == 16 || tab.type == 8 ? "短剧" : tab.title
        return (nativeFallbackHomeTabs, parseBooks(payload, category: contentKind), parseHomeRank(payload, tabIndex: tabIndex))
    }

    nonisolated private static func parseHomeRank(_ payload: Any, tabIndex: Int) -> NativeHomeRank? {
        let root = payload as? [String: Any] ?? [:]
        let data = root["data"] as? [String: Any] ?? root
        var selected: Any = data
        if let tabs = data["tab_item"] as? [Any] {
            guard let index = (data["tab_index"] as? NSNumber)?.intValue,
                  tabs.indices.contains(index), index == tabIndex else { return nil }
            selected = tabs[index]
        }
        func find(_ node: Any, depth: Int) -> [String: Any]? {
            guard depth <= 12 else { return nil }
            if let list = node as? [Any] {
                for item in list { if let found = find(item, depth: depth + 1) { return found } }
            } else if let map = node as? [String: Any] {
                if map["rank_with_category_data"] is [String: Any] { return map }
                for child in map.values { if let found = find(child, depth: depth + 1) { return found } }
            }
            return nil
        }
        guard let card = find(selected, depth: 0),
              let rank = card["rank_with_category_data"] as? [String: Any] else { return nil }
        let entries = rank["rank_algo_list"] as? [[String: Any]] ?? []
        let valid = entries.compactMap { entry -> (String, Int)? in
            guard let name = entry["rank_name"] as? String, !name.isEmpty else { return nil }
            let algorithm = (entry["rank_algo"] as? NSNumber)?.intValue ?? Int("\(entry["rank_algo"] ?? "")")
            guard let algorithm, algorithm >= 0 else { return nil }
            return (name, algorithm)
        }
        let id = card["cell_id_str"] as? String ?? ""
        guard !id.isEmpty, !valid.isEmpty else { return nil }
        return NativeHomeRank(
            id: id,
            title: (card["cell_name"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "排行榜",
            names: valid.map(\.0),
            algorithms: valid.map(\.1),
            books: parseBooks(card, category: "小说")
        )
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

    nonisolated private static func fetchVideoURL(_ episodeId: String, resourceBase: String) throws -> URL {
        let id = episodeId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? episodeId
        let payload = try performJSONRequest(path: "/api/v1/videos/\(id)", parameters: [])
        var relativePath: String?
        func visit(_ value: Any, depth: Int) {
            guard depth < 8, relativePath == nil else { return }
            if let map = value as? [String: Any] {
                if let candidate = string(map, keys: ["video_url", "main_url"], fallback: [:]), !candidate.isEmpty {
                    relativePath = candidate
                    return
                }
                for (key, child) in map where ["data", "video_info", "video_list", "video_1"].contains(key) { visit(child, depth: depth + 1) }
            } else if let list = value as? [Any] { list.forEach { visit($0, depth: depth + 1) } }
        }
        visit(payload, depth: 0)
        guard let path = relativePath else { throw NativeClientError.message("服务端没有返回可播放视频地址") }
        if path.hasPrefix("/src/") {
            guard let url = URL(string: resourceBase + path) else { throw NativeClientError.message("视频缓存地址无效") }
            return url
        }
        guard let url = URL(string: path), ["http", "https", "file"].contains(url.scheme?.lowercased() ?? "") else {
            throw NativeClientError.message("服务端返回的视频地址无效")
        }
        return url
    }

    nonisolated private static func fetchCategories(channel: String) throws -> (channels: [NativeCategoryChannel], dimensions: [NativeCategoryDimension], tiles: [NativeCategoryTile]) {
        let payload = try performJSONRequest(path: "/api/v1/category", parameters: [URLQueryItem(name: "category_tab", value: channel)])
        guard let root = payload as? [String: Any], let data = root["data"] as? [String: Any] else { return ([], [], []) }
        let rule = data["rule"] as? [String: Any] ?? [:]
        var channels = (rule["tab"] as? [[String: Any]] ?? []).compactMap { raw -> NativeCategoryChannel? in
            guard let title = string(raw, keys: ["name", "title"], fallback: [:]), !title.isEmpty else { return nil }
            let id = string(raw, keys: ["value", "id"], fallback: [:]) ?? "1"
            return NativeCategoryChannel(id: id, title: title)
        }
        channels.sort { (Int($0.id) ?? 99) < (Int($1.id) ?? 99) }
        for (id, title) in [("6", "短剧"), ("5", "漫画")] where !channels.contains(where: { $0.id == id }) {
            channels.append(NativeCategoryChannel(id: id, title: title))
        }
        func scalar(_ value: Any?) -> String? {
            if let text = value as? String, !text.isEmpty { return text }
            if let number = value as? NSNumber { return number.stringValue }
            return nil
        }
        let dimensions = (rule["dim"] as? [[String: Any]] ?? []).compactMap { raw -> NativeCategoryDimension? in
            guard let title = string(raw, keys: ["name"], fallback: [:]), !title.isEmpty else { return nil }
            return NativeCategoryDimension(id: scalar(raw["value"]) ?? scalar(raw["id"]) ?? "", title: title)
        }
        let tiles = (data["down_category"] as? [[String: Any]] ?? []).compactMap { raw -> NativeCategoryTile? in
            guard let title = string(raw, keys: ["name", "title"], fallback: [:]), !title.isEmpty else { return nil }
            let id = scalar(raw["id"]) ?? scalar(raw["category_id"]) ?? title
            let dimension = scalar(raw["dim"]) ?? ""
            let hot = string(raw, keys: ["tag"], fallback: [:]) == "1"
            return NativeCategoryTile(id: id, title: title, dimension: dimension, isHot: hot)
        }
        return (channels, dimensions, tiles)
    }

    nonisolated private static func fetchHotSearchTerms() throws -> [String] {
        let payload = try performJSONRequest(path: "/api/v1/search/hot", parameters: [])
        guard let root = payload as? [String: Any], let cells = root["data"] as? [[String: Any]] else { return [] }
        var terms: [String] = []
        var seen = Set<String>()
        for cell in cells {
            guard let tags = cell["search_tag_data"] as? [[String: Any]] else { continue }
            for tag in tags {
                guard let title = string(tag, keys: ["tag_title"], fallback: [:]), !title.isEmpty, seen.insert(title).inserted else { continue }
                terms.append(title)
                if terms.count == 10 { return terms }
            }
        }
        return terms
    }

    nonisolated private static func performSearch(_ query: String) throws -> [NativeBook] {
        let payload = try performJSONRequest(path: "/api/v1/search", parameters: [
            URLQueryItem(name: "query", value: query),
            URLQueryItem(name: "offset", value: "0"),
            URLQueryItem(name: "count", value: "10")
        ])
        return parseBooks(payload)
    }

    nonisolated private static func fetchDirectory(_ bookId: String, kind: String) throws -> [NativeChapter] {
        let id = bookId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bookId
        let payload: Any
        if kind == "video" || kind == "manju" {
            payload = try performJSONRequest(path: "/api/v1/manga/videos/\(id)", parameters: [
                URLQueryItem(name: "offset", value: "1"),
                URLQueryItem(name: "count", value: "80"),
                URLQueryItem(name: "total", value: "80"),
                URLQueryItem(name: "pseries_type", value: "5")
            ])
        } else {
            payload = try performJSONRequest(path: "/api/v1/books/\(id)/directory", parameters: [])
        }
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
                       let id = string(map, keys: ["item_id", "itemId", "chapter_id", "video_id", "episode_id", "vid", "id"], fallback: [:]),
                       !id.isEmpty, seen.insert(id).inserted {
                        let rawTitle = string(map, keys: ["title", "episode_title", "chapter_title", "name", "item_title"], fallback: [:]) ?? ""
                        output.append(NativeChapter(id: id, title: rawTitle.isEmpty ? "第\(index + 1)集" : rawTitle))
                    }
                    visit(item, depth: depth + 1)
                }
                return
            }
            guard let map = value as? [String: Any] else { return }
            for (key, child) in map where ["episodes", "item_data_list", "item_list", "lists", "chapterListWithVolume", "chapterList", "data", "chapter_list", "video_data", "pseries_data"].contains(key) {
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
            let tagInfo = (card["tag_info"] as? [String: Any]) ?? (fallback["tag_info"] as? [String: Any])
            let tagText = tagInfo.flatMap { string($0, keys: ["text"], fallback: [:]) }
            let tagColors = tagInfo?["bg_color"] as? [String] ?? tagInfo?["dark_bg_color"] as? [String]
            let episodeLabel = string(card, keys: ["ep", "episode_text", "episode_list_text"], fallback: fallback)
            let reasonList = (card["recommend_reason_list"] as? [[String: Any]]) ?? (fallback["recommend_reason_list"] as? [[String: Any]]) ?? []
            let recommendationReason = reasonList.first?["content"] as? String
            let kind: String
            if ["series_id", "series_id_str", "pseries_id", "video_id", "vid"].contains(where: { card[$0] != nil || fallback[$0] != nil }) { kind = "video" }
            else if ["audio_book_id", "audio_id", "album_id"].contains(where: { card[$0] != nil || fallback[$0] != nil }) { kind = "audio" }
            else if ["manga_id", "comic_id"].contains(where: { card[$0] != nil || fallback[$0] != nil }) { kind = "manga" }
            else { kind = "book" }
            let inferredCategory = kind == "video" ? "短剧" : kind == "audio" ? "听书" : kind == "manga" ? "漫画" : "小说"
            let displayKind = category ?? inferredCategory
            let finalKind = displayKind == "漫剧" ? "manju" : displayKind == "漫画" ? "manga" : displayKind == "听书" ? "audio" : displayKind == "短剧" ? "video" : kind
            output.append(NativeBook(id: id, title: title, author: author, category: displayKind, kind: finalKind, coverURL: URL(string: cover), tagText: tagText, tagColors: tagColors, episodeLabel: episodeLabel, recommendationReason: recommendationReason))
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
