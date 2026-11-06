import SwiftUI
import Foundation
import Combine
import Security
import CoreFoundation

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

struct NativeChapter: Identifiable, Hashable, Codable {
    let id: String
    let title: String
}

struct NativeComicPage: Identifiable, Hashable {
    let url: URL
    var id: String { url.absoluteString }
}

struct NativeAudioSource {
    let url: URL
    let keyHex: String?
}

struct NativeAudioVoice: Identifiable, Hashable {
    let id: String
    let title: String
}

struct NativeBookComment: Identifiable, Hashable {
    let id: String
    let text: String
    let score: Int
    let diggCount: Int
    let replyCount: Int
    let createdAt: Date?
    let userName: String
}

struct NativeBookCommentPage {
    let comments: [NativeBookComment]
    let totalCount: Int
    let scoreCount: Int
    let scoreContext: String
    let hasMore: Bool
    let nextOffset: Int
}

struct NativeTextReplacementRule: Identifiable, Codable, Hashable {
    var id = UUID().uuidString
    var pattern = ""
    var replacement = ""
    var isRegex = false
    var enabled = true
}

private struct NativeLocalBookManifest: Codable {
    var book: NativeBook
    var chapters: [NativeChapter]
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

struct NativeLibraryBackup: Codable {
    var format = "fqapp.library-backup"
    var version = 1
    var createdAt: Int64
    var shelf: [NativeLibraryBackupEntry]
    var history: [NativeLibraryBackupEntry]
    var watched: [NativeLibraryBackupWatched]
    var excludedLocalRecords: Int?
}

struct NativeLibraryBackupEntry: Codable {
    var id: String
    var kind: String
    var title: String
    var cover: String
    var author: String
    var badge: String
    var ep: String
    var addedAt: Int64?
    var seriesId: String?
    var episodeId: String?
    var bookId: String?
    var chapterId: String?
    var toneId: String?
    var time: Int64?
    var episode: Int?
    var positionVersion: Int?
    var textOffset: Int?
    var position: Double?
    var maxScroll: Double?
    var progress: Double?
    var duration: Double?
    var rate: Double?
    var positionUnit: String?
    var autoAdvance: Bool?
    var completed: Bool?
    var fanqieImported: Bool?
}

struct NativeLibraryBackupWatched: Codable {
    var id: String
    var episodes: [String: Int64]
}

struct NativeLibraryBackupPreview {
    let shelfCount: Int
    let historyCount: Int
    let episodeCount: Int
    let excludedLocalRecords: Int
    let createdAt: Date
}

struct NativeLibraryBackupMergeResult {
    let shelf: Int
    let history: Int
    let episodes: Int
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
    @Published private(set) var watchedEpisodes: [String: [String: Int64]] = UserDefaults.standard.data(forKey: "xiaoman.watched").flatMap { try? JSONDecoder().decode([String: [String: Int64]].self, from: $0) } ?? [:]
    @Published private(set) var offlineBooks: [NativeBook] = []
    @Published private(set) var offlineCacheProgress: [String: Double] = [:]
    @Published private(set) var todayReadMinutes = UserDefaults.standard.integer(forKey: NativeReadingStore.todayReadMinutesKey())
    @Published private(set) var textReplacementEnabled = UserDefaults.standard.bool(forKey: "xiaoman.textReplacement.enabled")
    @Published private(set) var textReplacementRules: [NativeTextReplacementRule] = UserDefaults.standard.data(forKey: "xiaoman.textReplacement.rules").flatMap { try? JSONDecoder().decode([NativeTextReplacementRule].self, from: $0) } ?? []
    @Published private(set) var isLoading = false
    @Published private(set) var message: String?
    private var initialized = false
    private var lastQuery = ""
    private var loadedHomeTab: Int?
    private var homeLoadGeneration = 0
    private var categoryLoadGeneration = 0
    private var readingSessionStartedAt: Date?

    init() {
        offlineBooks = Self.loadOfflineBooks()
    }

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

    func saveTextReplacements(enabled: Bool, rules: [NativeTextReplacementRule]) throws {
        guard rules.count <= 50 else { throw NativeClientError.message("最多保存 50 条替换规则") }
        for rule in rules {
            guard !rule.pattern.isEmpty, rule.pattern.count <= 2048, rule.replacement.count <= 2048 else {
                throw NativeClientError.message("匹配内容不能为空，且匹配与替换内容不能超过 2048 字")
            }
            guard !rule.replacement.contains(where: { $0.isNewline }) else { throw NativeClientError.message("替换内容不能包含换行") }
            if rule.isRegex { do { _ = try NSRegularExpression(pattern: rule.pattern) } catch { throw NativeClientError.message("正则表达式无效：\(error.localizedDescription)") } }
        }
        let data = try JSONEncoder().encode(rules)
        UserDefaults.standard.set(data, forKey: "xiaoman.textReplacement.rules")
        UserDefaults.standard.set(enabled, forKey: "xiaoman.textReplacement.enabled")
        textReplacementRules = rules
        textReplacementEnabled = enabled
        objectWillChange.send()
    }

    func applyTextReplacements(to source: String) -> String {
        guard textReplacementEnabled else { return source }
        return textReplacementRules.filter(\.enabled).reduce(source) { text, rule in
            guard !rule.pattern.isEmpty else { return text }
            if rule.isRegex {
                guard let regex = try? NSRegularExpression(pattern: rule.pattern) else { return text }
                let range = NSRange(text.startIndex..<text.endIndex, in: text)
                return regex.stringByReplacingMatches(in: text, range: range, withTemplate: rule.replacement)
            }
            return text.replacingOccurrences(of: rule.pattern, with: rule.replacement)
        }
    }

