import SwiftUI

/// SwiftUI interface shared by the iPhone, iPad, and Mac apps.
public struct XiaomanReadingView: View {
    @StateObject private var store = NativeReadingStore()
    @State private var selection: AppTab = .shelf
    @State private var query = ""
    @State private var selectedBook: NativeBook?

    public init() {}

    public var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                ShelfView(books: store.shelf, onSelect: { selectedBook = $0 })
                    .navigationTitle("小满阅读")
            }
            .tabItem { Label("书架", systemImage: "books.vertical") }
            .tag(AppTab.shelf)

            NavigationStack {
                SearchView(query: $query, store: store, onSelect: { selectedBook = $0 })
                    .navigationTitle("书城")
            }
            .tabItem { Label("书城", systemImage: "magnifyingglass") }
            .tag(AppTab.discover)

            NavigationStack {
                SettingsView().navigationTitle("我的")
            }
            .tabItem { Label("我的", systemImage: "person.crop.circle") }
            .tag(AppTab.me)
        }
        .tint(Color(red: 0.72, green: 0.36, blue: 0.24))
        .sheet(item: $selectedBook) { book in
            NavigationStack { ReaderView(book: book, store: store, addToShelf: { store.addToShelf(book) }) }
        }
    }
}

private enum AppTab: Hashable { case shelf, discover, me }

private var groupedBackground: Color {
    #if os(iOS)
    Color(uiColor: .systemGroupedBackground)
    #else
    Color(nsColor: .windowBackgroundColor)
    #endif
}

private struct ShelfView: View {
    let books: [NativeBook]
    let onSelect: (NativeBook) -> Void

    var body: some View {
        Group {
            if books.isEmpty {
                ContentUnavailableView("书架还是空的", systemImage: "books.vertical", description: Text("去书城搜索作品，加入书架后从这里继续阅读。"))
            } else {
                List(books) { book in
                    Button { onSelect(book) } label: { BookRow(book: book) }.buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .background(groupedBackground)
    }
}

private struct SearchView: View {
    @Binding var query: String
    @ObservedObject var store: NativeReadingStore
    let onSelect: (NativeBook) -> Void

    var body: some View {
        Group {
            if store.isLoading {
                ProgressView("正在搜索")
            } else if let message = store.message {
                ContentUnavailableView(message, systemImage: "magnifyingglass")
            } else if store.results.isEmpty {
                ContentUnavailableView("搜索小说", systemImage: "magnifyingglass", description: Text("输入书名、作者或作品编号"))
            } else {
                List(store.results) { book in
                    Button { onSelect(book) } label: { BookRow(book: book) }.buttonStyle(.plain)
                }
                .listStyle(.plain)
            }
        }
        .searchable(text: $query, prompt: "书名、作者或作品编号")
        .task(id: query) {
            try? await Task.sleep(for: .milliseconds(350))
            await store.search(query)
        }
    }
}

private struct BookRow: View {
    let book: NativeBook
    var body: some View {
        HStack(spacing: 14) {
            if let url = book.coverURL {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                    RoundedRectangle(cornerRadius: 8).fill(book.color.gradient).overlay(Image(systemName: "book.closed.fill").foregroundStyle(.white.opacity(0.8)))
                }
                .frame(width: 62, height: 82).clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8).fill(book.color.gradient).frame(width: 62, height: 82)
                    .overlay(Image(systemName: "book.closed.fill").foregroundStyle(.white.opacity(0.8)))
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(book.title).font(.headline).foregroundStyle(.primary)
                Text(book.author.isEmpty ? book.category : book.author).font(.subheadline).foregroundStyle(.secondary)
                Text(book.progress).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

private struct ReaderView: View {
    let book: NativeBook
    @ObservedObject var store: NativeReadingStore
    let addToShelf: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var chapters: [NativeChapter] = []
    @State private var selectedIndex = 0
    @State private var content = ""
    @State private var error: String?
    @State private var isLoading = true
    @State private var fontSize = 20.0

    var body: some View {
        VStack(spacing: 0) {
            if !chapters.isEmpty {
                HStack {
                    Button { Task { await openChapter(selectedIndex - 1) } } label: { Image(systemName: "chevron.left") }
                        .disabled(selectedIndex == 0)
                    Spacer()
                    Menu {
                        ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                            Button(chapter.title) { Task { await openChapter(index) } }
                        }
                    } label: { Text(chapters[selectedIndex].title).font(.subheadline).lineLimit(1) }
                    Spacer()
                    Button { Task { await openChapter(selectedIndex + 1) } } label: { Image(systemName: "chevron.right") }
                        .disabled(selectedIndex >= chapters.count - 1)
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
                Divider()
            }
            if isLoading {
                Spacer(); ProgressView("正在加载章节"); Spacer()
            } else if let error {
                ContentUnavailableView("章节暂时无法打开", systemImage: "wifi.exclamationmark", description: Text(error))
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(book.title).font(.title2.weight(.semibold))
                        if !chapters.isEmpty { Text(chapters[selectedIndex].title).font(.subheadline).foregroundStyle(.secondary) }
                        Text(formattedContent(content))
                            .font(.system(size: fontSize, design: .serif))
                            .lineSpacing(10)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: 720, alignment: .leading)
                    .padding(.horizontal, 28).padding(.vertical, 26)
                    .frame(maxWidth: .infinity)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) { Button("完成") { dismiss() } }
            ToolbarItem(placement: .automatic) { Button("加入书架", systemImage: "books.vertical") { addToShelf() } }
            ToolbarItem(placement: .automatic) {
                Menu { Slider(value: $fontSize, in: 16...32, step: 1) } label: { Image(systemName: "textformat.size") }
            }
        }
        .task { await loadDirectory() }
    }

    private func loadDirectory() async {
        do {
            chapters = try await store.directory(for: book)
            guard !chapters.isEmpty else { throw ReaderError.emptyDirectory }
            let savedId = store.savedChapterId(for: book)
            let resumeIndex = chapters.firstIndex(where: { $0.id == savedId }) ?? 0
            await openChapter(resumeIndex)
        } catch { self.error = error.localizedDescription; isLoading = false }
    }

    private func openChapter(_ index: Int) async {
        guard chapters.indices.contains(index) else { return }
        isLoading = true
        error = nil
        do {
            content = try await store.content(for: chapters[index], book: book)
            selectedIndex = index
            store.recordProgress(for: book, chapter: chapters[index])
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }

    private func formattedContent(_ source: String) -> String {
        source
            .replacingOccurrences(of: "<br>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br/>", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<br />", with: "\n", options: .caseInsensitive)
            .replacingOccurrences(of: "</p>", with: "\n\n", options: .caseInsensitive)
            .replacingOccurrences(of: "<p[^>]*>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

private enum ReaderError: LocalizedError {
    case emptyDirectory
    var errorDescription: String? { "作品目录没有返回可读章节" }
}

private struct SettingsView: View {
    var body: some View {
        List {
            Section("阅读") {
                Label("阅读记录", systemImage: "clock")
                Label("离线书籍", systemImage: "arrow.down.circle")
            }
            Section("应用") {
                Label("数据备份与恢复", systemImage: "externaldrive")
                Label("关于小满阅读", systemImage: "info.circle")
            }
        }
    }
}
