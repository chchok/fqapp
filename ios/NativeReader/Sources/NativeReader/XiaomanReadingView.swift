import SwiftUI
import AVKit
#if os(iOS)
import UIKit
#else
import AppKit
#endif

/// SwiftUI interface shared by the iPhone, iPad, and Mac apps.
public struct XiaomanReadingView: View {
    @StateObject private var store = NativeReadingStore()
    @State private var selection: AppTab = .home
    @State private var query = ""
    @State private var showingSearch = false
    @State private var showingCategories = false
    @State private var selectedBook: NativeBook?
    @State private var selectedMedia: NativeBook?
    @State private var selectedReader: NativeBook?

    public init() {}

    public var body: some View {
        Group {
            switch selection {
            case .home:
                NavigationStack {
                    HomeView(query: $query, store: store, onSearch: { showingSearch = true }, onCategories: { showingCategories = true }, onResume: { selectedReader = $0 }) { item in
                        if item.kind == "book" { selectedBook = item }
                        else { selectedMedia = item }
                    }
                }
                .nativeNavigationChromeHidden()
            case .drama:
                NavigationStack { DramaView(store: store, onSearch: { showingSearch = true }) { item in selectedMedia = item } }
                    .nativeNavigationChromeHidden()
            case .shelf:
                NavigationStack { ShelfView(store: store, onSearch: { showingSearch = true }, onBrowse: { selection = .home }, onSelect: { select($0) }) }
                    .nativeNavigationChromeHidden()
            case .me:
                NavigationStack { SettingsView(store: store) }
                    .nativeNavigationChromeHidden()
            }
        }
        .background(Color(red: 0.957, green: 0.953, blue: 0.937).ignoresSafeArea())
        .tint(Color(red: 0.72, green: 0.36, blue: 0.24))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            NativeDock(selection: $selection)
                .padding(.horizontal, 22)
                .padding(.top, 3)
                .padding(.bottom, 12)
                .background {
                    LinearGradient(colors: [Color.clear, Color.primary.opacity(0.045)], startPoint: .top, endPoint: .bottom)
                        .ignoresSafeArea(edges: .bottom)
                }
        }
        .sheet(item: $selectedBook) { book in
            NavigationStack { BookDetailView(book: book, store: store) }
        }
        .sheet(item: $selectedReader) { book in
            NavigationStack { ReaderView(book: book, store: store, addToShelf: { store.addToShelf(book) }) }
        }
        .sheet(item: $selectedMedia) { media in
            NavigationStack { MediaPreviewView(media: media, store: store) }
                .nativeNavigationChromeHidden()
        }
        .sheet(isPresented: $showingSearch) {
            NavigationStack {
                SearchView(query: $query, store: store, onSelect: { item in
                    showingSearch = false
                    select(item)
                })
                    .nativeNavigationChromeHidden()
            }
            .presentationDetents([.large])
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

private extension View {
    @ViewBuilder func nativeNavigationChromeHidden() -> some View {
        #if os(iOS)
        self.toolbar(.hidden, for: .navigationBar)
        #else
        self
        #endif
    }
}

private struct NativeDock: View {
    @Binding var selection: AppTab
    private let items: [(AppTab, String, String)] = [
        (.home, "house", "首页"), (.drama, "play", "短剧"),
        (.shelf, "book", "书架"), (.me, "person.crop.circle", "我的")
    ]
    private let itemWidth: CGFloat = 184.0 / 3.0
    private let accent = Color(red: 0.94, green: 0.31, blue: 0.22)

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(items.enumerated()), id: \.offset) { entry in
                let item = entry.element
                let active = selection == item.0
                Button { selection = item.0 } label: {
                    VStack(spacing: 3) {
                        Image(systemName: item.1).font(.system(size: 20, weight: active ? .semibold : .regular)).frame(height: 22)
                        Text(item.2).font(.system(size: 11, weight: active ? .bold : .medium)).lineLimit(1)
                        Capsule().fill(Color.primary.opacity(active ? 0.72 : 0)).frame(width: 12, height: 1.5)
                    }
                    .foregroundStyle(active ? accent : Color.primary.opacity(0.68))
                    .frame(width: itemWidth, height: 48)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 50)
        .background(.ultraThinMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7))
        .shadow(color: Color.black.opacity(0.08), radius: 14, y: 5)
        .frame(maxWidth: 620)
        .frame(maxWidth: .infinity)
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
    let onResume: (NativeBook) -> Void
    let onSelect: (NativeBook) -> Void
    @State private var selectedTab = 0
    @State private var dismissedContinueIDs: Set<String> = []

    private func columnCount(for width: CGFloat) -> Int {
        if width < 324 { return 2 }
        if width < 640 { return 3 }
        if width < 900 { return 4 }
        let fit = Int(width / 190)
        return fit < 6 ? 5 : min(9, max(6, fit))
    }

    private var visibleItems: [NativeBook] {
        let kind = switch selectedTab {
        case 2: "video"
        case 3: "manju"
        case 4: "manga"
        case 5: "audio"
        default: "book"
        }
        return store.homeItems.filter { $0.kind == kind }
    }

    private var continueReading: NativeBook? {
        guard selectedTab == 0 else { return nil }
        return store.readingHistory.first { $0.kind == "book" || $0.kind == "audio" }
    }

    var body: some View {
        VStack(spacing: 0) {
            masthead
            categoryBar
            GeometryReader { geometry in
                // Android constrains phones to the screen width and lets iPad / desktop
                // use the available window width. Do not cap the native grid at 840pt.
                let width = geometry.size.width
                let gutter: CGFloat = 16
                let gridWidth = width - gutter * 2
                let count = columnCount(for: gridWidth)
                let gap: CGFloat = 12
                let cardWidth = (gridWidth - CGFloat(count - 1) * gap) / CGFloat(count)
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if store.homeLoading && visibleItems.isEmpty {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 180)
                        } else if let message = store.homeMessage, visibleItems.isEmpty {
                            ContentUnavailableView(message, systemImage: "books.vertical", description: Text("稍后重试，或直接搜索作品。"))
                                .frame(minHeight: 220)
                        } else {
                            if let item = continueReading,
                               !dismissedContinueIDs.contains(item.id),
                               !UserDefaults.standard.bool(forKey: "xiaoman.continue.dismissed.\(item.id)") {
                                NativeContinueRow(item: item) {
                                    onResume(item)
                                } onDismiss: {
                                    UserDefaults.standard.set(true, forKey: "xiaoman.continue.dismissed.\(item.id)")
                                    dismissedContinueIDs.insert(item.id)
                                }
                            }
                            sectionLabel
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap, alignment: .top), count: count), alignment: .leading, spacing: 20) {
                                ForEach(visibleItems) { item in
                                    Button { onSelect(item) } label: { HomeMediaCard(item: item, width: cardWidth) }
                                        .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, gutter)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 30)
                }
                .refreshable { await store.loadHome(tabIndex: selectedTab, force: true) }
            }
        }
        .background(Color(red: 0.957, green: 0.953, blue: 0.937))
        .task {
            selectedTab = store.selectedHomeTab
            await store.loadHome(tabIndex: selectedTab)
        }
    }

    private var masthead: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("什锦铺").font(.system(size: 20, weight: .bold)).tracking(-0.4)
                Text("SHIJINPU / STORY ARCHIVE")
                    .font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.05)
                    .foregroundStyle(Color(red: 0.43, green: 0.43, blue: 0.41))
            }
            Spacer(minLength: 8)
            headerAction("magnifyingglass", label: "搜索", action: onSearch)
            headerAction("square.grid.2x2", label: "分类", action: onCategories)
        }
        .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.11))
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 4)
    }

    private var categoryBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(Array(store.homeTabs.enumerated()), id: \.element.id) { index, tab in
                    Button {
                        selectedTab = index
                        store.selectedHomeTab = index
                        Task { await store.loadHome(tabIndex: index) }
                    } label: {
                        VStack(spacing: 0) {
                            Text(tab.title)
                                .font(.system(size: 15, weight: selectedTab == index ? .semibold : .regular))
                                .foregroundStyle(selectedTab == index ? Color(red: 0.11, green: 0.11, blue: 0.11) : Color(red: 0.43, green: 0.43, blue: 0.41))
                                .padding(.top, 12).padding(.bottom, 12)
                            Rectangle().fill(selectedTab == index ? Color(red: 0.11, green: 0.11, blue: 0.11) : .clear).frame(height: 2)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color(red: 0.88, green: 0.87, blue: 0.84)).frame(height: 1) }
        .fixedSize(horizontal: false, vertical: true)
    }

    private var sectionLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(selectedTab == 0 ? "01 / FOR YOU" : "01 / \((selectedTab < store.homeTabs.count ? store.homeTabs[selectedTab].title : "FOR YOU").uppercased())")
                    .font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.05)
                    .foregroundStyle(Color(red: 0.43, green: 0.43, blue: 0.41))
                    .lineLimit(1)
                Rectangle().fill(Color(red: 0.88, green: 0.87, blue: 0.84)).frame(height: 1)
                Rectangle().fill(Color(red: 0.11, green: 0.11, blue: 0.11)).frame(width: 4, height: 4)
            }
            Text(selectedTab == 0 ? "为你推荐" : (selectedTab < store.homeTabs.count ? store.homeTabs[selectedTab].title : "推荐"))
                .font(.system(size: 18, weight: .bold)).tracking(-0.4)
                .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.11))
        }
        .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func headerAction(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 19)).frame(width: 36, height: 36) }
            .buttonStyle(.plain).foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.11))
            .accessibilityLabel(label)
    }
}