    func recordTextPosition(for book: NativeBook, chapter: NativeChapter, chapterIndex: Int, chapterCount: Int, textOffset: Int, textLength: Int) {
        guard textLength >= 0 else { return }
        let offset = min(max(0, textOffset), textLength)
        let key = "xiaoman.textOffset.\(book.id).\(chapter.id)"
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        UserDefaults.standard.set(chapter.title, forKey: "xiaoman.progress.\(book.id)")
        UserDefaults.standard.set(chapter.id, forKey: "xiaoman.chapter.\(book.id)")
        UserDefaults.standard.set(offset, forKey: key)
        let withinChapter = textLength > 0 ? Double(offset) / Double(textLength) : 0
        UserDefaults.standard.set(min(1, max(0, (Double(chapterIndex) + withinChapter) / Double(max(1, chapterCount)))), forKey: "xiaoman.progressRatio.\(book.id)")
        UserDefaults.standard.set(now, forKey: "xiaoman.readTime.\(book.id)")
    }

    func savedTextOffset(for book: NativeBook, chapter: NativeChapter) -> Int {
        guard savedChapterId(for: book) == chapter.id else { return 0 }
        return max(0, UserDefaults.standard.integer(forKey: "xiaoman.textOffset.\(book.id).\(chapter.id)"))
    }

    func recordMediaHistory(_ item: NativeBook) {
        readingHistory.removeAll { $0.id == item.id }
        readingHistory.insert(item, at: 0)
        if let data = try? JSONEncoder().encode(readingHistory) { UserDefaults.standard.set(data, forKey: "xiaoman.history") }
        objectWillChange.send()
    }

    func recordComicProgress(for book: NativeBook, chapter: NativeChapter, chapterIndex: Int, page: Double, pageCount: Int, chapterCount: Int) {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        UserDefaults.standard.set(chapter.title, forKey: "xiaoman.progress.\(book.id)")
        UserDefaults.standard.set(chapter.id, forKey: "xiaoman.chapter.\(book.id)")
        UserDefaults.standard.set(min(1, max(0, (Double(chapterIndex) + page / Double(max(1, pageCount))) / Double(max(1, chapterCount)))), forKey: "xiaoman.progressRatio.\(book.id)")
        UserDefaults.standard.set(page, forKey: "xiaoman.comicPosition.\(book.id)")
        UserDefaults.standard.set(Double(pageCount), forKey: "xiaoman.comicMaxScroll.\(book.id)")
        UserDefaults.standard.set(chapterIndex, forKey: "xiaoman.comicEpisode.\(book.id)")
        UserDefaults.standard.set(now, forKey: "xiaoman.comicTime.\(book.id)")
        readingHistory.removeAll { $0.id == book.id }
        readingHistory.insert(book, at: 0)
        if let data = try? JSONEncoder().encode(readingHistory) { UserDefaults.standard.set(data, forKey: "xiaoman.history") }
        objectWillChange.send()
    }

    func recordAudioProgress(for book: NativeBook, chapter: NativeChapter, chapterIndex: Int, chapterCount: Int, position: Double, duration: Double, rate: Double) {
        guard position.isFinite, duration.isFinite else { return }
        UserDefaults.standard.set(chapter.title, forKey: "xiaoman.progress.\(book.id)")
        UserDefaults.standard.set(chapter.id, forKey: "xiaoman.chapter.\(book.id)")
        UserDefaults.standard.set(min(1, max(0, (Double(chapterIndex) + position / max(duration, 1)) / Double(max(chapterCount, 1)))), forKey: "xiaoman.progressRatio.\(book.id)")
        UserDefaults.standard.set(max(0, position), forKey: "xiaoman.audioPosition.\(book.id)")
        UserDefaults.standard.set(max(0, duration), forKey: "xiaoman.audioDuration.\(book.id)")
        UserDefaults.standard.set(min(10, max(0, rate)), forKey: "xiaoman.audioRate.\(book.id)")
        readingHistory.removeAll { $0.id == book.id }
        readingHistory.insert(book, at: 0)
        if let data = try? JSONEncoder().encode(readingHistory) { UserDefaults.standard.set(data, forKey: "xiaoman.history") }
        objectWillChange.send()
    }

    func savedAudioPosition(for book: NativeBook, chapter: NativeChapter) -> Double {
        guard savedChapterId(for: book) == chapter.id else { return 0 }
        return max(0, UserDefaults.standard.double(forKey: "xiaoman.audioPosition.\(book.id)"))
    }

    func savedAudioRate(for book: NativeBook) -> Float {
        let saved = UserDefaults.standard.double(forKey: "xiaoman.audioRate.\(book.id)")
        return saved > 0 ? Float(min(3, saved)) : 1
    }

    func savedChapterId(for book: NativeBook) -> String? {
        UserDefaults.standard.string(forKey: "xiaoman.chapter.\(book.id)")
    }

