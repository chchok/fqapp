import SwiftUI

/// SwiftUI interface shared by the iPhone, iPad, and Mac apps.
public struct XiaomanReadingView: View {
    @StateObject private var store = NativeReadingStore()
    @State private var selection: AppTab = .home
    @State private var query = ""
    @State private var showingSearch = false
    @State private var showingCategories = false
    @State private var selectedBook: NativeBook?
    @State private var selectedMedia: NativeBook?

    public init() {}

    public var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                HomeView(query: $query, store: store, onSearch: { showingSearch = true }, onCategories: { showingCategories = true }) { item in
                    if item.kind == "book" { selectedBook = item }
                    else { selectedMedia = item }
                }
                    .navigationTitle("小满阅读")
            }
            .tabItem { Label("首页", systemImage: "house") }
            .tag(AppTab.home)

            NavigationStack {
                DramaView(store: store) { item in selectedMedia = item }
                    .navigationTitle("短剧")
            }
            .tabItem { Label("短剧", systemImage: "play.rectangle") }
            .tag(AppTab.drama)

            NavigationStack {
                ShelfView(books: store.shelf, onSelect: { select($0) })
                    .navigationTitle("书架")
            }
            .tabItem { Label("书架", systemImage: "books.vertical") }
            .tag(AppTab.shelf)

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
        .sheet(item: $selectedMedia) { media in NavigationStack { MediaPreviewView(media: media) } }
        .sheet(isPresented: $showingSearch) {
            NavigationStack {
                SearchView(query: $query, store: store, onSelect: { item in
                    showingSearch = false
                    select(item)
                })
                    .navigationTitle("搜索")
                    .toolbar { ToolbarItem(placement: .automatic) { Button("完成") { showingSearch = false } } }
            }
        }
        .sheet(isPresented: $showingCategories) {
            NavigationStack {
                CategoryBrowserView(store: store) { term in
                    query = term
                    showingCategories = false
                    showingSearch = true
                }
                .navigationTitle("分类")
                .toolbar { ToolbarItem(placement: .automatic) { Button("完成") { showingCategories = false } } }
            }
        }
    }

    private func select(_ item: NativeBook) {
        if item.kind == "book" { selectedBook = item }
        else { selectedMedia = item }
    }
}

private enum AppTab: Hashable { case home, drama, shelf, me }

private var groupedBackground: Color {
    #if os(iOS)
    Color(uiColor: .systemGroupedBackground)
    #else
    Color(nsColor: .windowBackgroundColor)
    #endif
}

private var appBackground: Color {
    #if os(iOS)
    Color(uiColor: .systemBackground)
    #else
    Color(nsColor: .windowBackgroundColor)
    #endif
}

private struct HomeView: View {
    @Binding var query: String
    @ObservedObject var store: NativeReadingStore
    let onSearch: () -> Void
    let onCategories: () -> Void
    let onSelect: (NativeBook) -> Void
    @State private var selectedTab = 0

    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 14)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField("搜索书名、作者或作品编号", text: $query)
                        .submitLabel(.search)
                        .onSubmit(onSearch)
                    Button(action: onSearch) { Image(systemName: "arrow.right.circle.fill").font(.title3) }
                        .accessibilityLabel("开始搜索")
                    Button(action: onCategories) { Image(systemName: "square.grid.2x2.fill").font(.title3) }
                        .accessibilityLabel("浏览分类")
                }
                .padding(12)
                .background(groupedBackground, in: RoundedRectangle(cornerRadius: 14))

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(store.homeTabs.enumerated()), id: \.element.id) { index, tab in
                            Button {
                                selectedTab = index
                                Task { await store.loadHome(tabIndex: index) }
                            } label: {
                                Text(tab.title).font(.subheadline.weight(selectedTab == index ? .semibold : .regular))
                                    .padding(.horizontal, 15).padding(.vertical, 8)
                                    .foregroundStyle(selectedTab == index ? .white : .primary)
                                    .background(selectedTab == index ? Color(red: 0.72, green: 0.36, blue: 0.24) : groupedBackground, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(selectedTab < store.homeTabs.count ? store.homeTabs[selectedTab].title : "推荐")
                            .font(.title2.weight(.bold))
                        Text("为你发现好作品").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await store.loadHome(tabIndex: selectedTab, force: true) } } label: {
                        Image(systemName: "arrow.clockwise").padding(9).background(groupedBackground, in: Circle())
                    }
                    .accessibilityLabel("刷新推荐")
                }

                if store.homeLoading && store.homeItems.isEmpty {
                    ProgressView("正在加载推荐")
                        .frame(maxWidth: .infinity, minHeight: 180)
                } else if let message = store.homeMessage, store.homeItems.isEmpty {
                    ContentUnavailableView(message, systemImage: "books.vertical", description: Text("稍后重试，或直接搜索作品。"))
                        .frame(minHeight: 220)
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(store.homeItems) { item in
                            Button { onSelect(item) } label: { HomeMediaCard(item: item) }
                                .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 14)
        }
        .background(appBackground)
        .refreshable { await store.loadHome(tabIndex: selectedTab, force: true) }
        .task { await store.loadHome(tabIndex: selectedTab) }
        .onChange(of: store.homeTabs.count) { _, count in
            if selectedTab >= count { selectedTab = 0 }
        }
    }
}