private struct NativeContinueRow: View {
    let item: NativeBook
    let onOpen: () -> Void
    let onDismiss: () -> Void

    private var percent: Int { Int((item.progressRatio * 100).rounded()) }
    private var detail: String {
        if let chapter = item.savedChapterTitle, !chapter.isEmpty {
            return "\(item.kind == "audio" ? "听到" : "读到") \(chapter)"
        }
        return item.kind == "audio" ? "上次收听" : "上次阅读"
    }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("CONTINUE / \(detail)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .tracking(0.65).foregroundStyle(Color(red: 0.43, green: 0.43, blue: 0.41))
                    HStack(spacing: 6) {
                        Text(item.title).font(.system(size: 14, weight: .bold)).lineLimit(1)
                        if !item.author.isEmpty {
                            Text(item.author).font(.system(size: 12.5)).lineLimit(1)
                                .foregroundStyle(Color(red: 0.43, green: 0.43, blue: 0.41))
                        }
                    }
                    .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.11))
                    .padding(.top, 5)
                    ProgressView(value: item.progressRatio)
                        .tint(Color(red: 0.11, green: 0.11, blue: 0.11))
                        .scaleEffect(x: 1, y: 0.35, anchor: .center)
                        .padding(.top, 8)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 14).padding(.vertical, 11).padding(.trailing, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if percent > 0 {
                Text("\(percent)%")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.11))
                    .padding(.trailing, 8)
            }
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(Color(red: 0.43, green: 0.43, blue: 0.41))
                    .frame(width: 34, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain).accessibilityLabel("隐藏继续阅读")
        }
        .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal, 16).padding(.top, 14)
    }
}

private struct CategoryBrowserView: View {
    @ObservedObject var store: NativeReadingStore
    let onChoose: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedChannel = "1"
    @State private var selectedDimension = ""
    @State private var expandedSections: Set<String> = []

    private var sections: [NativeCategorySection] {
        guard !store.categoryTiles.isEmpty else { return [] }
        var result = [NativeCategorySection(id: "hot", title: "热门标签", tiles: store.categoryTiles)]
        for dimension in store.categoryDimensions where dimension.id != "0" {
            let tiles = store.categoryTiles.filter { $0.dimension == dimension.id }
            if !tiles.isEmpty {
                result.append(NativeCategorySection(id: dimension.id, title: dimension.title, tiles: tiles))
            }
        }
        return result
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Button { dismiss() } label: { Image(systemName: "chevron.left").font(.system(size: 20)).frame(width: 48, height: 48) }
                    .buttonStyle(.plain).foregroundStyle(.primary).accessibilityLabel("返回")
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 24) {
                        ForEach(store.categoryChannels) { channel in
                            Button {
                                selectedChannel = channel.id
                                selectedDimension = ""
                                expandedSections = []
                                Task {
                                    await store.loadCategories(channel: channel.id)
                                    selectedDimension = sections.first?.id ?? ""
                                }
                            } label: {
                                Text(channel.title).font(.system(size: 16, weight: selectedChannel == channel.id ? .bold : .regular))
                                    .foregroundStyle(selectedChannel == channel.id ? Color(red: 0.11, green: 0.11, blue: 0.11) : Color(red: 0.55, green: 0.55, blue: 0.55))
                            }.buttonStyle(.plain)
                        }
                    }
                }
                Button { onChoose("") } label: { Image(systemName: "magnifyingglass").font(.system(size: 20)).frame(width: 48, height: 48) }
                    .buttonStyle(.plain).foregroundStyle(.primary).accessibilityLabel("搜索分类")
            }
            .frame(height: 48)

            if store.categoriesLoading && store.categoryTiles.isEmpty {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = store.categoriesMessage, store.categoryTiles.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "cloud.slash").font(.system(size: 28)).foregroundStyle(.secondary)
                    Text(message).font(.system(size: 15)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button { Task { await store.loadCategories(channel: selectedChannel) } } label: {
                        Label("重试", systemImage: "arrow.clockwise")
                            .font(.system(size: 14, weight: .medium))
                            .padding(.horizontal, 18).padding(.vertical, 9)
                            .background(Color(red: 0.94, green: 0.31, blue: 0.22), in: Capsule())
                            .foregroundStyle(.white)
                    }.buttonStyle(.plain)
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GeometryReader { geometry in
                    let count = max(3, min(10, Int((geometry.size.width - 88 - 32) / 170)))
                    let gridColumns = Array(repeating: GridItem(.flexible(), spacing: 7, alignment: .top), count: count)
                    ScrollViewReader { proxy in
                        HStack(spacing: 0) {
                            ScrollView(showsIndicators: false) {
                                VStack(spacing: 0) {
                                    ForEach(sections) { section in
                                        Button {
                                            selectedDimension = section.id
                                            withAnimation(.easeInOut(duration: 0.3)) { proxy.scrollTo(section.id, anchor: .top) }
                                        } label: {
                                            Text(section.title)
                                                .font(.system(size: 14, weight: .regular))
                                                .foregroundStyle(selectedDimension == section.id ? Color(red: 0.94, green: 0.31, blue: 0.22) : Color(red: 0.11, green: 0.11, blue: 0.11))
                                                .lineLimit(1).minimumScaleFactor(0.75)
                                                .frame(width: 88, height: 50)
                                        }.buttonStyle(.plain)
                                    }
                                }
                            }
                            .frame(width: 88)
                            .background(Color(red: 0.925, green: 0.914, blue: 0.886))

                            ScrollView {
                                LazyVStack(alignment: .leading, spacing: 0) {
                                    ForEach(sections) { section in
                                        let collapsed = section.tiles.count > 30 && !expandedSections.contains(section.id)
                                        let visible = collapsed ? Array(section.tiles.prefix(30)) : section.tiles
                                        VStack(alignment: .leading, spacing: 0) {
                                            HStack {
                                                Text(section.title).font(.system(size: 12)).foregroundStyle(Color(red: 0.59, green: 0.59, blue: 0.59))
                                                Spacer()
                                                if section.tiles.count > 30 {
                                                    Button {
                                                        if expandedSections.contains(section.id) { expandedSections.remove(section.id) }
                                                        else { expandedSections.insert(section.id) }
                                                    } label: {
                                                        HStack(spacing: 2) {
                                                            Text(expandedSections.contains(section.id) ? "收起" : "展开").font(.system(size: 12))
                                                            Image(systemName: expandedSections.contains(section.id) ? "chevron.up" : "chevron.down").font(.system(size: 10))
                                                        }.foregroundStyle(Color(red: 0.59, green: 0.59, blue: 0.59))
                                                    }.buttonStyle(.plain)
                                                }
                                            }
                                            .frame(height: 24)
                                            LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 0) {
                                                ForEach(visible) { tile in
                                                    Button { onChoose(tile.title) } label: {
                                                        HStack(spacing: 2) {
                                                            if tile.isHot { Image(systemName: "flame.fill").font(.system(size: 16)).foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.11)) }
                                                            Text(tile.title).font(.system(size: 14)).lineLimit(1).minimumScaleFactor(0.75)
                                                        }
                                                        .frame(maxWidth: .infinity).frame(height: 30)
                                                        .background(Color(red: 0.925, green: 0.925, blue: 0.925), in: RoundedRectangle(cornerRadius: 6))
                                                        .padding(.top, 6).padding(.bottom, 4)
                                                    }.buttonStyle(.plain).foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.11))
                                                }
                                            }
                                        }
                                        .padding(.top, 16)
                                        .id(section.id)
                                        .background {
                                            GeometryReader { itemGeometry in
                                                Color.clear.preference(key: NativeCategoryOffsetsKey.self, value: [section.id: itemGeometry.frame(in: .named("nativeCategoryList")).minY])
                                            }
                                        }
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.bottom, 16)
                            }
                            .coordinateSpace(name: "nativeCategoryList")
                            .onPreferenceChange(NativeCategoryOffsetsKey.self) { offsets in
                                if let current = sections.last(where: { (offsets[$0.id] ?? .greatestFiniteMagnitude) <= 24 }) {
                                    if selectedDimension != current.id { selectedDimension = current.id }
                                }
                            }
                            .background(Color(red: 0.957, green: 0.953, blue: 0.937), in: UnevenRoundedRectangle(topLeadingRadius: 12))
                        }
                    }
                }
            }
        }
        .background(Color(red: 0.957, green: 0.953, blue: 0.937))
        .nativeNavigationChromeHidden()
        .task {
            await store.loadCategories(channel: selectedChannel)
            selectedDimension = sections.first?.id ?? ""
        }
    }
}