    func savedComicPage(for book: NativeBook, chapterIndex: Int) -> Int {
        guard UserDefaults.standard.integer(forKey: "xiaoman.comicEpisode.\(book.id)") == chapterIndex else { return 0 }
        return max(0, Int(UserDefaults.standard.double(forKey: "xiaoman.comicPosition.\(book.id)")))
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

    func removeFromShelf(_ items: [NativeBook]) {
        let keys = Set(items.map { "\($0.kind):\($0.id)" })
        shelf.removeAll { keys.contains("\($0.kind):\($0.id)") }
        favorites.removeAll { keys.contains("\($0.kind):\($0.id)") }
        let localIDs = Set(items.filter { $0.id.hasPrefix("local_") }.map(\.id))
        if !localIDs.isEmpty {
            readingHistory.removeAll { localIDs.contains($0.id) }
            if let data = try? JSONEncoder().encode(readingHistory) { UserDefaults.standard.set(data, forKey: "xiaoman.history") }
            for id in localIDs { removeLocalBookFiles(id) }
        }
        persistLocalLibraries()
        objectWillChange.send()
    }

    func importLocalBookFile(_ url: URL) throws -> NativeBook {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer { if hasAccess { url.stopAccessingSecurityScopedResource() } }
        let fileExtension = url.pathExtension.lowercased()
        guard fileExtension == "txt" || fileExtension == "epub" else { throw NativeClientError.message("仅支持导入 TXT 和 EPUB 文件") }
        let values = try url.resourceValues(forKeys: [.fileSizeKey])
        guard (values.fileSize ?? 0) <= 32 * 1024 * 1024 else { throw NativeClientError.message("请选择小于 32 MB 的 TXT 文件") }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        guard data.count <= 32 * 1024 * 1024 else { throw NativeClientError.message("请选择小于 32 MB 的 TXT 文件") }
        let stem = url.deletingPathExtension().lastPathComponent
        let parsedChapters: [(String, String)]
        let title: String
        let author: String
        let coverData: Data?
        let coverExtension: String?
        if fileExtension == "txt" {
            parsedChapters = try Self.parseLocalText(Self.decodeLocalText(data))
            title = Self.cleanedLocalTitle(stem)
            author = ""
            coverData = nil
            coverExtension = nil
        } else {
            let document = try NativeEPUBImporter.parse(data, fallbackTitle: stem)
            parsedChapters = document.chapters.map { ($0.title, $0.text) }
            title = document.title.trimmingCharacters(in: .whitespacesAndNewlines)
            author = document.author.trimmingCharacters(in: .whitespacesAndNewlines)
            coverData = document.cover
            coverExtension = document.coverExtension
        }
        let id = "local_\(Int(Date().timeIntervalSince1970))_\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())"
        let chapters = parsedChapters.enumerated().map { NativeChapter(id: "\(id):chapter:\($0.offset)", title: $0.element.0) }
        let folder = Self.localBookURL(id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        var coverURL: URL?
        if let coverData, let coverExtension {
            let url = folder.appendingPathComponent("cover.\(coverExtension)")
            if (try? coverData.write(to: url, options: .atomic)) != nil { coverURL = url }
        }
        let book = NativeBook(id: id, title: title.isEmpty ? stem : title, author: author, category: "本地导入", kind: "book", coverURL: coverURL, tagText: "本地", tagColors: nil, episodeLabel: "\(chapters.count)章", recommendationReason: nil)
        for (index, entry) in parsedChapters.enumerated() {
            try entry.1.write(to: folder.appendingPathComponent("chapter_\(index).txt"), atomically: true, encoding: .utf8)
        }
        do {
            try JSONEncoder().encode(NativeLocalBookManifest(book: book, chapters: chapters)).write(to: folder.appendingPathComponent("manifest.json"), options: .atomic)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
        addToShelf(book)
        return book
    }

    func removeFromReadingHistory(_ items: [NativeBook]) {
        let keys = Set(items.map { "\($0.kind):\($0.id)" })
        readingHistory.removeAll { keys.contains("\($0.kind):\($0.id)") }
        if let data = try? JSONEncoder().encode(readingHistory) { UserDefaults.standard.set(data, forKey: "xiaoman.history") }
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

    func makeLibraryBackup() throws -> Data {
        let now = Int64(Date().timeIntervalSince1970 * 1000)
        var excluded = 0
        var entries: [NativeLibraryBackupEntry] = []
        var seen = Set<String>()
        for item in shelf + favorites {
            if item.id.hasPrefix("local_") || !Self.backupIDIsValid(item.id) || !Self.backupKinds.contains(item.kind) {
                excluded += 1
                continue
            }
            let key = "\(item.kind):\(item.id)"
            guard seen.insert(key).inserted else { continue }
            entries.append(Self.backupEntry(item, addedAt: now))
        }
        var historySeen = Set<String>()
        let history = readingHistory.compactMap { item -> NativeLibraryBackupEntry? in
            if item.id.hasPrefix("local_") || !Self.backupIDIsValid(item.id) || !Self.backupKinds.contains(item.kind) {
                excluded += 1
                return nil
            }
            guard historySeen.insert("\(item.kind):\(item.id)").inserted else { return nil }
            var entry = Self.backupEntry(item)
            entry.bookId = UserDefaults.standard.string(forKey: "xiaoman.bookId.\(item.id)") ?? item.id
            entry.chapterId = UserDefaults.standard.string(forKey: "xiaoman.chapter.\(item.id)")
            entry.progress = item.progressRatio
            entry.time = now
            if item.kind == "book", let chapterID = entry.chapterId {
                entry.textOffset = UserDefaults.standard.integer(forKey: "xiaoman.textOffset.\(item.id).\(chapterID)")
            }
            if item.kind == "manga", let position = UserDefaults.standard.object(forKey: "xiaoman.comicPosition.\(item.id)") as? Double {
                entry.position = position
                entry.maxScroll = UserDefaults.standard.double(forKey: "xiaoman.comicMaxScroll.\(item.id)")
                entry.episode = UserDefaults.standard.integer(forKey: "xiaoman.comicEpisode.\(item.id)")
                entry.time = Int64(UserDefaults.standard.integer(forKey: "xiaoman.comicTime.\(item.id)"))
                entry.positionUnit = "comic-page"
            }
            if item.kind == "audio" {
                entry.position = UserDefaults.standard.double(forKey: "xiaoman.audioPosition.\(item.id)")
                entry.duration = UserDefaults.standard.double(forKey: "xiaoman.audioDuration.\(item.id)")
                entry.rate = UserDefaults.standard.object(forKey: "xiaoman.audioRate.\(item.id)") as? Double
            }
            return entry
        }
        let watched = watchedEpisodes.keys.sorted().compactMap { id -> NativeLibraryBackupWatched? in
            guard Self.backupIDIsValid(id), !id.hasPrefix("local_"), let episodes = watchedEpisodes[id] else {
                if id.hasPrefix("local_") { excluded += 1 }
                return nil
            }
            return NativeLibraryBackupWatched(id: id, episodes: episodes)
        }
        let backup = NativeLibraryBackup(createdAt: now, shelf: entries, history: history, watched: watched, excludedLocalRecords: excluded)
        let data = try JSONEncoder().encode(backup)
        guard data.count <= 16 * 1024 * 1024 else { throw NativeClientError.message("备份文件超过 16 MB") }
        return data
    }

    func previewLibraryBackup(_ data: Data) throws -> NativeLibraryBackupPreview {
        let backup = try Self.decodeLibraryBackup(data)
        return NativeLibraryBackupPreview(
            shelfCount: backup.shelf.count,
            historyCount: backup.history.count,
            episodeCount: backup.watched.reduce(0) { $0 + $1.episodes.count },
            excludedLocalRecords: backup.excludedLocalRecords ?? 0,
            createdAt: Date(timeIntervalSince1970: Double(backup.createdAt) / 1000)
        )
    }

    func mergeLibraryBackup(_ data: Data) throws -> NativeLibraryBackupMergeResult {
        let backup = try Self.decodeLibraryBackup(data)
        var shelfIDs = Set(shelf.map { "\($0.kind):\($0.id)" })
        var favoriteIDs = Set(favorites.map { "\($0.kind):\($0.id)" })
        var historyIDs = Set(readingHistory.map { "\($0.kind):\($0.id)" })
        var shelfAdded = 0
        var historyAdded = 0
        var episodeAdded = 0

        for entry in backup.shelf {
            let item = Self.book(from: entry)
            let key = "\(item.kind):\(item.id)"
            if item.kind == "book" || item.kind == "audio" {
                if shelfIDs.insert(key).inserted { shelf.append(item); shelfAdded += 1 }
            } else if favoriteIDs.insert(key).inserted {
                favorites.append(item)
                shelfAdded += 1
            }
        }
        for entry in backup.history {
            let item = Self.book(from: entry)
            let key = "\(item.kind):\(item.id)"
            guard historyIDs.insert(key).inserted else { continue }
            readingHistory.append(item)
            historyAdded += 1
            if let chapterID = entry.chapterId {
                UserDefaults.standard.set(chapterID, forKey: "xiaoman.chapter.\(item.id)")
                UserDefaults.standard.set(entry.bookId ?? item.id, forKey: "xiaoman.bookId.\(item.id)")
                UserDefaults.standard.set("已恢复阅读进度", forKey: "xiaoman.progress.\(item.id)")
                if item.kind == "book", let textOffset = entry.textOffset {
                    UserDefaults.standard.set(textOffset, forKey: "xiaoman.textOffset.\(item.id).\(chapterID)")
                }
            }
            if let progress = entry.progress { UserDefaults.standard.set(progress, forKey: "xiaoman.progressRatio.\(item.id)") }
            if let position = entry.position { UserDefaults.standard.set(position, forKey: "xiaoman.comicPosition.\(item.id)") }
            if let maxScroll = entry.maxScroll { UserDefaults.standard.set(maxScroll, forKey: "xiaoman.comicMaxScroll.\(item.id)") }
            if let episode = entry.episode { UserDefaults.standard.set(episode, forKey: "xiaoman.comicEpisode.\(item.id)") }
            if let time = entry.time { UserDefaults.standard.set(time, forKey: "xiaoman.comicTime.\(item.id)") }
            if item.kind == "audio" {
                if let position = entry.position { UserDefaults.standard.set(position, forKey: "xiaoman.audioPosition.\(item.id)") }
                if let duration = entry.duration { UserDefaults.standard.set(duration, forKey: "xiaoman.audioDuration.\(item.id)") }
                if let rate = entry.rate { UserDefaults.standard.set(rate, forKey: "xiaoman.audioRate.\(item.id)") }
            }
        }
        for record in backup.watched {
            var existing = watchedEpisodes[record.id] ?? [:]
            for (episodeID, timestamp) in record.episodes where existing[episodeID] == nil {
                existing[episodeID] = timestamp
                episodeAdded += 1
            }
            watchedEpisodes[record.id] = existing
        }
        persistLocalLibraries()
        if let data = try? JSONEncoder().encode(watchedEpisodes) { UserDefaults.standard.set(data, forKey: "xiaoman.watched") }
        objectWillChange.send()
        return NativeLibraryBackupMergeResult(shelf: shelfAdded, history: historyAdded, episodes: episodeAdded)
    }

    func markEpisodeWatched(bookID: String, episodeID: String) {
        var entries = watchedEpisodes[bookID] ?? [:]
        entries[episodeID] = Int64(Date().timeIntervalSince1970 * 1000)
        watchedEpisodes[bookID] = entries
        if let data = try? JSONEncoder().encode(watchedEpisodes) { UserDefaults.standard.set(data, forKey: "xiaoman.watched") }
        objectWillChange.send()
    }

    private func persistLocalLibraries() {
        if let data = try? JSONEncoder().encode(shelf) { UserDefaults.standard.set(data, forKey: "xiaoman.shelf") }
        if let data = try? JSONEncoder().encode(favorites) { UserDefaults.standard.set(data, forKey: "xiaoman.favorites") }
        if let data = try? JSONEncoder().encode(readingHistory) { UserDefaults.standard.set(data, forKey: "xiaoman.history") }
    }

    private static let backupKinds: Set<String> = ["book", "audio", "manga", "video", "manju"]

    private static func backupIDIsValid(_ value: String) -> Bool {
        value.range(of: "^[a-zA-Z0-9_-]{1,128}$", options: .regularExpression) != nil
    }

    private static func backupEntry(_ item: NativeBook, addedAt: Int64? = nil) -> NativeLibraryBackupEntry {
        let cover = item.coverURL.flatMap { url -> String? in
            guard ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.user == nil, url.password == nil else { return nil }
            return url.absoluteString
        } ?? ""
        return NativeLibraryBackupEntry(id: item.id, kind: item.kind, title: String(item.title.prefix(8192)), cover: cover,
                                        author: String(item.author.prefix(8192)), badge: String((item.tagText ?? "").prefix(8192)),
                                        ep: String((item.episodeLabel ?? "").prefix(8192)), addedAt: addedAt)
    }

    private static func book(from entry: NativeLibraryBackupEntry) -> NativeBook {
        NativeBook(id: entry.id, title: entry.title, author: entry.author, category: entry.kind, kind: entry.kind,
                   coverURL: entry.cover.isEmpty ? nil : URL(string: entry.cover), tagText: entry.badge.isEmpty ? nil : entry.badge, tagColors: nil,
                   episodeLabel: entry.ep.isEmpty ? nil : entry.ep, recommendationReason: nil)
    }

    private static func decodeLibraryBackup(_ data: Data) throws -> NativeLibraryBackup {
        guard data.count <= 16 * 1024 * 1024 else { throw NativeClientError.message("备份文件超过 16 MB") }
        let backup: NativeLibraryBackup
        do { backup = try JSONDecoder().decode(NativeLibraryBackup.self, from: data) }
        catch { throw NativeClientError.message("文件不是有效的 FQApp JSON 备份") }
        guard backup.format == "fqapp.library-backup", backup.version == 1 else {
            throw NativeClientError.message("不是受支持的 FQApp 备份文件")
        }
        guard (0...8_640_000_000_000_000).contains(backup.createdAt), backup.shelf.count <= 10000, backup.history.count <= 10000,
              backup.watched.count <= 10000, (backup.excludedLocalRecords ?? 0) >= 0 else {
            throw NativeClientError.message("备份记录数量或时间字段无效")
        }
        func validate(_ entry: NativeLibraryBackupEntry, shelf: Bool) throws {
            guard backupIDIsValid(entry.id), backupKinds.contains(entry.kind), !entry.id.hasPrefix("local_"),
                  [entry.title, entry.cover, entry.author, entry.badge, entry.ep].allSatisfy({ $0.count <= 8192 }) else {
                throw NativeClientError.message("备份含无效作品记录")
            }
            if shelf, entry.addedAt == nil { throw NativeClientError.message("备份收藏记录缺少时间") }
            if let addedAt = entry.addedAt, !(0...8_640_000_000_000_000).contains(addedAt) { throw NativeClientError.message("备份收藏时间无效") }
            for id in [entry.chapterId, entry.bookId, entry.seriesId, entry.episodeId, entry.toneId].compactMap({ $0 }) where !backupIDIsValid(id) {
                throw NativeClientError.message("备份章节或作品标识无效")
            }
            if !(0...8_640_000_000_000_000).contains(entry.time ?? 0) || (entry.episode ?? 0) < 0 || (entry.positionVersion ?? 0) < 0 || (entry.textOffset ?? 0) < 0 {
                throw NativeClientError.message("备份进度字段无效")
            }
            let positions = [entry.position, entry.maxScroll, entry.duration].compactMap { $0 }
            if positions.contains(where: { !$0.isFinite || $0 < 0 || $0 > 1_000_000_000_000 }) {
                throw NativeClientError.message("备份进度字段无效")
            }
            if let rate = entry.rate, !rate.isFinite || rate < 0 || rate > 10 { throw NativeClientError.message("备份播放速度无效") }
            if let progress = entry.progress, !progress.isFinite || !(0...1).contains(progress) { throw NativeClientError.message("备份阅读进度无效") }
            if let unit = entry.positionUnit, unit != "comic-page" || entry.kind != "manga" { throw NativeClientError.message("备份漫画进度单位无效") }
            if let cover = URL(string: entry.cover), !entry.cover.isEmpty {
                guard ["http", "https"].contains(cover.scheme?.lowercased() ?? ""), cover.host != nil, cover.user == nil, cover.password == nil else {
                    throw NativeClientError.message("备份封面地址无效")
                }
            }
        }
        var keys = Set<String>()
        for entry in backup.shelf {
            try validate(entry, shelf: true)
            guard keys.insert("\(entry.kind):\(entry.id)").inserted else { throw NativeClientError.message("备份中存在重复收藏") }
        }
        keys.removeAll()
        for entry in backup.history {
            try validate(entry, shelf: false)
            guard keys.insert("\(entry.kind):\(entry.id)").inserted else { throw NativeClientError.message("备份中存在重复进度") }
        }
        keys.removeAll()
        var episodeCount = 0
        for record in backup.watched {
            guard backupIDIsValid(record.id), keys.insert(record.id).inserted else { throw NativeClientError.message("备份已看记录无效或重复") }
            episodeCount += record.episodes.count
            guard episodeCount <= 100000 else { throw NativeClientError.message("已看剧集超过 100000 条") }
            for (episodeID, timestamp) in record.episodes where !backupIDIsValid(episodeID) || !(0...8_640_000_000_000_000).contains(timestamp) {
                throw NativeClientError.message("备份剧集记录无效")
            }
        }
        return backup
    }

    func loadHotSearchTerms() async {
        guard hotSearchTerms.isEmpty else { return }
        do {
            try await initializeIfNeeded()
            hotSearchTerms = try await Task.detached(priority: .userInitiated) { try Self.fetchHotSearchTerms() }.value
        } catch { /* Search remains available without discovery data. */ }
    }

    func directory(for book: NativeBook) async throws -> [NativeChapter] {
        if book.id.hasPrefix("local_") {
            let data = try Data(contentsOf: Self.localBookURL(book.id).appendingPathComponent("manifest.json"))
            return try JSONDecoder().decode(NativeLocalBookManifest.self, from: data).chapters
        }
        do {
            try await initializeIfNeeded()
            let chapters = try await Task.detached(priority: .userInitiated) {
                try Self.fetchDirectory(book.id, kind: book.kind)
            }.value
            Self.saveOfflineDirectory(book, chapters: chapters)
            refreshOfflineBooks()
            return chapters
        } catch {
            if let cached = Self.loadOfflineDirectory(bookID: book.id), !cached.isEmpty { return cached }
            throw error
        }
    }

    func content(for chapter: NativeChapter, book: NativeBook) async throws -> String {
        if book.id.hasPrefix("local_"), let index = chapter.id.range(of: #":chapter:(\d+)$"#, options: .regularExpression).flatMap({ Int(chapter.id[$0].split(separator: ":").last ?? "") }) {
            return try String(contentsOf: Self.localBookURL(book.id).appendingPathComponent("chapter_\(index).txt"), encoding: .utf8)
        }
        do {
            try await initializeIfNeeded()
            let text = try await Task.detached(priority: .userInitiated) {
                try Self.fetchChapter(chapter.id, bookId: book.id)
            }.value
            Self.saveOfflineContent(text, book: book, chapter: chapter)
            refreshOfflineBooks()
            return text
        } catch {
            if let cached = Self.loadOfflineContent(bookID: book.id, chapterID: chapter.id) { return cached }
            throw error
        }
    }

    func cacheBook(_ book: NativeBook) async throws {
        let chapters = try await directory(for: book)
        guard !chapters.isEmpty else { throw NativeClientError.message("作品目录为空，无法缓存") }
        offlineCacheProgress[book.id] = 0
        defer { offlineCacheProgress[book.id] = nil }
        for (index, chapter) in chapters.enumerated() {
            _ = try await content(for: chapter, book: book)
            offlineCacheProgress[book.id] = Double(index + 1) / Double(chapters.count)
        }
        refreshOfflineBooks()
    }

    func removeOfflineCache(for book: NativeBook) {
        try? FileManager.default.removeItem(at: Self.offlineBookURL(book.id))
        refreshOfflineBooks()
    }

    func cachedChapterCount(for book: NativeBook) -> Int {
        let directory = Self.offlineBookURL(book.id).appendingPathComponent("chapters", isDirectory: true)
        return (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).count) ?? 0
    }

    func offlineCacheSize(for book: NativeBook) -> Int64 {
        let root = Self.offlineBookURL(book.id)
        guard let enumerator = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        let sizes = enumerator.compactMap { element -> Int? in
            guard let url = element as? URL, let values = try? url.resourceValues(forKeys: [.fileSizeKey]) else { return nil }
            return values.fileSize
        }
        return sizes.reduce(Int64(0)) { $0 + Int64($1) }
    }

    private func refreshOfflineBooks() { offlineBooks = Self.loadOfflineBooks() }

    private static func offlineBookURL(_ id: String) -> URL {
        let safe = Data(id.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "")
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("XiaomanOffline", isDirectory: true).appendingPathComponent(safe, isDirectory: true)
    }

    private static func localBookURL(_ id: String) -> URL {
        let safe = Data(id.utf8).base64EncodedString().replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "=", with: "")
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        return support.appendingPathComponent("XiaomanLocalBooks", isDirectory: true).appendingPathComponent(safe, isDirectory: true)
    }

    private func removeLocalBookFiles(_ id: String) { try? FileManager.default.removeItem(at: Self.localBookURL(id)) }

    private static func decodeLocalText(_ data: Data) throws -> String {
        if data.starts(with: [0xEF, 0xBB, 0xBF]), let value = String(data: data.dropFirst(3), encoding: .utf8) { return value }
        if data.starts(with: [0xFF, 0xFE]), let value = String(data: data.dropFirst(2), encoding: .utf16LittleEndian) { return value }
        if data.starts(with: [0xFE, 0xFF]), let value = String(data: data.dropFirst(2), encoding: .utf16BigEndian) { return value }
        if let value = String(data: data, encoding: .utf8) { return value }
        let charset = CFStringConvertIANACharSetNameToEncoding("GB18030" as CFString)
        let encoding = CFStringConvertEncodingToNSStringEncoding(charset)
        if let value = NSString(data: data, encoding: encoding) as String? { return value }
        throw NativeClientError.message("无法识别 TXT 编码")
    }

    private static func parseLocalText(_ source: String) throws -> [(String, String)] {
        let normalized = source.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n").replacingOccurrences(of: "\0", with: "").replacingOccurrences(of: "\u{000C}", with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw NativeClientError.message("TXT 正文为空") }
        let lines = normalized.components(separatedBy: "\n")
        let pattern = #"^\s*(?:第[0-9０-９零〇一二三四五六七八九十百千万两]+[章节回卷部集篇].*|[0-9]{1,5}[.、 ]+\S.*|卷[0-9０-９零〇一二三四五六七八九十百千万两]+.*|序章|序言|楔子|前言|后记|尾声|番外(?:第.*)?|正文)\s*$"#
        let regex = try NSRegularExpression(pattern: pattern)
        let headings = lines.indices.filter { index in
            let line = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return !line.isEmpty && line.count <= 100 && regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
        }
        guard headings.count <= 20_000 else { throw NativeClientError.message("章节数量超过支持上限") }
        let starts = headings.count > 1 ? headings : (headings.isEmpty ? [] : [headings[0]])
        var result: [(String, String)] = []
        if headings.count > 1 {
            for index in headings.indices {
                let start = headings[index]
                let end = index + 1 < headings.count ? headings[index + 1] : lines.count
                let text = lines[start..<end].joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                let title = lines[start].trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty && text != title { result.append((title, text)) }
            }
        } else {
            let title = starts.first.map { lines[$0].trimmingCharacters(in: .whitespacesAndNewlines) } ?? "正文"
            if normalized != title { result.append((title, normalized)) }
        }
        guard !result.isEmpty else { throw NativeClientError.message("TXT 中没有可导入的正文") }
        return result
    }

    private static func cleanedLocalTitle(_ title: String) -> String {
        title.replacingOccurrences(of: #"\s*[（(\[【]\s*(?:精校版?|校对版?|全本|全集|完结|完本|精修版?|无错版?|未删节|未删减|手打|更新|排版|精编)[^）)\]】]*[）)\]】]"#, with: "", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func saveOfflineDirectory(_ book: NativeBook, chapters: [NativeChapter]) {
        let folder = offlineBookURL(book.id)
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try JSONEncoder().encode(book).write(to: folder.appendingPathComponent("book.json"), options: .atomic)
            try JSONEncoder().encode(chapters).write(to: folder.appendingPathComponent("directory.json"), options: .atomic)
        } catch { /* A cache failure must not prevent online reading. */ }
    }

    private static func saveOfflineContent(_ text: String, book: NativeBook, chapter: NativeChapter) {
        let root = offlineBookURL(book.id)
        do {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("chapters", isDirectory: true), withIntermediateDirectories: true)
            try text.write(to: root.appendingPathComponent("chapters", isDirectory: true).appendingPathComponent(chapter.id + ".txt"), atomically: true, encoding: .utf8)
            saveOfflineDirectory(book, chapters: loadOfflineDirectory(bookID: book.id) ?? [chapter])
        } catch { /* A cache failure must not prevent online reading. */ }
    }

    private static func loadOfflineDirectory(bookID: String) -> [NativeChapter]? {
        let url = offlineBookURL(bookID).appendingPathComponent("directory.json")
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode([NativeChapter].self, from: data)
    }

    private static func loadOfflineContent(bookID: String, chapterID: String) -> String? {
        try? String(contentsOf: offlineBookURL(bookID).appendingPathComponent("chapters", isDirectory: true).appendingPathComponent(chapterID + ".txt"), encoding: .utf8)
    }

    private static func loadOfflineBooks() -> [NativeBook] {
        let support = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
        let root = support.appendingPathComponent("XiaomanOffline", isDirectory: true)
        guard let urls = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) else { return [] }
        return urls.compactMap { try? JSONDecoder().decode(NativeBook.self, from: Data(contentsOf: $0.appendingPathComponent("book.json"))) }
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

    func bookComments(for book: NativeBook, offset: Int = 0) async throws -> NativeBookCommentPage {
        try await initializeIfNeeded()
        let id = book.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? book.id
        return try await Task.detached(priority: .userInitiated) {
            let payload = try Self.performJSONRequest(path: "/api/v1/books/\(id)/comments", parameters: [
                URLQueryItem(name: "count", value: "10"),
                URLQueryItem(name: "offset", value: String(max(0, offset)))
            ])
            var data = payload as? [String: Any] ?? [:]
            for _ in 0..<4 {
                guard let nested = data["data"] as? [String: Any] else { break }
                data = nested
            }
            let entries = data["comment"] as? [[String: Any]] ?? []
            let comments = entries.compactMap { raw -> NativeBookComment? in
                let text = Self.string(raw, keys: ["text"], fallback: [:]) ?? ""
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                let user = raw["user_info"] as? [String: Any] ?? [:]
                return NativeBookComment(
                    id: Self.string(raw, keys: ["comment_id"], fallback: [:]) ?? UUID().uuidString,
                    text: text,
                    score: Self.intValue(raw["score"]),
                    diggCount: Self.intValue(raw["digg_count"]),
                    replyCount: Self.intValue(raw["reply_count"]),
                    createdAt: Self.dateValue(raw["create_timestamp"]),
                    userName: Self.string(user, keys: ["user_name"], fallback: [:]) ?? "读者"
                )
            }
            return NativeBookCommentPage(
                comments: comments,
                totalCount: Self.intValue(data["comment_cnt"]),
                scoreCount: Self.intValue(data["score_cnt"]),
                scoreContext: Self.string(data, keys: ["context"], fallback: [:]) ?? "",
                hasMore: data["has_more"] as? Bool ?? false,
                nextOffset: Self.intValue(data["next_offset"])
            )
        }.value
    }

    func videoURL(for episode: NativeChapter) async throws -> URL {
        try await initializeIfNeeded()
        guard let base = resourceBaseURL?.absoluteString else { throw NativeClientError.message("媒体服务尚未启动") }
        return try await Task.detached(priority: .userInitiated) {
            try Self.fetchVideoURL(episode.id, resourceBase: base)
        }.value
    }

    func audioVoices(for book: NativeBook) async throws -> [NativeAudioVoice] {
        try await initializeIfNeeded()
        let id = book.id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? book.id
        return try await Task.detached(priority: .userInitiated) {
            let payload = try Self.performJSONRequest(path: "/api/v1/books/\(id)/tones", parameters: [])
            var data = payload as? [String: Any] ?? [:]
            for _ in 0..<8 {
                guard let nested = data["data"] as? [String: Any] else { break }
                data = nested
            }
            let voices = (data["tts_tones"] as? [[String: Any]] ?? []).compactMap { entry -> NativeAudioVoice? in
                guard let id = Self.string(entry, keys: ["id"], fallback: [:]), !id.isEmpty,
                      let title = Self.string(entry, keys: ["title"], fallback: [:]), !title.isEmpty else { return nil }
                return NativeAudioVoice(id: id, title: title)
            }
            var seen = Set<String>()
            return voices.filter { seen.insert($0.id).inserted }
        }.value
    }

    func audioSource(for chapter: NativeChapter, book: NativeBook, toneID: String = "0") async throws -> NativeAudioSource {
        try await initializeIfNeeded()
        guard let base = resourceBaseURL?.absoluteString else { throw NativeClientError.message("媒体服务尚未启动") }
        return try await Task.detached(priority: .userInitiated) {
            try Self.fetchAudioSource(chapter.id, bookId: book.id, toneID: toneID, resourceBase: base)
        }.value
    }

    func comicPages(for chapter: NativeChapter, book: NativeBook) async throws -> [NativeComicPage] {
        try await initializeIfNeeded()
        guard let base = resourceBaseURL?.absoluteString else { throw NativeClientError.message("媒体服务尚未启动") }
        return try await Task.detached(priority: .userInitiated) {
            try Self.fetchComicPages(chapter.id, bookId: book.id, resourceBase: base)
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

    nonisolated private static func fetchAudioSource(_ chapterId: String, bookId: String, toneID: String, resourceBase: String) throws -> NativeAudioSource {
        let book = bookId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? bookId
        let chapter = chapterId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? chapterId
        let payload = try performJSONRequest(path: "/api/v1/audio/books/\(book)/chapters/\(chapter)", parameters: [URLQueryItem(name: "tone_id", value: toneID)])
        var candidates: [(String, String?)] = []
        func contentKey(_ encryption: [String: Any]?) -> String? {
            guard encryption?["encrypt"] as? Bool == true else { return nil }
            return ((encryption?["key_hex"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()) ?? ""
        }
        func inspect(_ value: Any, depth: Int) throws {
            guard depth < 12 else { return }
            if let map = value as? [String: Any] {
                let status = (map["code"] as? NSNumber)?.intValue
                if let status, status != 0, status != 200 {
                    let message = map["message"] as? String ?? "音频资源暂不可用"
                    throw NativeClientError.message(message)
                }
                if map["success"] as? Bool == false { throw NativeClientError.message(map["message"] as? String ?? "音频资源暂不可用") }
                let streamID = map["item_id"].map { String(describing: $0) }
                if streamID == nil || streamID == chapterId {
                    let outerKey = contentKey(map["encrypt_info"] as? [String: Any])
                    var foundModelStreams = false
                    if let encodedModel = map["video_model"] as? String,
                       let data = encodedModel.data(using: .utf8),
                       let model = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if model["media_type"] as? String == "audio", let streams = model["video_list"] as? [[String: Any]] {
                            foundModelStreams = !streams.isEmpty
                            for stream in streams {
                                let streamKey = contentKey(stream["encrypt_info"] as? [String: Any])
                                for key in ["main_url", "backup_url"] {
                                    if let raw = stream[key] as? String, !raw.isEmpty { candidates.append((raw, streamKey)) }
                                }
                            }
                        }
                    }
                    if !foundModelStreams {
                        for key in ["main_url", "backup_url"] {
                            if let raw = map[key] as? String, !raw.isEmpty { candidates.append((raw, outerKey)) }
                        }
                    }
                }
                for child in map.values { try inspect(child, depth: depth + 1) }
            } else if let list = value as? [Any] {
                for child in list { try inspect(child, depth: depth + 1) }
            }
        }
        try inspect(payload, depth: 0)
        for (raw, keyHex) in candidates {
            guard let url = URL(string: raw, relativeTo: URL(string: resourceBase))?.absoluteURL,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { continue }
            if let keyHex, keyHex.range(of: "^[0-9a-f]{32}$", options: .regularExpression) == nil {
                throw NativeClientError.message("服务端返回的 CENC 音频密钥格式无效")
            }
            return NativeAudioSource(url: url, keyHex: keyHex)
        }
        throw NativeClientError.message("服务端没有返回可播放音频地址")
    }

    nonisolated private static func fetchComicPages(_ chapterId: String, bookId: String, resourceBase: String) throws -> [NativeComicPage] {
        let id = chapterId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? chapterId
        let payload = try performJSONRequest(path: "/api/v1/manga/\(id)", parameters: [URLQueryItem(name: "book_id", value: bookId)])
        var objects: [[String: Any]] = []
        var current = payload as? [String: Any] ?? [:]
        for _ in 0..<8 {
            let code = (current["code"] as? NSNumber)?.intValue
            if let code, code != 0, code != 200 {
                throw NativeClientError.message(current["message"] as? String ?? current["error"] as? String ?? "漫画章节加载失败")
            }
            if current["success"] as? Bool == false {
                throw NativeClientError.message(current["message"] as? String ?? "漫画章节加载失败")
            }
            objects.append(current)
            guard let next = current["data"] as? [String: Any] else { break }
            current = next
        }

        func resolved(_ raw: String) -> URL? {
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty, let url = URL(string: value, relativeTo: URL(string: resourceBase))?.absoluteURL,
                  ["http", "https"].contains(url.scheme?.lowercased() ?? ""), url.host != nil else { return nil }
            return url
        }

        for object in objects {
            guard let images = object["images"] as? [Any] else { continue }
            let pages = images.compactMap { value -> NativeComicPage? in
                let raw = value as? String ?? (value as? [String: Any]).flatMap { $0["url"] as? String }
                guard let raw, let url = resolved(raw) else { return nil }
                return NativeComicPage(url: url)
            }
            if !pages.isEmpty { return pages }
        }

        let pattern = #"(?is)<img\b[^>]*?\bsrc\s*=\s*["']([^"']+)["'][^>]*>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { throw NativeClientError.message("漫画图片解析失败") }
        for object in objects {
            for key in ["content", "images"] {
                guard let html = object[key] as? String else { continue }
                let range = NSRange(html.startIndex..., in: html)
                let pages = regex.matches(in: html, range: range).compactMap { match -> NativeComicPage? in
                    guard let capture = Range(match.range(at: 1), in: html), let url = resolved(String(html[capture])) else { return nil }
                    return NativeComicPage(url: url)
                }
                if !pages.isEmpty { return pages }
            }
        }
        throw NativeClientError.message("本章节没有返回漫画图片")
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

    nonisolated private static func intValue(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        if let value = value as? String { return Int(value) ?? 0 }
        return 0
    }

    nonisolated private static func dateValue(_ value: Any?) -> Date? {
        let raw = Double(intValue(value))
        guard raw > 0 else { return nil }
        return Date(timeIntervalSince1970: raw > 100_000_000_000 ? raw / 1000 : raw)
    }
}

private struct NativeHTTPResponse { let status: Int; let body: Data }
enum NativeClientError: LocalizedError {
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