private struct CategoryBrowserView: View {
    @ObservedObject var store: NativeReadingStore
    let onChoose: (String) -> Void
    @State private var selectedChannel = "1"
    private let columns = [GridItem(.adaptive(minimum: 104), spacing: 10)]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(store.categoryChannels) { channel in
                            Button {
                                selectedChannel = channel.id
                                Task { await store.loadCategories(channel: channel.id) }
                            } label: {
                                Text(channel.title).padding(.horizontal, 14).padding(.vertical, 9)
                                    .foregroundStyle(selectedChannel == channel.id ? .white : .primary)
                                    .background(selectedChannel == channel.id ? Color(red: 0.72, green: 0.36, blue: 0.24) : groupedBackground, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                if store.categoriesLoading && store.categoryTiles.isEmpty {
                    ProgressView("正在加载分类").frame(maxWidth: .infinity, minHeight: 170)
                } else if let message = store.categoriesMessage, store.categoryTiles.isEmpty {
                    ContentUnavailableView(message, systemImage: "square.grid.2x2", description: Text("切换频道或稍后重试。"))
                } else {
                    Text("热门分类").font(.headline)
                    LazyVGrid(columns: columns, spacing: 10) {
                        ForEach(store.categoryTiles) { tile in
                            Button { onChoose(tile.title) } label: {
                                HStack(spacing: 6) {
                                    if tile.isHot { Image(systemName: "flame.fill").foregroundStyle(.orange) }
                                    Text(tile.title).lineLimit(1)
                                }
                                .font(.subheadline)
                                .frame(maxWidth: .infinity, minHeight: 42)
                                .background(groupedBackground, in: RoundedRectangle(cornerRadius: 9))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(appBackground)
        .task { await store.loadCategories(channel: selectedChannel) }
    }
}

private struct DramaView: View {
    @ObservedObject var store: NativeReadingStore
    let onSelect: (NativeBook) -> Void
    @State private var tabIndex: Int?
    private let columns = [GridItem(.adaptive(minimum: 145), spacing: 14)]

    private var dramaIndex: Int {
        store.homeTabs.firstIndex(where: { $0.type == 8 || $0.title.contains("短剧") || $0.title.contains("看剧") }) ?? 2
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("短剧与漫剧").font(.title2.weight(.bold))
                        Text("番茄内容源实时推荐").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button { Task { await store.loadHome(tabIndex: tabIndex ?? dramaIndex, force: true) } } label: {
                        Image(systemName: "arrow.clockwise").padding(9).background(groupedBackground, in: Circle())
                    }
                    .accessibilityLabel("刷新短剧")
                }
                if store.homeLoading && store.homeItems.isEmpty {
                    ProgressView("正在加载短剧").frame(maxWidth: .infinity, minHeight: 180)
                } else if let message = store.homeMessage, store.homeItems.isEmpty {
                    ContentUnavailableView(message, systemImage: "play.rectangle", description: Text("请稍后重试，或前往首页搜索作品。"))
                } else {
                    LazyVGrid(columns: columns, alignment: .leading, spacing: 14) {
                        ForEach(store.homeItems) { item in
                            Button { onSelect(item) } label: { HomeMediaCard(item: item) }.buttonStyle(.plain)
                        }
                    }
                }
            }
            .padding(16)
        }
        .background(appBackground)
        .refreshable { await store.loadHome(tabIndex: tabIndex ?? dramaIndex, force: true) }
        .task {
            let index = dramaIndex
            tabIndex = index
            await store.loadHome(tabIndex: index)
        }
        .onChange(of: store.homeTabs) { _, _ in
            guard tabIndex == nil else { return }
            let index = dramaIndex
            tabIndex = index
            Task { await store.loadHome(tabIndex: index) }
        }
    }
}

private struct HomeMediaCard: View {
    let item: NativeBook
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack(alignment: .bottomLeading) {
                if let url = item.coverURL {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                        RoundedRectangle(cornerRadius: 12).fill(item.color.gradient)
                    }
                } else {
                    RoundedRectangle(cornerRadius: 12).fill(item.color.gradient)
                        .overlay(Image(systemName: "book.closed.fill").font(.largeTitle).foregroundStyle(.white.opacity(0.8)))
                }
                Text(item.category).font(.caption2.weight(.medium)).padding(.horizontal, 8).padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: Capsule()).padding(8)
            }
            .frame(height: 188).clipShape(RoundedRectangle(cornerRadius: 12))
            Text(item.title).font(.subheadline.weight(.semibold)).lineLimit(2).foregroundStyle(.primary)
            if !item.author.isEmpty { Text(item.author).font(.caption).lineLimit(1).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9).background(.background, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct MediaPreviewView: View {
    let media: NativeBook
    @StateObject private var store = NativeReadingStore()
    @State private var details: [String: String] = [:]
    @State private var loading = true
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HomeMediaCard(item: media).frame(maxWidth: 300).frame(maxWidth: .infinity)
                Text(media.title).font(.title2.bold())
                if loading { ProgressView("正在读取作品详情") }
                if let error { ContentUnavailableView("详情暂时无法加载", systemImage: "wifi.exclamationmark", description: Text(error)) }
                ForEach(details.keys.sorted(), id: \.self) { key in
                    if let value = details[key], !value.isEmpty {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(key).font(.caption).foregroundStyle(.secondary)
                            Text(value).font(.body).textSelection(.enabled)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12).background(groupedBackground, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                Text("作品详情来自 fqapp 内容服务；原生播放和互动功能仍在移植中。")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(20)
        }
        .task {
            do { details = try await store.mediaDetails(for: media); error = nil }
            catch { self.error = error.localizedDescription }
            loading = false
        }
        .toolbar { ToolbarItem(placement: .automatic) { Button("完成") { dismiss() } } }
    }
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