private struct NativeCategorySection: Identifiable {
    let id: String
    let title: String
    let tiles: [NativeCategoryTile]
}

private struct NativeCategoryOffsetsKey: PreferenceKey {
    static var defaultValue: [String: CGFloat] = [:]
    static func reduce(value: inout [String: CGFloat], nextValue: () -> [String: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private struct DramaView: View {
    @ObservedObject var store: NativeReadingStore
    let onSearch: () -> Void
    let onSelect: (NativeBook) -> Void
    @State private var selectedChannel = 0
    @State private var feedIndex = 0
    private let channels = ["推荐", "看剧", "漫剧", "最近", "收藏"]
    private var isFeed: Bool { selectedChannel == 0 }
    private var isLightPage: Bool { selectedChannel != 0 }
    private var items: [NativeBook] {
        switch selectedChannel {
        case 3: store.readingHistory.filter { $0.kind == "video" || $0.kind == "manju" }
        case 4: store.favorites.filter { $0.kind == "video" || $0.kind == "manju" }
        default: store.homeItems
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                if isFeed, items.indices.contains(feedIndex) {
                    NativeDramaInlinePlayer(media: items[feedIndex], store: store)
                        .id(items[feedIndex].id)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .ignoresSafeArea()
                } else {
                    (isFeed ? Color.black : Color(red: 0.957, green: 0.953, blue: 0.937)).ignoresSafeArea()
                }

                if isLightPage {
                    ScrollView {
                        if items.isEmpty {
                            if store.homeLoading { ProgressView().tint(.secondary).frame(maxWidth: .infinity, minHeight: 220) }
                            else { ContentUnavailableView(selectedChannel == 3 ? "暂无观看记录" : selectedChannel == 4 ? "暂无收藏内容" : "暂无内容", systemImage: "play.rectangle") }
                        } else {
                            let columns = 3
                            let gap: CGFloat = 8
                            let itemWidth = (geometry.size.width - 24 - gap * CGFloat(columns - 1)) / CGFloat(columns)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: gap, alignment: .top), count: columns), alignment: .leading, spacing: 16) {
                                ForEach(items) { item in
                                    Button { onSelect(item) } label: { HomeMediaCard(item: item, width: itemWidth, radius: 10) }
                                        .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 12)
                        }
                    }
                    .padding(.top, 12)
                    .padding(.bottom, 12)
                    .refreshable { await loadChannel(selectedChannel, force: true) }
                } else if items.isEmpty {
                    VStack(spacing: 12) {
                        if store.homeLoading { ProgressView().tint(.white) }
                        else { Text(store.homeMessage ?? "暂无内容").foregroundStyle(.white.opacity(0.8)) }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                if isFeed, items.indices.contains(feedIndex) {
                    VStack(alignment: .leading, spacing: 8) {
                        Spacer()
                        HStack(alignment: .bottom, spacing: 14) {
                            Button { onSelect(items[feedIndex]) } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(items[feedIndex].title).font(.headline.weight(.semibold)).foregroundStyle(.white).lineLimit(2)
                                    Text(items[feedIndex].author.isEmpty ? "短剧 · 点击播放" : "短剧 · \(items[feedIndex].author)")
                                        .font(.caption).foregroundStyle(.white.opacity(0.8))
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            VStack(spacing: 18) {
                                Button { store.toggleFavorite(items[feedIndex]) } label: {
                                    Image(systemName: store.favorites.contains(where: { $0.id == items[feedIndex].id }) ? "heart.fill" : "heart")
                                        .font(.system(size: 24)).foregroundStyle(.white)
                                }
                                Button { onSelect(items[feedIndex]) } label: { Image(systemName: "play.circle.fill").font(.system(size: 30)).foregroundStyle(.white) }
                            }
                        }
                        .padding(.horizontal, 18).padding(.bottom, 22)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .simultaneousGesture(DragGesture(minimumDistance: 36).onEnded { value in
                        if value.translation.height < -50, feedIndex + 1 < items.count { feedIndex += 1 }
                        else if value.translation.height > 50, feedIndex > 0 { feedIndex -= 1 }
                    })
                }

                VStack(spacing: 0) {
                    if !isLightPage {
                        searchRow
                    } else {
                        LinearGradient(colors: [Color(red: 0.957, green: 0.953, blue: 0.937), Color(red: 0.957, green: 0.953, blue: 0.937).opacity(0.9), .clear], startPoint: .top, endPoint: .bottom)
                            .frame(height: 112).overlay(alignment: .top) { searchRow }
                    }
                    channelStrip
                    Spacer(minLength: 0)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(isFeed ? Color.black : Color(red: 0.957, green: 0.953, blue: 0.937))
        .task { await loadChannel(selectedChannel) }
        .onChange(of: selectedChannel) { _, channel in feedIndex = 0; Task { await loadChannel(channel) } }
    }

    private var searchRow: some View {
        Button(action: onSearch) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").font(.system(size: 14))
                Text(selectedChannel == 2 ? "请输入漫剧名或主演名" : "请输入短剧名或主演名").font(.system(size: 13)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isLightPage ? Color.primary.opacity(0.62) : Color.white.opacity(0.8))
            .padding(.horizontal, 14).frame(height: 36)
            .background(isLightPage ? Color.primary.opacity(0.06) : Color.black.opacity(0.2), in: Capsule())
            .overlay(Capsule().strokeBorder(isLightPage ? Color.primary.opacity(0.08) : Color.white.opacity(0.18), lineWidth: 0.5))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16).padding(.top, 6).padding(.bottom, 9)
    }

    private var channelStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .center, spacing: 18) {
                ForEach(Array(channels.enumerated()), id: \.offset) { index, title in
                    Button { selectedChannel = index } label: {
                        VStack(spacing: 2) {
                            Text(title).font(.system(size: index == selectedChannel ? 24 : 16, weight: index == selectedChannel ? .bold : .regular))
                                .foregroundStyle(isLightPage ? Color.primary.opacity(index == selectedChannel ? 1 : 0.6) : Color.white.opacity(index == selectedChannel ? 1 : 0.62))
                            Rectangle().fill(index == selectedChannel ? (isLightPage ? Color.primary : Color.white) : .clear).frame(height: 3)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 38)
    }

    private func loadChannel(_ channel: Int, force: Bool = false) async {
        switch channel {
        case 0: await store.loadHome(tabIndex: 6, force: force)
        case 1: await store.loadHome(tabIndex: 2, force: force)
        case 2: await store.loadHome(tabIndex: 3, force: force)
        default: break
        }
    }
}

/// The Android recommendation feed starts the first episode inline and toggles
/// playback on a tap. AVPlayerLayer keeps the native feed free of system player
/// chrome so the surrounding SwiftUI controls retain the Android page layout.
private struct NativeDramaInlinePlayer: View {
    let media: NativeBook
    @ObservedObject var store: NativeReadingStore
    @State private var player: AVPlayer?
    @State private var loading = true
    @State private var error: String?
    @State private var playing = false

    var body: some View {
        ZStack {
            if let player {
                NativePlayerSurface(player: player)
                    .ignoresSafeArea()
            } else if let cover = media.coverURL {
                AsyncImage(url: cover) { image in image.resizable().scaledToFill() }
                    placeholder: { NativeCoverPlaceholder(item: media) }
                    .ignoresSafeArea()
            } else {
                NativeCoverPlaceholder(item: media).ignoresSafeArea()
            }
            LinearGradient(colors: [.black.opacity(0.06), .clear, .clear, .black.opacity(0.38)], startPoint: .top, endPoint: .bottom)
                .allowsHitTesting(false)
            if loading {
                ProgressView().tint(.white).scaleEffect(1.1)
            } else if let error {
                VStack(spacing: 8) {
                    Image(systemName: "wifi.exclamationmark").font(.system(size: 24))
                    Text(error).font(.system(size: 12)).multilineTextAlignment(.center).lineLimit(3)
                    Button("重试") { Task { await startPlayback() } }
                        .font(.system(size: 13, weight: .semibold))
                        .padding(.horizontal, 14).padding(.vertical, 7)
                        .background(.white.opacity(0.2), in: Capsule())
                }
                .foregroundStyle(.white)
                .padding(16)
                .background(.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
            } else if !playing {
                Image(systemName: "play.fill")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(20)
                    .background(.black.opacity(0.3), in: Circle())
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture { togglePlayback() }
        .task(id: media.id) { await startPlayback() }
        .onDisappear { player?.pause(); playing = false }
    }

    private func togglePlayback() {
        guard let player else { return }
        if playing { player.pause() } else { player.play() }
        playing.toggle()
    }

    @MainActor private func startPlayback() async {
        player?.pause()
        player = nil
        loading = true
        error = nil
        do {
            let episodes = try await store.directory(for: media)
            guard let first = episodes.first else {
                error = "剧集目录为空"
                loading = false
                return
            }
            let url = try await store.videoURL(for: first)
            guard !Task.isCancelled else { return }
            let nextPlayer = AVPlayer(url: url)
            player = nextPlayer
            nextPlayer.play()
            playing = true
            store.recordMediaHistory(media)
        } catch {
            if !Task.isCancelled { self.error = error.localizedDescription }
        }
        loading = false
    }
}

#if os(iOS)
private struct NativePlayerSurface: UIViewRepresentable {
    let player: AVPlayer
    func makeUIView(context: Context) -> NativePlayerUIView {
        let view = NativePlayerUIView()
        view.playerLayer.videoGravity = .resizeAspectFill
        view.playerLayer.player = player
        return view
    }
    func updateUIView(_ view: NativePlayerUIView, context: Context) { view.playerLayer.player = player }
}

private final class NativePlayerUIView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
#else
private struct NativePlayerSurface: NSViewRepresentable {
    let player: AVPlayer
    func makeNSView(context: Context) -> NativePlayerNSView {
        let view = NativePlayerNSView()
        view.playerLayer.player = player
        return view
    }
    func updateNSView(_ view: NativePlayerNSView, context: Context) { view.playerLayer.player = player }
}

private final class NativePlayerNSView: NSView {
    override var wantsUpdateLayer: Bool { true }
    override func makeBackingLayer() -> CALayer {
        let layer = AVPlayerLayer()
        layer.videoGravity = .resizeAspectFill
        return layer
    }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}
#endif

private struct HomeMediaCard: View {
    let item: NativeBook
    var width: CGFloat = 150
    var radius: CGFloat = 3
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let url = item.coverURL {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                        NativeCoverPlaceholder(item: item)
                    }
                } else {
                    NativeCoverPlaceholder(item: item)
                }
                if let tag = item.tagText, !tag.isEmpty,
                   let colors = item.tagColors, !colors.isEmpty {
                    Text(tag).font(.system(size: 9)).lineLimit(1)
                        .foregroundStyle(.white).padding(.horizontal, 6).padding(.vertical, 3)
                        .background(LinearGradient(colors: colors.compactMap(nativeHexColor).ifEmpty([Color.black.opacity(0.7)]), startPoint: .leading, endPoint: .trailing), in: RoundedRectangle(cornerRadius: 5))
                        .padding(8)
                }
                if let episode = item.episodeLabel, !episode.isEmpty, item.kind == "video" {
                    Text(episode).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                        .foregroundStyle(.white).shadow(color: .black.opacity(0.8), radius: 2)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(8)
                }
            }
            .frame(width: width, height: width * 1.4).clipped().clipShape(RoundedRectangle(cornerRadius: radius))
            Text(item.title).font(.system(size: 14.5, weight: .semibold)).lineSpacing(0).lineLimit(2).truncationMode(.tail).foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.11))
                .frame(height: 39.2, alignment: .topLeading).padding(.top, 8)
            Text(fileCode(item)).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.05)
                .lineLimit(1).foregroundStyle(Color(red: 0.43, green: 0.43, blue: 0.41)).padding(.top, 5)
            let meta = [item.author, item.recommendationReason].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            if !meta.isEmpty { Text(meta).font(.system(size: 11)).lineLimit(1).foregroundStyle(Color(red: 0.43, green: 0.43, blue: 0.41)).padding(.top, 2) }
        }
        .frame(width: width, alignment: .leading)
    }

    private func fileCode(_ item: NativeBook) -> String {
        let prefix = switch item.kind { case "video": "VID"; case "manju": "MNJ"; case "manga": "MNG"; case "audio": "AUD"; default: "NOV" }
        let digits = item.id.filter(\.isNumber)
        let tail = String(digits.suffix(5))
        return "\(prefix)-\(String(repeating: "0", count: max(0, 5 - tail.count)))\(tail)"
    }

}

private func nativeHexColor(_ hex: String) -> Color? {
    guard hex.count == 7, hex.first == "#", let value = UInt64(hex.dropFirst(), radix: 16) else { return nil }
    return Color(.sRGB, red: Double((value >> 16) & 0xff) / 255, green: Double((value >> 8) & 0xff) / 255, blue: Double(value & 0xff) / 255, opacity: 1)
}

private extension Array where Element == Color {
    func ifEmpty(_ fallback: [Color]) -> [Color] { isEmpty ? fallback : self }
}

private struct NativeCoverPlaceholder: View {
    let item: NativeBook

    private var colors: [Color] {
        switch item.kind {
        case "video": [Color(red: 0.45, green: 0.28, blue: 0.25), Color(red: 0.14, green: 0.14, blue: 0.16)]
        case "manju": [Color(red: 0.55, green: 0.33, blue: 0.50), Color(red: 0.21, green: 0.16, blue: 0.24)]
        case "manga": [Color(red: 0.44, green: 0.41, blue: 0.53), Color(red: 0.20, green: 0.20, blue: 0.29)]
        case "audio": [Color(red: 0.26, green: 0.42, blue: 0.47), Color(red: 0.13, green: 0.23, blue: 0.26)]
        default: [Color(red: 0.42, green: 0.47, blue: 0.39), Color(red: 0.16, green: 0.24, blue: 0.21)]
        }
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .topLeading) {
                LinearGradient(colors: colors, startPoint: UnitPoint(x: 0.33, y: 0), endPoint: UnitPoint(x: 0.67, y: 1))
                VStack(spacing: 0) {
                    ForEach(Array(item.title.prefix(8).enumerated()), id: \.offset) { _, character in
                        Text(String(character))
                            .font(.system(size: min(22, max(12, geometry.size.width * 0.13)), weight: .bold, design: .serif))
                            .foregroundStyle(.white.opacity(0.92))
                    }
                }
                .lineSpacing(1)
                .padding(.leading, geometry.size.width * 0.11)
                .padding(.top, geometry.size.height * 0.09)
                .frame(height: geometry.size.height * 0.74, alignment: .top)
                LinearGradient(colors: [.clear, .black.opacity(0.18)], startPoint: .center, endPoint: .bottom)
            }
        }
    }
}

private struct MediaPreviewView: View {
    let media: NativeBook
    @ObservedObject var store: NativeReadingStore
    @State private var details: [String: String] = [:]
    @State private var loading = true
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Group {
            if media.kind == "video" || media.kind == "manju" {
                NativeDramaDetailView(media: media, store: store)
            } else {
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
                .background(appBackground)
            }
        }
        .task {
            guard media.kind != "video" && media.kind != "manju" else { return }
            do { details = try await store.mediaDetails(for: media); error = nil }
            catch { self.error = error.localizedDescription }
            loading = false
        }
        .toolbar {
            if media.kind != "video" && media.kind != "manju" {
                ToolbarItem(placement: .automatic) { Button("完成") { dismiss() } }
            }
        }
    }
}

private struct NativeDramaDetailView: View {
    let media: NativeBook
    @ObservedObject var store: NativeReadingStore
    @Environment(\.dismiss) private var dismiss
    @State private var details: [String: String] = [:]
    @State private var episodes: [NativeChapter] = []
    @State private var loading = true
    @State private var error: String?
    @State private var playing = false
    @State private var startIndex = 0

    private let ink = Color(red: 0.11, green: 0.11, blue: 0.11)
    private let muted = Color(red: 0.43, green: 0.43, blue: 0.41)
    private let line = Color(red: 0.88, green: 0.87, blue: 0.84)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    poster.frame(width: 112, height: 150).clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(media.title).font(.system(size: 19, weight: .bold)).lineSpacing(2).foregroundStyle(ink)
                        Text([media.author, media.category].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 12)).foregroundStyle(muted)
                        if let count = details["集数"], !count.isEmpty { Text("共\(count)集").font(.system(size: 12)).foregroundStyle(muted) }
                        if let followers = details["追剧人数"], !followers.isEmpty { Text("\(followers)人在追").font(.system(size: 12)).foregroundStyle(muted) }
                        HStack(spacing: 10) {
                            Button { store.toggleFavorite(media) } label: {
                                Label(store.favorites.contains(where: { $0.id == media.id }) ? "已收藏" : "收藏", systemImage: store.favorites.contains(where: { $0.id == media.id }) ? "heart.fill" : "heart")
                                    .font(.system(size: 12, weight: .medium)).foregroundStyle(ink)
                            }.buttonStyle(.plain)
                            Button { store.addToShelf(media) } label: {
                                Label("追剧", systemImage: "plus").font(.system(size: 12, weight: .medium)).foregroundStyle(ink)
                            }.buttonStyle(.plain)
                        }.padding(.top, 5)
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal, 16).padding(.top, 10)

                dramaSection("简介") {
                    Text(clean(details["简介"] ?? details["作品简介"] ?? "正在加载作品简介…"))
                        .font(.system(size: 14)).lineSpacing(5).foregroundStyle(muted)
                }
                dramaSection("选集", trailing: episodes.isEmpty ? "" : "共\(episodes.count)集") {
                    if loading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 52)
                    } else if let error {
                        Text(error).font(.system(size: 13)).foregroundStyle(muted).padding(.vertical, 12)
                    } else {
                        ForEach(Array(episodes.prefix(6).enumerated()), id: \.element.id) { index, episode in
                            Button { startIndex = index; playing = true; store.recordMediaHistory(media) } label: {
                                HStack(spacing: 12) {
                                    Text(String(format: "%02d", index + 1)).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(muted).frame(width: 24, alignment: .leading)
                                    Text(episode.title).font(.system(size: 14)).lineLimit(1).foregroundStyle(ink)
                                    Spacer()
                                    Image(systemName: "play.fill").font(.system(size: 11)).foregroundStyle(muted)
                                }.frame(height: 44)
                            }.buttonStyle(.plain)
                            if index < min(episodes.count, 6) - 1 { Rectangle().fill(line).frame(height: 0.7) }
                        }
                    }
                }
                Text("作品编号  \(media.id)").font(.system(size: 11, design: .monospaced)).foregroundStyle(muted)
                    .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 24)
            }.frame(maxWidth: 840, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.957, green: 0.953, blue: 0.937))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 8) {
                Button { store.addToShelf(media) } label: {
                    VStack(spacing: 3) { Image(systemName: "plus.rectangle.on.folder").font(.system(size: 19)); Text("追剧").font(.system(size: 10)) }
                        .foregroundStyle(muted).frame(width: 66, height: 48)
                }.buttonStyle(.plain)
                Button { startIndex = 0; playing = true; store.recordMediaHistory(media) } label: {
                    Text(loading ? "正在加载剧集" : "开始观看")
                        .font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 42)
                        .foregroundStyle(.white).background(loading || episodes.isEmpty ? muted : Color(red: 0.94, green: 0.31, blue: 0.22), in: Capsule())
                }.buttonStyle(.plain).disabled(loading || episodes.isEmpty)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
            .background(Color(red: 0.99, green: 0.98, blue: 0.96).overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) })
        }
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .navigationDestination(isPresented: $playing) { NativeDramaPlayerView(media: media, store: store, initialIndex: startIndex) }
        .task {
            async let detailLoad = store.mediaDetails(for: media)
            async let directoryLoad = store.directory(for: media)
            do { details = try await detailLoad }
            catch { self.error = error.localizedDescription }
            do { episodes = try await directoryLoad }
            catch { if self.error == nil { self.error = error.localizedDescription } }
            loading = false
        }
    }

    private var poster: some View {
        Group {
            if let url = media.coverURL {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { RoundedRectangle(cornerRadius: 6).fill(media.color.gradient) }
            } else {
                RoundedRectangle(cornerRadius: 6).fill(media.color.gradient).overlay(Image(systemName: "play.rectangle.fill").foregroundStyle(.white.opacity(0.8)))
            }
        }
    }

    private func dramaSection<Content: View>(_ title: String, trailing: String = "", @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(ink)
                Spacer()
                if !trailing.isEmpty { Text(trailing).font(.system(size: 11)).foregroundStyle(muted) }
            }
            content()
        }.padding(.horizontal, 16).padding(.top, 20)
    }

    private func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
    }
}

private struct NativeDramaPlayerView: View {
    let media: NativeBook
    @ObservedObject var store: NativeReadingStore
    var initialIndex = 0
    @State private var episodes: [NativeChapter] = []
    @State private var selectedIndex = 0
    @State private var player: AVPlayer?
    @State private var isLoading = true
    @State private var error: String?
    @State private var duration: Double = 0
    @State private var position: Double = 0
    @State private var seekValue: Double?
    @State private var observer: Any?
    @State private var showCatalog = false
    @State private var rate = 1.0
    @State private var showDetail = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color.black.ignoresSafeArea()
                if let player {
                    NativePlayerSurface(player: player)
                        .ignoresSafeArea()
                        .contentShape(Rectangle())
                        .onTapGesture { togglePlayback() }
                } else if let url = media.coverURL {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { Color.black }
                        .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                }
                LinearGradient(colors: [.black.opacity(0.66), .clear, .clear, .black.opacity(0.16), .black.opacity(0.78)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
                if isLoading { ProgressView("正在准备视频").tint(.white).foregroundStyle(.white) }
                if let error {
                    VStack(spacing: 10) {
                        Image(systemName: "wifi.exclamationmark").font(.title)
                        Text(error).font(.callout).multilineTextAlignment(.center)
                        Button("重试") { Task { await playEpisode(selectedIndex) } }.buttonStyle(.bordered)
                    }
                    .foregroundStyle(.white).padding(22).background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 12))
                }
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Button { player?.pause(); player = nil; dismiss() } label: {
                            Image(systemName: "chevron.left").font(.system(size: 19, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 48)
                        }
                        Text("第\(selectedIndex + 1)集").font(.system(size: 16, weight: .medium)).foregroundStyle(.white).lineLimit(1)
                        Spacer()
                        Menu {
                            ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                                Button(value == 1 ? "正常速度" : "\(rateLabel(value))×") {
                                    rate = value
                                    if player?.timeControlStatus == .playing { player?.rate = Float(value) }
                                }
                            }
                            Button("选集", systemImage: "list.number") { showCatalog = true }
                            Button(store.favorites.contains(where: { $0.id == media.id }) ? "取消收藏" : "收藏", systemImage: "heart") {
                                store.toggleFavorite(media)
                            }
                        } label: {
                            Image(systemName: "ellipsis").font(.system(size: 20, weight: .semibold)).foregroundStyle(.white).frame(width: 44, height: 48)
                        }
                    }
                    .padding(.horizontal, 8).padding(.top, geometry.safeAreaInsets.top)
                    Spacer()

                    Spacer()
                    VStack(alignment: .leading, spacing: 0) {
                        Button { showDetail = true } label: {
                            HStack(spacing: 4) {
                                Text(media.title).font(.system(size: 16, weight: .bold)).foregroundStyle(.white).lineLimit(1)
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white.opacity(0.85))
                            }
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, 16)
                        NativeDramaSeekBar(position: seekValue ?? position, duration: duration, onScrub: { seekValue = $0 }, onCommit: { value in
                            seekValue = nil
                            guard let player, duration > 0 else { return }
                            player.seek(to: CMTime(seconds: value * duration, preferredTimescale: 600))
                        })
                        .padding(.bottom, 8)
                        Button { showCatalog = true } label: {
                            HStack(spacing: 4) {
                                Text("选集").font(.system(size: 14, weight: .bold))
                                Text("· 全\(episodes.count)集").font(.system(size: 14, weight: .bold)).lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.up").font(.system(size: 16, weight: .semibold))
                            }
                            .foregroundStyle(.white).padding(.horizontal, 16).frame(height: 48)
                            .background(Color(red: 0.09, green: 0.09, blue: 0.09).opacity(0.9), in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain).disabled(episodes.isEmpty)
                    }
                    .padding(.horizontal, 16).padding(.bottom, geometry.safeAreaInsets.bottom + 8)
                }

                if player?.timeControlStatus != .playing && !isLoading && error == nil {
                    Image(systemName: "play.fill").font(.system(size: 38, weight: .semibold)).foregroundStyle(.white.opacity(0.35)).allowsHitTesting(false)
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .background(.black)
        .task { await loadEpisodes() }
        .sheet(isPresented: $showCatalog) {
            NativeDramaCatalogSheet(media: media, episodes: episodes, selectedIndex: selectedIndex) { index in
                showCatalog = false
                Task { await playEpisode(index) }
            }
        }
        .navigationDestination(isPresented: $showDetail) { NativeDramaDetailView(media: media, store: store) }
        .onDisappear {
            player?.pause()
            if let player, let observer { player.removeTimeObserver(observer) }
            observer = nil
        }
    }

    private func loadEpisodes() async {
        do {
            episodes = try await store.directory(for: media)
            guard !episodes.isEmpty else {
                error = "剧集目录为空"
                isLoading = false
                return
            }
            await playEpisode(initialIndex)
        } catch {
            self.error = error.localizedDescription
            isLoading = false
        }
    }

    private func playEpisode(_ index: Int) async {
        guard episodes.indices.contains(index) else { return }
        if let current = player, let observer { current.removeTimeObserver(observer) }
        observer = nil
        player?.pause()
        isLoading = true
        error = nil
        do {
            let url = try await store.videoURL(for: episodes[index])
            selectedIndex = index
            let next = AVPlayer(url: url)
            player = next
            attachTimeObserver(to: next)
            next.playImmediately(atRate: Float(rate))
            store.recordMediaHistory(media)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func attachTimeObserver(to player: AVPlayer) {
        observer = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 0.25, preferredTimescale: 600), queue: .main) { time in
            guard time.seconds.isFinite else { return }
            position = time.seconds
            if let seconds = player.currentItem?.duration.seconds, seconds.isFinite, seconds > 0 { duration = seconds }
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if player.timeControlStatus == .playing { player.pause() }
        else { player.playImmediately(atRate: Float(rate)) }
    }

    private func rateLabel(_ value: Double) -> String { String(format: "%g", value) }
}

private struct NativeDramaSeekBar: View {
    let position: Double
    let duration: Double
    let onScrub: (Double) -> Void
    let onCommit: (Double) -> Void
    @State private var dragging = false
    var body: some View {
        GeometryReader { geometry in
            let progress = duration > 0 ? min(1, max(0, position / duration)) : 0
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.3)).frame(height: 2)
                Capsule().fill(Color(red: 0.98, green: 0.40, blue: 0.15)).frame(width: geometry.size.width * progress, height: 3)
                Circle().fill(.white).frame(width: dragging ? 9 : 6, height: dragging ? 9 : 6).offset(x: max(0, geometry.size.width * progress - 3))
            }
            .frame(height: 30)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { value in
                guard duration > 0 else { return }
                dragging = true
                onScrub(min(1, max(0, value.location.x / max(1, geometry.size.width))) * duration)
            }.onEnded { value in
                dragging = false
                let fraction = min(1, max(0, value.location.x / max(1, geometry.size.width)))
                onCommit(fraction)
            })
        }
        .frame(height: 30)
    }
}

private struct NativeDramaCatalogSheet: View {
    let media: NativeBook
    let episodes: [NativeChapter]
    let selectedIndex: Int
    let onSelect: (Int) -> Void
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List(Array(episodes.enumerated()), id: \.element.id) { index, episode in
                Button { onSelect(index) } label: {
                    HStack(spacing: 12) {
                        Text(String(format: "%02d", index + 1)).font(.system(size: 12, weight: .medium, design: .monospaced)).foregroundStyle(.secondary).frame(width: 28, alignment: .leading)
                        Text(episode.title).font(.system(size: 15, weight: index == selectedIndex ? .semibold : .regular)).foregroundStyle(index == selectedIndex ? Color(red: 0.94, green: 0.31, blue: 0.22) : .primary)
                        Spacer()
                        if index == selectedIndex { Image(systemName: "waveform").foregroundStyle(Color(red: 0.94, green: 0.31, blue: 0.22)) }
                    }
                }.buttonStyle(.plain)
            }
            .listStyle(.plain)
            .navigationTitle("选集 · \(media.title)")
#if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
#endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct ShelfView: View {
    @ObservedObject var store: NativeReadingStore
    let onSearch: () -> Void
    let onBrowse: () -> Void
    let onSelect: (NativeBook) -> Void
    @State private var tab = 0
    @State private var layout = 0
    @State private var filter = 0

    private let ink = Color(red: 0.11, green: 0.11, blue: 0.11)
    private let muted = Color(red: 0.43, green: 0.43, blue: 0.41)
    private let line = Color(red: 0.88, green: 0.87, blue: 0.84)

    private var entries: [NativeBook] {
        switch tab {
        case 0: return store.shelf.filter { $0.kind == "book" }
        case 1: return store.readingHistory
        default:
            let media = store.favorites.filter { $0.kind == "video" || $0.kind == "manju" }
            switch filter {
            case 1: return media.filter { $0.kind == "video" }
            case 2: return media.filter { $0.kind == "manju" }
            default: return media
            }
        }
    }

    private var columns: [GridItem] {
        let count = layout == 2 ? 1 : (layout == 1 ? 2 : 3)
        return Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: count)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .bottom, spacing: 18) {
                HStack(spacing: 20) {
                    ForEach(Array(["书架", "浏览历史", "收藏"].enumerated()), id: \.offset) { index, title in
                        Button { withAnimation(.easeOut(duration: 0.18)) { tab = index } } label: {
                            VStack(spacing: 7) {
                                Text(title).font(.system(size: 18, weight: tab == index ? .semibold : .regular))
                                    .foregroundStyle(tab == index ? ink : muted)
                                Rectangle().fill(tab == index ? ink : .clear).frame(height: 2)
                            }
                        }.buttonStyle(.plain)
                    }
                }
                Spacer(minLength: 0)
                Button(action: onSearch) { Image(systemName: "magnifyingglass").font(.system(size: 19)).frame(width: 34, height: 34) }
                    .buttonStyle(.plain).foregroundStyle(ink).accessibilityLabel("搜索")
                Menu {
                    Button("切换为宫格", systemImage: "square.grid.3x3") { layout = 0 }
                    Button("切换为双列", systemImage: "square.grid.2x2") { layout = 1 }
                    Button("切换为列表", systemImage: "list.bullet") { layout = 2 }
                    if tab == 1 { Button("清空历史", systemImage: "trash", role: .destructive) { store.clearReadingHistory() } }
                } label: {
                    Image(systemName: "ellipsis").font(.system(size: 20)).frame(width: 30, height: 34)
                }.foregroundStyle(ink)
            }
            .padding(.leading, 16).padding(.trailing, 12).padding(.top, 12).padding(.bottom, 5)
            Rectangle().fill(line).frame(height: 0.7)

            HStack(spacing: 10) {
                if tab == 0 {
                    Label("今日已读 \(store.todayReadMinutes)分钟", systemImage: "clock").font(.system(size: 12.5, weight: .medium))
                        .foregroundStyle(muted).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.black.opacity(0.045), in: Capsule())
                } else if tab == 2 {
                    ForEach(Array(["全部", "短剧", "漫剧"].enumerated()), id: \.offset) { index, title in
                        Button { filter = index } label: {
                            Text(title).font(.system(size: 12.5, weight: filter == index ? .semibold : .regular))
                                .foregroundStyle(filter == index ? ink : muted)
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(filter == index ? Color.black.opacity(0.07) : .clear, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                } else { Spacer(minLength: 0) }
                Spacer(minLength: 0)
                HStack(spacing: 0) {
                    ForEach(0..<3, id: \.self) { index in
                        Button { layout = index } label: {
                            Image(systemName: ["square.grid.3x3", "square.grid.2x2", "list.bullet"][index])
                                .font(.system(size: 13, weight: layout == index ? .semibold : .regular))
                                .foregroundStyle(layout == index ? ink : muted)
                                .frame(width: 34, height: 29)
                                .background(layout == index ? Color.white : .clear, in: RoundedRectangle(cornerRadius: 8))
                        }.buttonStyle(.plain)
                    }
                }.padding(3).background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 11))
            }
            .padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 8)

            if entries.isEmpty {
                Spacer(minLength: 0)
                VStack(spacing: 15) {
                    Image(systemName: tab == 2 ? "film.stack" : (tab == 1 ? "magnifyingglass" : "book.closed"))
                        .font(.system(size: 42, weight: .light)).foregroundStyle(muted.opacity(0.7))
                        .frame(width: 88, height: 88).background(Color.black.opacity(0.045), in: RoundedRectangle(cornerRadius: 15))
                    Text(tab == 2 ? (filter == 1 ? "暂无短剧" : filter == 2 ? "暂无漫剧" : "暂无收藏内容") : tab == 1 ? "未找到相关内容" : "书架暂无书籍")
                        .font(.system(size: 16, weight: .semibold)).foregroundStyle(ink)
                    if tab == 0 { Text("去书城发现海量故事，随时随地畅读").font(.system(size: 13)).foregroundStyle(muted) }
                    if tab == 0 { Button("去书城找书", action: onBrowse).font(.system(size: 14, weight: .semibold)).padding(.horizontal, 22).padding(.vertical, 11).background(Color(red: 0.94, green: 0.31, blue: 0.22), in: Capsule()).foregroundStyle(.white) }
                }.frame(maxWidth: .infinity)
                Spacer(minLength: 0)
            } else {
                GeometryReader { geometry in
                    let count = layout == 2 ? 1 : (layout == 1 ? 2 : 3)
                    let width = geometry.size.width
                    let cardWidth = (width - 32 - CGFloat(count - 1) * 12) / CGFloat(count)
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: 20) {
                            ForEach(entries) { book in
                                Button { onSelect(book) } label: {
                                    ShelfBookCard(book: book, width: cardWidth, list: layout == 2)
                                }.buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 100)
                    }
                }
            }
        }
        .background(Color(red: 0.957, green: 0.953, blue: 0.937))
    }
}

private struct ShelfBookCard: View {
    let book: NativeBook
    let width: CGFloat
    var list = false
    var body: some View {
        if list {
            HStack(spacing: 12) {
                poster(width: 56, height: 78)
                VStack(alignment: .leading, spacing: 6) {
                    Text(book.title).font(.system(size: 15, weight: .medium)).lineLimit(2).foregroundStyle(.primary)
                    Text(book.author.isEmpty ? book.category : book.author).font(.system(size: 11.5)).lineLimit(1).foregroundStyle(.secondary)
                    Text(book.progress).font(.system(size: 11.5)).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 5)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                poster(width: width, height: width * 1.4)
                Text(book.title).font(.system(size: 13, weight: .medium)).lineLimit(2).frame(height: 36, alignment: .topLeading)
                    .foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.11)).padding(.top, 5)
                Text(book.author.isEmpty ? book.category : book.author).font(.system(size: 11.5)).lineLimit(1).foregroundStyle(.secondary).padding(.top, 3)
            }.frame(width: width, alignment: .leading)
        }
    }
    @ViewBuilder private func poster(width: CGFloat, height: CGFloat) -> some View {
        if let url = book.coverURL {
            AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: {
                RoundedRectangle(cornerRadius: 10).fill(book.color.gradient)
            }
                .frame(width: width, height: height).clipShape(RoundedRectangle(cornerRadius: 10))
        } else {
            RoundedRectangle(cornerRadius: 10).fill(book.color.gradient).frame(width: width, height: height)
                .overlay(Image(systemName: "book.closed.fill").foregroundStyle(.white.opacity(0.78)))
        }
    }
}

private struct SearchView: View {
    @Binding var query: String
    @ObservedObject var store: NativeReadingStore
    let onSelect: (NativeBook) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focused: Bool
    @State private var selectedCategory = 0
    private let categories = ["综合", "小说", "短剧", "漫剧", "漫画", "听书"]
    private var visibleResults: [NativeBook] {
        switch selectedCategory {
        case 1: return store.results.filter { $0.kind == "book" }
        case 2: return store.results.filter { $0.kind == "video" }
        case 3: return store.results.filter { $0.kind == "manju" }
        case 4: return store.results.filter { $0.kind == "manga" }
        case 5: return store.results.filter { $0.kind == "audio" }
        default: return store.results
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Image(systemName: "magnifyingglass").font(.system(size: 18)).frame(width: 44)
                TextField("搜索名称或作品 ID", text: $query)
                    .font(.system(size: 15))
                    .focused($focused).submitLabel(.search).onSubmit { runSearch(query) }
                if !query.isEmpty {
                    Button { query = ""; Task { await store.search("") }; focused = true } label: {
                        Image(systemName: "xmark.circle.fill").font(.system(size: 16)).foregroundStyle(.secondary).frame(width: 34, height: 44)
                    }.buttonStyle(.plain)
                }
                Button { runSearch(query) } label: { Text("搜索").font(.system(size: 14, weight: .semibold)).frame(width: 48, height: 44) }
                    .buttonStyle(.plain).foregroundStyle(Color(red: 0.72, green: 0.36, blue: 0.24))
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 15, weight: .medium)).frame(width: 42, height: 44) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("关闭搜索")
            }
            .background(Color.white.opacity(0.55), in: Capsule())
            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.7))
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 7)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(categories.enumerated()), id: \.offset) { index, title in
                        Button { selectedCategory = index } label: {
                            Text(title).font(.system(size: 14, weight: selectedCategory == index ? .semibold : .regular))
                                .foregroundStyle(selectedCategory == index ? .primary : .secondary)
                                .padding(.horizontal, 12).frame(height: 36)
                                .background(selectedCategory == index ? Color.primary.opacity(0.08) : .clear, in: Capsule())
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 16)
            }.padding(.bottom, 6)

            Group {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    discovery
                } else if store.isLoading && store.results.isEmpty {
                    ProgressView("正在搜索").frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let message = store.message, visibleResults.isEmpty {
                    ContentUnavailableView(message, systemImage: "magnifyingglass", description: Text("试试更短的名称或作者名"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if visibleResults.isEmpty {
                    ContentUnavailableView("没有找到相关故事", systemImage: "books.vertical", description: Text("试试其他分类，或换个关键词搜索"))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(visibleResults) { book in
                                Button { onSelect(book) } label: { NativeSearchResultRow(book: book) }.buttonStyle(.plain)
                            }
                        }.padding(.horizontal, 22).padding(.bottom, 30)
                    }
                }
            }
        }
        .background(Color(red: 0.957, green: 0.953, blue: 0.937))
        .task { await store.loadHotSearchTerms(); if !query.isEmpty { await store.search(query) } }
        .onChange(of: query) { _, value in if value.isEmpty { Task { await store.search("") } } }
    }

    private var discovery: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !store.searchHistory.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(spacing: 9) {
                            Text("最近搜索").font(.system(size: 17, weight: .bold))
                            Text("03 / RECENT QUERIES").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(0.7).foregroundStyle(.secondary)
                            Spacer()
                            Button("清空") { store.clearSearchHistory() }.font(.system(size: 12)).foregroundStyle(.secondary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(store.searchHistory, id: \.self) { term in
                                    Button { runSearch(term) } label: {
                                        Text(term).font(.system(size: 13)).lineLimit(1).padding(.horizontal, 12).padding(.vertical, 8)
                                            .background(Color.white.opacity(0.65), in: Capsule())
                                            .overlay(Capsule().strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.6))
                                    }.buttonStyle(.plain).foregroundStyle(.primary)
                                }
                            }
                        }
                    }
                }
                if !store.hotSearchTerms.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 9) {
                            Text("热搜榜").font(.system(size: 17, weight: .bold))
                            Text("02 / TRENDING INDEX").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(0.7).foregroundStyle(.secondary)
                        }
                        ForEach(Array(store.hotSearchTerms.enumerated()), id: \.offset) { index, term in
                            Button { runSearch(term) } label: {
                                HStack(spacing: 12) {
                                    Text("\(index + 1)").font(.system(size: index < 3 ? 14 : 12, weight: .semibold, design: .rounded))
                                        .foregroundStyle(index < 3 ? Color.primary : Color.secondary).frame(width: 20, alignment: .leading)
                                    Text(term).font(.system(size: 13.5, weight: index < 3 ? .medium : .regular)).lineLimit(1)
                                    Spacer()
                                    Image(systemName: "arrow.up.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                                }.frame(height: 42)
                            }.buttonStyle(.plain).foregroundStyle(.primary)
                            if index < store.hotSearchTerms.count - 1 { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 0.6) }
                        }
                    }
                }
                if store.searchHistory.isEmpty && store.hotSearchTerms.isEmpty {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 180)
                }
            }
            .padding(.horizontal, 22).padding(.top, 22).padding(.bottom, 28)
        }
    }

    private func runSearch(_ value: String) {
        let term = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }
        query = term
        focused = false
        Task { await store.search(term) }
    }
}

private struct NativeSearchResultRow: View {
    let book: NativeBook
    var body: some View {
        HStack(spacing: 15) {
            Group {
                if let url = book.coverURL {
                    AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { RoundedRectangle(cornerRadius: 3).fill(book.color.gradient) }
                } else {
                    RoundedRectangle(cornerRadius: 3).fill(book.color.gradient).overlay(Image(systemName: "book.closed.fill").foregroundStyle(.white.opacity(0.75)))
                }
            }.frame(width: 56, height: 76).clipShape(RoundedRectangle(cornerRadius: 3))
            VStack(alignment: .leading, spacing: 4) {
                Text("FQ-\(book.id)").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(0.7).foregroundStyle(.secondary)
                Text(book.title).font(.system(size: 15, weight: .semibold)).lineLimit(2).multilineTextAlignment(.leading).foregroundStyle(.primary)
                Text([book.author, book.category].filter { !$0.isEmpty }.joined(separator: " · ")).font(.system(size: 12)).lineLimit(1).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Image(systemName: "chevron.right").font(.system(size: 13)).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 13).overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 0.7) }
        .contentShape(Rectangle())
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

private struct BookDetailView: View {
    let book: NativeBook
    @ObservedObject var store: NativeReadingStore
    @Environment(\.dismiss) private var dismiss
    @State private var details: [String: String] = [:]
    @State private var chapters: [NativeChapter] = []
    @State private var loading = true
    @State private var error: String?
    @State private var reading = false

    private let ink = Color(red: 0.11, green: 0.11, blue: 0.11)
    private let muted = Color(red: 0.43, green: 0.43, blue: 0.41)
    private let line = Color(red: 0.88, green: 0.87, blue: 0.84)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    cover.frame(width: 92, height: 128).clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(book.title).font(.system(size: 19, weight: .bold)).lineSpacing(2).foregroundStyle(ink)
                        Text([book.author, book.category].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 12)).foregroundStyle(muted)
                        if let score = details["评分"], !score.isEmpty { Text("评分  \(score)").font(.system(size: 12, weight: .medium)).foregroundStyle(ink) }
                        if let count = details["字数"], !count.isEmpty { Text("字数  \(count)").font(.system(size: 12)).foregroundStyle(muted) }
                        if let status = details["状态"], !status.isEmpty { Text(status == "1" ? "连载中" : status).font(.system(size: 12)).foregroundStyle(muted) }
                    }
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16).padding(.top, 10)

                detailSection("简介") {
                    Text(clean(details["简介"] ?? details["作品简介"] ?? "正在加载作品简介…"))
                        .font(.system(size: 14)).lineSpacing(5).foregroundStyle(muted)
                }
                detailSection("目录", trailing: chapters.isEmpty ? "" : "共\(chapters.count)章 · 全部") {
                    if loading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 52)
                    } else if let error {
                        Text(error).font(.system(size: 13)).foregroundStyle(muted).padding(.vertical, 12)
                    } else {
                        ForEach(Array(chapters.prefix(3))) { chapter in
                            HStack {
                                Text(chapter.title).font(.system(size: 14)).lineLimit(1).foregroundStyle(ink)
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.tertiary)
                            }.padding(.vertical, 12)
                            if chapter.id != chapters.prefix(3).last?.id { Rectangle().fill(line).frame(height: 0.7) }
                        }
                    }
                }
                if let error {
                    Text("目录加载失败：\(error)").font(.system(size: 12)).foregroundStyle(muted).padding(.horizontal, 16).padding(.top, 10)
                }
                Text("作品编号  \(book.id)").font(.system(size: 11, design: .monospaced)).foregroundStyle(muted)
                    .padding(.horizontal, 16).padding(.top, 18).padding(.bottom, 24)
            }
            .frame(maxWidth: 840, alignment: .leading).frame(maxWidth: .infinity)
        }
        .background(Color(red: 0.957, green: 0.953, blue: 0.937))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            HStack(spacing: 8) {
                Button { store.addToShelf(book) } label: {
                    VStack(spacing: 3) { Image(systemName: "books.vertical").font(.system(size: 19)); Text("加入书架").font(.system(size: 10)) }
                        .foregroundStyle(muted).frame(width: 76, height: 48)
                }.buttonStyle(.plain)
                Button { reading = true } label: {
                    Text(loading ? "正在加载目录" : (chapters.isEmpty ? "开始阅读" : "开始阅读 · \(chapters[0].title)"))
                        .font(.system(size: 14, weight: .semibold)).lineLimit(1).frame(maxWidth: .infinity, minHeight: 42)
                        .foregroundStyle(.white).background(loading || chapters.isEmpty ? muted : Color(red: 0.94, green: 0.31, blue: 0.22), in: Capsule())
                }.buttonStyle(.plain).disabled(loading || chapters.isEmpty)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
            .background(Color(red: 0.99, green: 0.98, blue: 0.96).overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) })
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
        }
        .navigationDestination(isPresented: $reading) {
            ReaderView(book: book, store: store, addToShelf: { store.addToShelf(book) })
        }
        .task {
            async let detailLoad = store.mediaDetails(for: book)
            async let directoryLoad = store.directory(for: book)
            do { details = try await detailLoad }
            catch { self.error = error.localizedDescription }
            do { chapters = try await directoryLoad }
            catch { if self.error == nil { self.error = error.localizedDescription } }
            loading = false
        }
    }

    private var cover: some View {
        Group {
            if let url = book.coverURL {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { RoundedRectangle(cornerRadius: 6).fill(book.color.gradient) }
            } else {
                RoundedRectangle(cornerRadius: 6).fill(book.color.gradient).overlay(Image(systemName: "book.closed.fill").foregroundStyle(.white.opacity(0.8)))
            }
        }
    }

    private func detailSection<Content: View>(_ title: String, trailing: String = "", @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.system(size: 16, weight: .bold)).foregroundStyle(ink)
                Spacer()
                if !trailing.isEmpty { Text(trailing).font(.system(size: 11)).foregroundStyle(muted) }
            }
            content()
        }
        .padding(.horizontal, 16).padding(.top, 20)
    }

    private func clean(_ value: String) -> String {
        value.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ").replacingOccurrences(of: "&amp;", with: "&")
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
        .onAppear { store.beginReadingSession() }
        .onDisappear { store.endReadingSession() }
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
            store.recordProgress(for: book, chapter: chapters[index], progress: Double(index + 1) / Double(chapters.count))
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
    @ObservedObject var store: NativeReadingStore
    @State private var selectedEntry: String?
    private let entries: [(String, String, String)] = [
        ("统计", "chart.bar", "阅读记录、藏书与阅读时长"),
        ("设置", "gearshape", "阅读、外观、播放与本地数据"),
        ("离线缓存", "arrow.down.to.line", "管理小说与短剧的离线内容"),
        ("备份与导入", "archivebox", "本机备份、恢复与外部书架导入"),
        ("关于", "info.circle", "版本与应用信息")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("我的").font(.system(size: 23, weight: .heavy)).tracking(-0.7)
                    Text("04 / PERSONAL ARCHIVE").font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(1.05).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 18)

                HStack(spacing: 16) {
                    RoundedRectangle(cornerRadius: 12).fill(Color(red: 0.91, green: 0.88, blue: 0.81))
                        .frame(width: 56, height: 56)
                        .overlay(Image(systemName: "book.closed.fill").font(.system(size: 25)).foregroundStyle(Color(red: 0.40, green: 0.34, blue: 0.27)))
                    VStack(alignment: .leading, spacing: 6) {
                        Text("什锦铺").font(.system(size: 20, weight: .semibold))
                        Text("本地阅读档案 · 小说、短剧、漫画与听书").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Spacer(minLength: 0)
                }
                .padding(16).background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.09), lineWidth: 0.7))
                .padding(.horizontal, 16).padding(.bottom, 24)

                VStack(spacing: 14) {
                    ForEach(entries, id: \.0) { title, symbol, subtitle in
                        Button { selectedEntry = title } label: {
                            HStack(spacing: 12) {
                                Image(systemName: symbol).font(.system(size: 21, weight: .regular)).frame(width: 24).foregroundStyle(.primary)
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(title).font(.system(size: 15, weight: .semibold)).foregroundStyle(.primary)
                                    Text(subtitle).font(.system(size: 12)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 13, weight: .medium)).foregroundStyle(.tertiary)
                            }
                            .padding(16).frame(maxWidth: .infinity, minHeight: 72, alignment: .leading)
                            .background(Color.white.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.primary.opacity(0.09), lineWidth: 0.7))
                        }.buttonStyle(.plain)
                    }
                }.padding(.horizontal, 16).padding(.bottom, 100)
            }
        }
        .background(Color(red: 0.957, green: 0.953, blue: 0.937))
        .sheet(item: Binding(
            get: { selectedEntry.map(SettingsRoute.init(title:)) },
            set: { selectedEntry = $0?.title }
        )) { route in
            NavigationStack {
                Group {
                    if route.title == "统计" {
                        List {
                            LabeledContent("书架藏书", value: "\(store.shelf.filter { $0.kind == "book" }.count) 本")
                            LabeledContent("阅读记录", value: "\(store.readingHistory.count) 条")
                            LabeledContent("收藏内容", value: "\(store.favorites.count) 部")
                            LabeledContent("今日阅读时长", value: "\(store.todayReadMinutes) 分钟")
                        }
                    } else {
                        ContentUnavailableView(route.title, systemImage: entries.first(where: { $0.0 == route.title })?.1 ?? "info.circle", description: Text(entries.first(where: { $0.0 == route.title })?.2 ?? "小满阅读"))
                    }
                }
                .navigationTitle(route.title)
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { selectedEntry = nil } } }
            }
            .presentationDetents([.medium, .large])
        }
    }
}

private struct SettingsRoute: Identifiable {
    let title: String
    var id: String { title }
}
