import SwiftUI
import AVKit
import MediaPlayer
import UniformTypeIdentifiers
import CoreText
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
    @State private var selectedHomeRank: NativeHomeRank?

    public init() {}

    public var body: some View {
        Group {
            switch selection {
            case .home:
                NavigationStack {
                    HomeView(query: $query, store: store, onSearch: { showingSearch = true }, onCategories: { showingCategories = true }, onResume: { selectedReader = $0 }, onOpenRank: { selectedHomeRank = store.homeRank }) { item in
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
                NavigationStack { SettingsView(store: store, onReadOffline: { selectedReader = $0 }) }
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
        .sheet(item: $selectedHomeRank) { rank in
            NavigationStack {
                NativeRankListView(rank: rank, store: store) { item in
                    selectedHomeRank = nil
                    select(item)
                }
            }
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
        if item.id.hasPrefix("local_") { selectedReader = item; return }
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
    let onOpenRank: () -> Void
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
        let rankedIDs = selectedTab == 0 ? Set(store.homeRank?.books.map(\.id) ?? []) : []
        return store.homeItems.filter { $0.kind == kind && !rankedIDs.contains($0.id) }
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
                            if selectedTab == 0, let rank = store.homeRank, !rank.books.isEmpty {
                                NativeHomeRankShelf(rank: rank, store: store, availableWidth: geometry.size.width, viewportHeight: geometry.size.height, onSelect: onSelect, onOpenAll: onOpenRank)
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
                Text(selectedTab == 0 ? (store.homeRank == nil ? "01 / FOR YOU" : "02 / FOR YOU") : "01 / \((selectedTab < store.homeTabs.count ? store.homeTabs[selectedTab].title : "FOR YOU").uppercased())")
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

private struct NativeHomeRankShelf: View {
    let rank: NativeHomeRank
    @ObservedObject var store: NativeReadingStore
    let availableWidth: CGFloat
    let viewportHeight: CGFloat
    let onSelect: (NativeBook) -> Void
    let onOpenAll: () -> Void
    @State private var selectedBoard = 0
    @State private var selectedBook = 0
    @State private var loadedBooks: [NativeBook]?
    @State private var loadingBoard = false

    private var books: [NativeBook] { loadedBooks ?? rank.books }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("01 / RANKING").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(0.8).foregroundStyle(.secondary)
                    Text(rank.title).font(.system(size: 18, weight: .bold)).foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.11))
                }
                Spacer()
                Button(action: onOpenAll) {
                    HStack(spacing: 4) {
                        Text("完整榜单").font(.system(size: 12, weight: .medium))
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                    }.foregroundStyle(Color(red: 0.43, green: 0.43, blue: 0.41))
                }.buttonStyle(.plain)
            }
            .padding(.horizontal, 16).padding(.top, 16).padding(.bottom, 10)

            if rank.names.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(rank.names.enumerated()), id: \.offset) { index, name in
                            Button { selectBoard(index) } label: {
                                Text(name).font(.system(size: 12, weight: index == selectedBoard ? .semibold : .regular))
                                    .foregroundStyle(index == selectedBoard ? Color(red: 0.11, green: 0.11, blue: 0.11) : Color(red: 0.43, green: 0.43, blue: 0.41))
                                    .padding(.horizontal, 11).frame(height: 28)
                                    .background(index == selectedBoard ? Color.black.opacity(0.07) : .clear, in: Capsule())
                                    .overlay(Capsule().strokeBorder(Color.black.opacity(index == selectedBoard ? 0.07 : 0.1), lineWidth: 0.7))
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 16)
                }
            }

            GeometryReader { geometry in
                let metrics = NativeRankShelfMetrics(width: min(geometry.size.width, 520), viewportHeight: viewportHeight)
                let selected = books.indices.contains(selectedBook) ? books[selectedBook] : books[0]
                Group {
                    if let url = selected.coverURL {
                        AsyncImage(url: url) { phase in
                            NativeRankShelfDrawing(books: books, focus: selectedBook, metrics: metrics, focusedCover: phase)
                        } placeholder: {
                            NativeRankShelfDrawing(books: books, focus: selectedBook, metrics: metrics, focusedCover: nil)
                        }
                    } else {
                        NativeRankShelfDrawing(books: books, focus: selectedBook, metrics: metrics, focusedCover: nil)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { point in
                    guard !books.isEmpty else { return }
                    if abs(point.x - metrics.width / 2) < metrics.cover * metrics.scale * 0.35,
                       point.y < metrics.height * 0.74 {
                        onSelect(books[min(max(selectedBook, 0), books.count - 1)])
                    } else {
                        let delta = Int(((point.x - metrics.width / 2) / max(metrics.pitch, 1)).rounded())
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            selectedBook = min(max(selectedBook + delta, 0), books.count - 1)
                        }
                    }
                }
                .simultaneousGesture(DragGesture(minimumDistance: 14).onEnded { value in
                    guard abs(value.translation.width) > 20 else { return }
                    let pages = max(1, Int((abs(value.translation.width) / max(metrics.pitch, 1)).rounded()))
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
                        selectedBook = min(max(selectedBook + (value.translation.width < 0 ? pages : -pages), 0), books.count - 1)
                    }
                })
            }
            .frame(width: min(availableWidth, 520), height: NativeRankShelfMetrics(width: min(availableWidth, 520), viewportHeight: viewportHeight).height)
            .frame(maxWidth: .infinity)
            .overlay { if loadingBoard { ProgressView().tint(Color(red: 0.94, green: 0.31, blue: 0.22)) } }

            if books.indices.contains(selectedBook) {
                let book = books[selectedBook]
                Button { onSelect(book) } label: {
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(book.title).font(.system(size: 17, weight: .bold)).lineLimit(2).foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.11))
                            Text(book.author).font(.system(size: 12)).lineLimit(1).foregroundStyle(Color(red: 0.43, green: 0.43, blue: 0.41))
                        }
                        Spacer()
                        Image(systemName: "arrow.up.right").font(.system(size: 16, weight: .medium)).foregroundStyle(Color(red: 0.11, green: 0.11, blue: 0.11))
                    }
                    .frame(height: 78).padding(.horizontal, 16).contentShape(Rectangle())
                }.buttonStyle(.plain)
            }

            HStack(spacing: 8) {
                Text(String(format: "NO.%03d", selectedBook + 1)).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(.secondary)
                Spacer()
                Button { if selectedBook > 0 { selectedBook -= 1 } } label: { Image(systemName: "chevron.left").frame(width: 32, height: 34) }.disabled(selectedBook == 0)
                Text(String(format: "%02d / %02d", min(selectedBook + 1, books.count), min(books.count, 99)))
                    .font(.system(size: 9, weight: .medium, design: .monospaced)).frame(minWidth: 50)
                Button { if selectedBook + 1 < books.count { selectedBook += 1 } } label: { Image(systemName: "chevron.right").frame(width: 32, height: 34) }.disabled(selectedBook + 1 >= books.count)
            }
            .foregroundStyle(Color(red: 0.43, green: 0.43, blue: 0.41)).padding(.horizontal, 10).frame(height: 42).padding(.bottom, 5)
        }
        .overlay(alignment: .bottom) { Rectangle().fill(Color(red: 0.88, green: 0.87, blue: 0.84)).frame(height: 0.7) }
        .onChange(of: rank.id) { _, _ in selectedBoard = 0; selectedBook = 0; loadedBooks = nil }
    }

    private func selectBoard(_ index: Int) {
        guard rank.algorithms.indices.contains(index), index != selectedBoard else { return }
        selectedBoard = index
        selectedBook = 0
        loadedBooks = nil
        loadingBoard = true
        Task {
            do { loadedBooks = try await store.rankBoard(id: rank.id, algorithm: rank.algorithms[index]) }
            catch { loadedBooks = rank.books }
            loadingBoard = false
        }
    }
}

private struct NativeRankShelfMetrics {
    let width: CGFloat
    let spine: CGFloat
    let cover: CGFloat
    let bodyHeight: CGFloat
    let base: CGFloat
    let anchor: CGFloat
    let pitch: CGFloat
    let height: CGFloat
    let scale: CGFloat

    init(width: CGFloat, viewportHeight: CGFloat) {
        self.width = min(width, 520)
        spine = min(max(self.width * 0.043, 14), 18)
        cover = min(max(self.width * 0.32, 100), 128)
        bodyHeight = (cover - 20) * 166 / 118 + 54
        base = cover * 0.30 + bodyHeight * 0.60 + 12
        let naturalHeight = base + bodyHeight + 60
        let available = viewportHeight * 0.75 - 78 - 42 - 8
        height = min(naturalHeight, max(200, available))
        scale = height / naturalHeight
        anchor = (self.width / scale - spine - cover * 0.66) / 2 + cover * 0.84 * 0.66
        pitch = (spine + 11) * scale
    }
}

/// Native SwiftUI port of Android's finite three dimensional rank shelf.
/// Dimensions and the pull-out curve mirror `home_rank_shelf.dart` so the selected
/// book stays centered while neighboring spines recede along the same projection.
private struct NativeRankShelfDrawing: View {
    let books: [NativeBook]
    let focus: Int
    let metrics: NativeRankShelfMetrics
    let focusedCover: Image?

    var body: some View {
        Canvas { context, size in
            guard !books.isEmpty else { return }
            let g = metrics
            let scale = g.scale
            let spine = g.spine * scale
            let cover = g.cover * scale
            let body = g.bodyHeight * scale
            let depthX = cover * 0.66
            let depthY = cover * -0.30
            let base = g.base * scale
            let anchor = g.anchor * scale
            let pitch = g.pitch
            let centerFocus = min(max(focus, 0), books.count - 1)
            let lower = max(0, centerFocus - 16)
            let upper = min(books.count - 1, centerFocus + 16)

            for index in lower...upper {
                let distance = CGFloat(index - centerFocus)
                let crest = abs(distance) < 1.48 ? cos(distance / 1.48 * .pi / 2) : 0
                let weight = crest * crest
                let rail = min(max(distance, -7), 7)
                let pull = cover * 0.84 * weight * (1.24 - 0.24 * weight)
                let lift = weight * weight * (3 - 2 * weight)
                let x = anchor + distance * pitch - pull * 0.66
                let y = base + (rail * 2.5 + rail * rail * 0.45) * scale + pull * 0.30 - body * 0.60 * lift
                let book = books[index]
                let stroke = Color.black.opacity(0.16)

                if weight > 0.05 {
                    let shadowRect = CGRect(x: x + spine / 2 + depthX * 0.5 - cover * 0.55,
                                            y: y + body + 8 + depthY * 0.5,
                                            width: cover * 1.1, height: 18 * scale)
                    context.fill(Path(ellipseIn: shadowRect), with: .color(.black.opacity(0.08 * weight)))
                }

                let top = nativeRankQuad([CGPoint(x: x, y: y), CGPoint(x: x + spine, y: y),
                                          CGPoint(x: x + spine + depthX, y: y + depthY), CGPoint(x: x + depthX, y: y + depthY)])
                let side = nativeRankQuad([CGPoint(x: x + spine, y: y), CGPoint(x: x + spine + depthX, y: y + depthY),
                                           CGPoint(x: x + spine + depthX, y: y + depthY + body), CGPoint(x: x + spine, y: y + body)])
                let front = nativeRankQuad([CGPoint(x: x, y: y), CGPoint(x: x + spine, y: y),
                                            CGPoint(x: x + spine, y: y + body), CGPoint(x: x, y: y + body)])
                context.fill(top, with: .color(Color(red: 0.91, green: 0.90, blue: 0.86)))
                context.stroke(top, with: .color(stroke), lineWidth: 0.8)
                context.fill(side, with: .color(Color(red: 0.96, green: 0.95, blue: 0.92)))
                context.stroke(side, with: .color(stroke), lineWidth: 0.8)

                if weight > 0.25 {
                    var artwork = context
                    artwork.concatenate(CGAffineTransform(a: 0.66, b: -0.30, c: 0, d: 1, tx: x + spine, ty: y))
                    let art = CGRect(x: 9 * scale, y: 20 * scale, width: max(1, g.cover - 18) * scale, height: max(1, g.bodyHeight - 46) * scale)
                    let artPath = Path(roundedRect: art, cornerRadius: 1.8 * scale)
                    artwork.clip(to: artPath)
                    if index == centerFocus, let focusedCover {
                        artwork.draw(focusedCover.resizable(), in: art)
                    } else {
                        artwork.fill(artPath, with: .linearGradient(Gradient(colors: [book.color.opacity(0.95), book.color.opacity(0.58)]),
                                                                    startPoint: CGPoint(x: art.minX, y: art.minY), endPoint: CGPoint(x: art.maxX, y: art.maxY)))
                        var titleContext = artwork
                        titleContext.translateBy(x: art.midX, y: art.midY)
                        titleContext.rotate(by: .degrees(-90))
                        titleContext.draw(Text(String(book.title.prefix(8))).font(.system(size: 8 * scale, weight: .medium)).foregroundColor(.white),
                                          at: .zero, anchor: .center)
                    }
                    artwork.draw(Text("NO.\(String(format: "%03d", index + 1))").font(.system(size: 7 * scale, weight: .medium, design: .monospaced)).foregroundColor(.white),
                                 at: CGPoint(x: art.minX + 8 * scale, y: art.minY - 5 * scale), anchor: .topLeading)
                }

                context.fill(front, with: .color(Color(red: 0.99, green: 0.985, blue: 0.96)))
                context.stroke(front, with: .color(stroke), lineWidth: 0.8)
                let centreX = x + spine / 2
                context.draw(Text(String(format: "%02d", index + 1)).font(.system(size: 7 * scale, weight: .medium, design: .monospaced)).foregroundColor(Color(red: 0.48, green: 0.47, blue: 0.44)),
                                 at: CGPoint(x: centreX, y: y + 7 * scale), anchor: .top)
                var titleContext = context
                titleContext.translateBy(x: centreX, y: y + body / 2)
                titleContext.rotate(by: .degrees(-90))
                titleContext.draw(Text(book.title).font(.system(size: 8 * scale, weight: .medium, design: .serif)).foregroundColor(Color(red: 0.25, green: 0.24, blue: 0.22)),
                                  at: .zero, anchor: .center)
            }
        }
        .frame(width: metrics.width, height: metrics.height)
        .clipped()
    }
}

private func nativeRankQuad(_ points: [CGPoint]) -> Path {
    var path = Path()
    guard let first = points.first else { return path }
    path.move(to: first)
    for point in points.dropFirst() { path.addLine(to: point) }
    path.closeSubpath()
    return path
}

private struct NativeRankListView: View {
    let rank: NativeHomeRank
    @ObservedObject var store: NativeReadingStore
    let onSelect: (NativeBook) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var selectedBoard = 0
    @State private var entries: [NativeBook] = []
    @State private var loading = false
    @State private var hasMore = true
    @State private var message: String?

    var body: some View {
        VStack(spacing: 0) {
            if rank.names.count > 1 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(Array(rank.names.enumerated()), id: \.offset) { index, name in
                            Button { selectedBoard = index } label: {
                                Text(name).font(.system(size: 13, weight: selectedBoard == index ? .semibold : .regular))
                                    .foregroundStyle(selectedBoard == index ? .primary : .secondary)
                                    .padding(.horizontal, 12).frame(height: 34)
                                    .background(selectedBoard == index ? Color.primary.opacity(0.08) : .clear, in: Capsule())
                            }.buttonStyle(.plain)
                        }
                    }.padding(.horizontal, 16)
                }.padding(.vertical, 8)
            }
            if entries.isEmpty && loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let message, entries.isEmpty { ContentUnavailableView("榜单暂时无法打开", systemImage: "wifi.exclamationmark", description: Text(message)) }
            else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, item in
                            Button { onSelect(item) } label: {
                                HStack(spacing: 10) {
                                    Text(String(format: "%02d", index + 1)).font(.system(size: 13, weight: .semibold, design: .monospaced)).foregroundStyle(index < 3 ? Color(red: 0.94, green: 0.31, blue: 0.22) : .secondary).frame(width: 24)
                                    NativeSearchResultRow(book: item)
                                }.padding(.leading, 14)
                            }.buttonStyle(.plain)
                        }
                        if loading { ProgressView().padding(16) }
                        else if hasMore { Button("加载更多") { Task { await loadMore() } }.font(.system(size: 14, weight: .medium)).padding(16) }
                    }
                }
            }
        }
        .background(Color(red: 0.957, green: 0.953, blue: 0.937))
        .navigationTitle(rank.title)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .task(id: selectedBoard) { entries = []; hasMore = true; message = nil; await loadMore() }
    }

    @MainActor private func loadMore() async {
        guard !loading, hasMore, rank.algorithms.indices.contains(selectedBoard) else { return }
        loading = true
        defer { loading = false }
        do {
            let page = try await store.rankBoard(id: rank.id, algorithm: rank.algorithms[selectedBoard], offset: entries.count)
            entries.append(contentsOf: page.filter { candidate in !entries.contains(where: { $0.id == candidate.id }) })
            hasMore = page.count >= 20
        } catch { message = error.localizedDescription; hasMore = false }
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
            } else if media.kind == "manga" {
                NativeMangaDetailView(media: media, store: store)
            } else if media.kind == "audio" {
                NativeAudioDetailView(media: media, store: store)
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
            guard media.kind != "video" && media.kind != "manju" && media.kind != "manga" && media.kind != "audio" else { return }
            do { details = try await store.mediaDetails(for: media); error = nil }
            catch { self.error = error.localizedDescription }
            loading = false
        }
        .toolbar {
            if media.kind != "video" && media.kind != "manju" && media.kind != "manga" && media.kind != "audio" {
                ToolbarItem(placement: .automatic) { Button("完成") { dismiss() } }
            }
        }
    }
}

private struct NativeAudioDetailView: View {
    let media: NativeBook
    @ObservedObject var store: NativeReadingStore
    @State private var chapters: [NativeChapter] = []
    @State private var details: [String: String] = [:]
    @State private var voices: [NativeAudioVoice] = []
    @State private var selectedToneID = "0"
    @State private var selectedIndex = 0
    @State private var player: AVPlayer?
    @State private var cencLoader: NativeCENCResourceLoader?
    @State private var periodicObserver: Any?
    @State private var loading = true
    @State private var playing = false
    @State private var error: String?
    @State private var rate: Float = 1

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .top, spacing: 16) {
                    HomeMediaCard(item: media).frame(width: 112, height: 150).clipShape(RoundedRectangle(cornerRadius: 8))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(media.title).font(.title3.bold()).lineLimit(3)
                        Text(details["作者"] ?? media.author).font(.subheadline).foregroundStyle(.secondary)
                        if let count = details["集数"] { Text("共\(count)集").font(.caption).foregroundStyle(.secondary) }
                        Button { store.addToShelf(media) } label: {
                            Label(store.shelf.contains(where: { $0.id == media.id }) ? "已加入书架" : "加入书架", systemImage: "books.vertical")
                                .font(.subheadline.weight(.medium))
                        }.buttonStyle(.bordered)
                    }
                    Spacer(minLength: 0)
                }

                if let intro = details["简介"] ?? details["作品简介"], !intro.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("作品简介").font(.headline)
                        Text(intro).font(.subheadline).foregroundStyle(.secondary).lineSpacing(4)
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("播放章节").font(.headline)
                        Spacer()
                        if !voices.isEmpty {
                            Menu {
                                ForEach(voices) { voice in
                                    Button(voice.title) {
                                        selectedToneID = voice.id
                                        if player != nil { Task { await play(selectedIndex) } }
                                    }
                                }
                            } label: {
                                Label(voices.first(where: { $0.id == selectedToneID })?.title ?? "音色", systemImage: "waveform")
                                    .font(.subheadline)
                            }
                        }
                        if !chapters.isEmpty {
                            Menu {
                                ForEach(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                                    Button(chapter.title) { Task { await play(index) } }
                                }
                            } label: { Label("选集", systemImage: "list.bullet").font(.subheadline) }
                        }
                    }
                    if loading { ProgressView("正在加载音频目录") }
                    else if chapters.isEmpty {
                        if let error { Text(error).font(.subheadline).foregroundStyle(.secondary) }
                        else { ContentUnavailableView("暂无可播放章节", systemImage: "headphones") }
                    }
                    else {
                        if let error { Text(error).font(.caption).foregroundStyle(.red) }
                        Text(chapters[selectedIndex].title).font(.title3.weight(.semibold)).lineLimit(2)
                        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                            let duration = player?.currentItem?.duration.seconds ?? 0
                            let position = player?.currentTime().seconds ?? 0
                            VStack(spacing: 6) {
                                Slider(value: Binding(get: { position.isFinite ? min(position, duration.isFinite ? duration : position) : 0 }, set: { player?.seek(to: CMTime(seconds: $0, preferredTimescale: 600)) }), in: 0...max(1, duration.isFinite ? duration : 1))
                                HStack {
                                    Text(Self.timeLabel(position)).monospacedDigit()
                                    Spacer()
                                    Text(Self.timeLabel(duration)).monospacedDigit()
                                }.font(.caption2).foregroundStyle(.secondary)
                            }
                            .onChange(of: Int(position.isFinite ? position / 10 : 0)) { _, _ in
                                guard chapters.indices.contains(selectedIndex), let player else { return }
                                store.recordAudioProgress(for: media, chapter: chapters[selectedIndex], chapterIndex: selectedIndex, chapterCount: chapters.count, position: player.currentTime().seconds, duration: player.currentItem?.duration.seconds ?? 0, rate: Double(rate))
                            }
                        }
                        HStack(spacing: 28) {
                            Button { Task { await play(max(0, selectedIndex - 1)) } } label: { Image(systemName: "backward.end.fill").font(.title3) }
                                .disabled(selectedIndex == 0)
                            Button {
                                if playing { player?.pause(); playing = false }
                                else { player?.playImmediately(atRate: rate); playing = true }
                                refreshNowPlaying()
                            } label: {
                                Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill")
                                    .font(.system(size: 58)).symbolRenderingMode(.palette).foregroundStyle(Color(red: 0.94, green: 0.31, blue: 0.22), .secondary)
                            }
                            Button { Task { await play(min(chapters.count - 1, selectedIndex + 1)) } } label: { Image(systemName: "forward.end.fill").font(.title3) }
                                .disabled(selectedIndex + 1 >= chapters.count)
                            Menu {
                                ForEach([0.75, 1.0, 1.25, 1.5, 2.0], id: \.self) { value in
                                    Button("\(value.formatted())×") { rate = Float(value); if playing { player?.rate = rate }; refreshNowPlaying() }
                                }
                            } label: { Text("\(rate.formatted())×").font(.subheadline.monospacedDigit()).frame(minWidth: 42) }
                        }
                        .frame(maxWidth: .infinity)
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
                .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 16))
            }
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity)
            .padding(20)
        }
        .background(appBackground)
        .navigationTitle("听书")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            async let detailLoad = store.mediaDetails(for: media)
            async let voicesLoad = store.audioVoices(for: media)
            do { chapters = try await store.directory(for: media) }
            catch { self.error = error.localizedDescription }
            do { details = try await detailLoad }
            catch { if self.error == nil { self.error = error.localizedDescription } }
            do {
                voices = try await voicesLoad
                if let first = voices.first { selectedToneID = first.id }
            } catch { /* Keep the service's default voice as a fallback. */ }
            rate = store.savedAudioRate(for: media)
            if let chapterID = store.savedChapterId(for: media), let index = chapters.firstIndex(where: { $0.id == chapterID }) {
                selectedIndex = index
            }
            loading = false
        }
        .onReceive(NotificationCenter.default.publisher(for: .AVPlayerItemDidPlayToEndTime)) { notification in
            guard (notification.object as? AVPlayerItem) === player?.currentItem else { return }
            if selectedIndex + 1 < chapters.count { Task { await play(selectedIndex + 1) } }
            else { playing = false; refreshNowPlaying() }
        }
        .onDisappear {
            if chapters.indices.contains(selectedIndex), let player {
                store.recordAudioProgress(for: media, chapter: chapters[selectedIndex], chapterIndex: selectedIndex, chapterCount: chapters.count, position: player.currentTime().seconds, duration: player.currentItem?.duration.seconds ?? 0, rate: Double(rate))
            }
            player?.pause()
            if let periodicObserver, let player { player.removeTimeObserver(periodicObserver) }
            periodicObserver = nil
            NativeAudioRemoteControls.shared.clear()
            player = nil; cencLoader = nil; playing = false
        }
    }

    @MainActor private func play(_ index: Int) async {
        guard chapters.indices.contains(index) else { return }
        error = nil
        do {
            let source = try await store.audioSource(for: chapters[index], book: media, toneID: selectedToneID)
            #if os(iOS)
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.allowAirPlay, .allowBluetoothA2DP])
            try AVAudioSession.sharedInstance().setActive(true)
            #endif
            if let periodicObserver, let player { player.removeTimeObserver(periodicObserver) }
            periodicObserver = nil
            player?.pause()
            cencLoader = nil
            let next: AVPlayer
            if source.keyHex != nil {
                let loader = NativeCENCResourceLoader(source: source)
                next = AVPlayer(playerItem: try loader.makePlayerItem())
                cencLoader = loader
            } else {
                next = AVPlayer(url: source.url)
            }
            next.automaticallyWaitsToMinimizeStalling = true
            player = next
            selectedIndex = index
            playing = true
            installRemoteControls()
            refreshNowPlaying()
            periodicObserver = next.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) { time in
                let elapsed = time.seconds
                let duration = next.currentItem?.duration.seconds ?? 0
                Task { @MainActor in
                    NativeAudioRemoteControls.shared.update(title: chapters[index].title, artist: details["作者"] ?? media.author, album: media.title, elapsed: elapsed, duration: duration, rate: Double(rate), playing: next.rate > 0)
                }
            }
            let resume = store.savedAudioPosition(for: media, chapter: chapters[index])
            if resume > 0 {
                next.seek(to: CMTime(seconds: resume, preferredTimescale: 600)) { _ in next.playImmediately(atRate: rate) }
            } else { next.playImmediately(atRate: rate) }
            store.recordAudioProgress(for: media, chapter: chapters[index], chapterIndex: index, chapterCount: chapters.count, position: resume, duration: 0, rate: Double(rate))
        } catch { self.error = error.localizedDescription; playing = false }
    }

    @MainActor private func installRemoteControls() {
        NativeAudioRemoteControls.shared.install(
            onPlay: { player?.playImmediately(atRate: rate); playing = true; refreshNowPlaying() },
            onPause: { player?.pause(); playing = false; refreshNowPlaying() },
            onNext: { Task { await play(min(chapters.count - 1, selectedIndex + 1)) } },
            onPrevious: { Task { await play(max(0, selectedIndex - 1)) } },
            onSeek: { seconds in player?.seek(to: CMTime(seconds: seconds, preferredTimescale: 600)); refreshNowPlaying() }
        )
    }

    @MainActor private func refreshNowPlaying() {
        guard chapters.indices.contains(selectedIndex), let player else { return }
        NativeAudioRemoteControls.shared.update(
            title: chapters[selectedIndex].title,
            artist: details["作者"] ?? media.author,
            album: media.title,
            elapsed: player.currentTime().seconds,
            duration: player.currentItem?.duration.seconds ?? 0,
            rate: Double(rate),
            playing: playing
        )
    }

    private static func timeLabel(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let value = Int(seconds)
        return String(format: "%d:%02d", value / 60, value % 60)
    }
}

@MainActor
private final class NativeAudioRemoteControls {
    static let shared = NativeAudioRemoteControls()
    private var installed = false
    private var onPlay: (() -> Void)?
    private var onPause: (() -> Void)?
    private var onNext: (() -> Void)?
    private var onPrevious: (() -> Void)?
    private var onSeek: ((Double) -> Void)?

    private init() {}

    func install(onPlay: @escaping () -> Void, onPause: @escaping () -> Void, onNext: @escaping () -> Void, onPrevious: @escaping () -> Void, onSeek: @escaping (Double) -> Void) {
        self.onPlay = onPlay
        self.onPause = onPause
        self.onNext = onNext
        self.onPrevious = onPrevious
        self.onSeek = onSeek
        guard !installed else { return }
        installed = true
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = true
        commands.pauseCommand.isEnabled = true
        commands.togglePlayPauseCommand.isEnabled = true
        commands.nextTrackCommand.isEnabled = true
        commands.previousTrackCommand.isEnabled = true
        commands.changePlaybackPositionCommand.isEnabled = true
        commands.skipForwardCommand.isEnabled = true
        commands.skipBackwardCommand.isEnabled = true
        commands.playCommand.addTarget { [weak self] _ in self?.onPlay?(); return .success }
        commands.pauseCommand.addTarget { [weak self] _ in self?.onPause?(); return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            if MPNowPlayingInfoCenter.default().playbackState == .playing { self.onPause?() } else { self.onPlay?() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in self?.onNext?(); return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in self?.onPrevious?(); return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent, let self else { return .commandFailed }
            self.onSeek?(event.positionTime)
            return .success
        }
        commands.skipForwardCommand.preferredIntervals = [15]
        commands.skipForwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            let current = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? 0
            self.onSeek?(current + 15)
            return .success
        }
        commands.skipBackwardCommand.preferredIntervals = [15]
        commands.skipBackwardCommand.addTarget { [weak self] _ in
            guard let self else { return .commandFailed }
            let current = MPNowPlayingInfoCenter.default().nowPlayingInfo?[MPNowPlayingInfoPropertyElapsedPlaybackTime] as? Double ?? 0
            self.onSeek?(max(0, current - 15))
            return .success
        }
    }

    func update(title: String, artist: String, album: String, elapsed: Double, duration: Double, rate: Double, playing: Bool) {
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: title,
            MPMediaItemPropertyArtist: artist,
            MPMediaItemPropertyAlbumTitle: album,
            MPNowPlayingInfoPropertyPlaybackRate: playing ? rate : 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: elapsed.isFinite ? max(0, elapsed) : 0
        ]
        if duration.isFinite, duration > 0 { info[MPMediaItemPropertyPlaybackDuration] = duration }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = playing ? .playing : .paused
    }

    func clear() {
        onPlay = nil; onPause = nil; onNext = nil; onPrevious = nil; onSeek = nil
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.isEnabled = false
        commands.pauseCommand.isEnabled = false
        commands.togglePlayPauseCommand.isEnabled = false
        commands.nextTrackCommand.isEnabled = false
        commands.previousTrackCommand.isEnabled = false
        commands.changePlaybackPositionCommand.isEnabled = false
        commands.skipForwardCommand.isEnabled = false
        commands.skipBackwardCommand.isEnabled = false
        MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
        MPNowPlayingInfoCenter.default().playbackState = .stopped
    }
}

private struct NativeMangaDetailView: View {
    let media: NativeBook
    @ObservedObject var store: NativeReadingStore
    @Environment(\.dismiss) private var dismiss
    @State private var details: [String: String] = [:]
    @State private var chapters: [NativeChapter] = []
    @State private var loading = true
    @State private var error: String?
    @State private var selectedIndex = 0
    @State private var reading = false

    private let ink = Color(red: 0.11, green: 0.11, blue: 0.11)
    private let muted = Color(red: 0.43, green: 0.43, blue: 0.41)
    private let line = Color(red: 0.88, green: 0.87, blue: 0.84)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    cover.frame(width: 100, height: 140).clipShape(RoundedRectangle(cornerRadius: 6))
                    VStack(alignment: .leading, spacing: 7) {
                        Text(media.title).font(.system(size: 19, weight: .bold)).lineSpacing(2).foregroundStyle(ink)
                        Text([media.author, media.category].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.system(size: 12)).foregroundStyle(muted)
                        if let status = details["状态"], !status.isEmpty { Text(status == "1" ? "连载中" : status).font(.system(size: 12)).foregroundStyle(muted) }
                        if !chapters.isEmpty { Text("共\(chapters.count)话").font(.system(size: 12)).foregroundStyle(muted) }
                        HStack(spacing: 12) {
                            Button { store.toggleFavorite(media) } label: {
                                Label(store.favorites.contains(where: { $0.id == media.id }) ? "已收藏" : "收藏", systemImage: store.favorites.contains(where: { $0.id == media.id }) ? "heart.fill" : "heart")
                            }.buttonStyle(.plain)
                            Button { store.addToShelf(media) } label: { Label("加入书架", systemImage: "books.vertical") }.buttonStyle(.plain)
                        }.font(.system(size: 12, weight: .medium)).foregroundStyle(ink).padding(.top, 5)
                    }
                    Spacer(minLength: 0)
                }.padding(.horizontal, 16).padding(.top, 12)

                section("简介") {
                    Text(clean(details["简介"] ?? details["作品简介"] ?? "正在加载作品简介…"))
                        .font(.system(size: 14)).lineSpacing(5).foregroundStyle(muted)
                }

                section("章节", trailing: chapters.isEmpty ? "" : "共\(chapters.count)话") {
                    if loading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 52)
                    } else if chapters.isEmpty {
                        Text(error ?? "暂时没有章节").font(.system(size: 13)).foregroundStyle(muted).padding(.vertical, 14)
                    } else {
                        ForEach(Array(chapters.prefix(12).enumerated()), id: \.element.id) { index, chapter in
                            Button { selectedIndex = index; reading = true } label: {
                                HStack(spacing: 10) {
                                    Text(String(format: "%02d", index + 1)).font(.system(size: 11, weight: .medium, design: .monospaced)).foregroundStyle(muted)
                                    Text(chapter.title).font(.system(size: 14)).lineLimit(1).foregroundStyle(ink)
                                    Spacer()
                                    Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.tertiary)
                                }.frame(height: 42)
                            }.buttonStyle(.plain)
                            if index < min(chapters.count, 12) - 1 { Rectangle().fill(line).frame(height: 0.7) }
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
                Button { store.toggleFavorite(media) } label: {
                    VStack(spacing: 3) { Image(systemName: "heart").font(.system(size: 19)); Text("收藏").font(.system(size: 10)) }
                        .foregroundStyle(muted).frame(width: 66, height: 48)
                }.buttonStyle(.plain)
                Button { selectedIndex = 0; reading = true; store.recordMediaHistory(media) } label: {
                    Text(loading ? "正在加载章节" : "开始阅读")
                        .font(.system(size: 14, weight: .semibold)).frame(maxWidth: .infinity, minHeight: 42)
                        .foregroundStyle(.white).background(loading || chapters.isEmpty ? muted : Color(red: 0.94, green: 0.31, blue: 0.22), in: Capsule())
                }.buttonStyle(.plain).disabled(loading || chapters.isEmpty)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
            .background(Color(red: 0.99, green: 0.98, blue: 0.96).overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) })
        }
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
        .navigationDestination(isPresented: $reading) {
            if chapters.indices.contains(selectedIndex) {
                NativeComicReaderView(book: media, chapters: chapters, initialIndex: selectedIndex, store: store)
            }
        }
        .task {
            async let detailLoad = store.mediaDetails(for: media)
            async let directoryLoad = store.directory(for: media)
            do { details = try await detailLoad } catch { self.error = error.localizedDescription }
            do { chapters = try await directoryLoad } catch { if self.error == nil { self.error = error.localizedDescription } }
            if let savedID = store.savedChapterId(for: media), let savedIndex = chapters.firstIndex(where: { $0.id == savedID }) {
                selectedIndex = savedIndex
            }
            loading = false
        }
    }

    private var cover: some View {
        Group {
            if let url = media.coverURL { AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { RoundedRectangle(cornerRadius: 6).fill(media.color.gradient) } }
            else { NativeCoverPlaceholder(item: media) }
        }
    }

    private func section<Content: View>(_ title: String, trailing: String = "", @ViewBuilder content: () -> Content) -> some View {
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

private struct NativeComicReaderView: View {
    let book: NativeBook
    let chapters: [NativeChapter]
    let initialIndex: Int
    @ObservedObject var store: NativeReadingStore
    @State private var selectedIndex: Int
    @State private var pages: [NativeComicPage] = []
    @State private var loading = true
    @State private var error: String?
    @State private var currentPage = 1
    @State private var visiblePageID: Int? = 0
    @State private var showCatalog = false
    @Environment(\.dismiss) private var dismiss

    init(book: NativeBook, chapters: [NativeChapter], initialIndex: Int, store: NativeReadingStore) {
        self.book = book
        self.chapters = chapters
        self.initialIndex = initialIndex
        self.store = store
        _selectedIndex = State(initialValue: initialIndex)
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Color.black.ignoresSafeArea()
                if loading {
                    ProgressView("正在加载漫画").tint(.white).foregroundStyle(.white)
                } else if let error {
                    ContentUnavailableView("漫画暂时无法打开", systemImage: "wifi.exclamationmark", description: Text(error))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, maxHeight: .infinity).background(.black)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 0) {
                                ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                                    AsyncImage(url: page.url) { phase in
                                        if let image = phase.image {
                                            image.resizable().scaledToFit().frame(maxWidth: .infinity)
                                        } else if phase.error != nil {
                                            VStack(spacing: 8) {
                                                Image(systemName: "photo").font(.system(size: 30))
                                                Text("图片加载失败").font(.caption)
                                            }.foregroundStyle(.white.opacity(0.7)).frame(maxWidth: .infinity).frame(height: geometry.size.height * 0.6)
                                        } else {
                                            ProgressView().tint(.white).frame(maxWidth: .infinity).frame(height: min(geometry.size.height * 0.6, 560))
                                        }
                                    }
                                    .id(index)
                                }
                            }
                            .scrollTargetLayout()
                        }
                        .coordinateSpace(name: "comicScroll")
                        .scrollPosition(id: $visiblePageID, anchor: .top)
                        .onChange(of: visiblePageID) { _, pageID in
                            currentPage = (pageID ?? 0) + 1
                            store.recordComicProgress(for: book, chapter: chapters[selectedIndex], chapterIndex: selectedIndex, page: Double(pageID ?? 0), pageCount: pages.count, chapterCount: chapters.count)
                        }
                        .onChange(of: pages.count) { _, count in
                            guard count > 0 else { return }
                            let restoredPage = min(store.savedComicPage(for: book, chapterIndex: selectedIndex), count - 1)
                            visiblePageID = restoredPage
                            currentPage = restoredPage + 1
                            proxy.scrollTo(restoredPage, anchor: .top)
                        }
                        .onChange(of: selectedIndex) { _, _ in
                            Task { await loadChapter() }
                            visiblePageID = 0
                            proxy.scrollTo(0, anchor: .top)
                        }
                    }
                    HStack(spacing: 16) {
                        Button { if selectedIndex > 0 { selectedIndex -= 1 } } label: { Image(systemName: "chevron.left") }
                            .disabled(selectedIndex == 0)
                        Button { showCatalog = true } label: {
                            Text("\(chapters[selectedIndex].title)  ·  \(currentPage)/\(max(1, pages.count))")
                                .font(.system(size: 12, weight: .medium)).lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        Button { if selectedIndex + 1 < chapters.count { selectedIndex += 1 } } label: { Image(systemName: "chevron.right") }
                            .disabled(selectedIndex + 1 >= chapters.count)
                    }
                    .buttonStyle(.plain).foregroundStyle(.white)
                    .padding(.horizontal, 18).frame(height: 48)
                    .background(.ultraThinMaterial.opacity(0.85), in: Capsule())
                    .padding(.horizontal, 22).padding(.bottom, 10)
                }
            }
        }
        .background(.black)
        #if os(iOS)
        .toolbar(.hidden, for: .navigationBar)
        #endif
        .safeAreaInset(edge: .top, spacing: 0) {
            HStack(spacing: 12) {
                Button { dismiss() } label: { Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).frame(width: 36, height: 40) }
                    .accessibilityLabel("关闭漫画阅读")
                Text(book.title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Spacer(minLength: 4)
                Button { showCatalog = true } label: { Image(systemName: "list.bullet").font(.system(size: 17, weight: .medium)).frame(width: 36, height: 40) }
                    .accessibilityLabel("打开漫画目录")
            }
            .buttonStyle(.plain).foregroundStyle(.white).padding(.horizontal, 14)
            .background(Color.black.opacity(0.86))
        }
        .sheet(isPresented: $showCatalog) {
            NavigationStack {
                List(Array(chapters.enumerated()), id: \.element.id) { index, chapter in
                    Button {
                        showCatalog = false
                        selectedIndex = index
                    } label: {
                        HStack {
                            Text(chapter.title).foregroundStyle(index == selectedIndex ? Color(red: 0.94, green: 0.31, blue: 0.22) : .primary)
                            Spacer()
                            if index == selectedIndex { Image(systemName: "checkmark").foregroundStyle(Color(red: 0.94, green: 0.31, blue: 0.22)) }
                        }
                    }.buttonStyle(.plain)
                }
                .navigationTitle("漫畫目錄")
                .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { showCatalog = false } } }
            }
            .presentationDetents([.medium, .large])
        }
        .task { store.recordMediaHistory(book); await loadChapter() }
    }

    @MainActor private func loadChapter() async {
        guard chapters.indices.contains(selectedIndex) else { return }
        loading = true
        error = nil
        pages = []
        currentPage = 1
        visiblePageID = 0
        do {
            pages = try await store.comicPages(for: chapters[selectedIndex], book: book)
            store.recordComicProgress(for: book, chapter: chapters[selectedIndex], chapterIndex: selectedIndex, page: 0, pageCount: pages.count, chapterCount: chapters.count)
        } catch { self.error = error.localizedDescription }
        loading = false
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
    @AppStorage("xiaoman.shelf.layout") private var layout = 0
    @State private var filter = 0
    @State private var isEditing = false
    @State private var selectedIDs = Set<String>()
    @State private var confirmingRemoval = false
    @State private var confirmingHistoryClear = false
    @State private var importingLocalBook = false
    @State private var importError: String?
    @State private var lastLongPressAt = Date.distantPast

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
                if isEditing {
                    Button("取消") { isEditing = false; selectedIDs.removeAll() }.foregroundStyle(muted)
                    Text("已选 \(selectedIDs.count) 项").font(.system(size: 17, weight: .semibold)).foregroundStyle(ink)
                    Spacer()
                    Button(selectedIDs.count == entries.count ? "取消全选" : "全选") {
                        selectedIDs = selectedIDs.count == entries.count ? [] : Set(entries.map { "\($0.kind):\($0.id)" })
                    }.foregroundStyle(ink)
                } else {
                    HStack(spacing: 20) {
                        ForEach(Array(["书架", "浏览历史", "收藏"].enumerated()), id: \.offset) { index, title in
                            Button { withAnimation(.easeOut(duration: 0.18)) { tab = index; selectedIDs.removeAll() } } label: {
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
                }
                Menu {
                    if tab == 0 && !isEditing { Button("导入本地书籍", systemImage: "doc.badge.plus") { importingLocalBook = true } }
                    Button("切换为宫格", systemImage: "square.grid.3x3") { layout = 0 }
                    Button("切换为双列", systemImage: "square.grid.2x2") { layout = 1 }
                    Button("切换为列表", systemImage: "list.bullet") { layout = 2 }
                    if tab == 1 { Button("清空历史", systemImage: "trash", role: .destructive) { confirmingHistoryClear = true } }
                    if !isEditing { Button("管理内容", systemImage: "checkmark.circle") { isEditing = true; selectedIDs.removeAll() } }
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
                                Button {
                                    if Date().timeIntervalSince(lastLongPressAt) < 0.8 { return }
                                    let key = "\(book.kind):\(book.id)"
                                    if isEditing {
                                        if !selectedIDs.insert(key).inserted { selectedIDs.remove(key) }
                                    } else { onSelect(book) }
                                } label: {
                                    ZStack(alignment: .topTrailing) {
                                        ShelfBookCard(book: book, width: cardWidth, list: layout == 2)
                                        if isEditing {
                                            Image(systemName: selectedIDs.contains("\(book.kind):\(book.id)") ? "checkmark.circle.fill" : "circle")
                                                .font(.system(size: 22)).symbolRenderingMode(.palette)
                                                .foregroundStyle(.white, selectedIDs.contains("\(book.kind):\(book.id)") ? Color(red: 0.94, green: 0.31, blue: 0.22) : Color.black.opacity(0.42))
                                                .padding(7)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                                .highPriorityGesture(LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                                    lastLongPressAt = Date()
                                    if !isEditing { isEditing = true; selectedIDs = ["\(book.kind):\(book.id)"] }
                                })
                            }
                        }
                        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 100)
                    }
                }
            }
        }
        .background(Color(red: 0.957, green: 0.953, blue: 0.937))
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isEditing {
                HStack(spacing: 12) {
                    Text(tab == 1 ? "选择历史记录" : "选择要移除的内容").font(.system(size: 12)).foregroundStyle(muted)
                    Spacer()
                    Button("删除", role: .destructive) { confirmingRemoval = true }
                        .disabled(selectedIDs.isEmpty)
                        .font(.system(size: 14, weight: .semibold)).padding(.horizontal, 24).padding(.vertical, 10)
                        .background(selectedIDs.isEmpty ? Color.gray.opacity(0.18) : Color.red, in: Capsule())
                        .foregroundStyle(selectedIDs.isEmpty ? muted : .white)
                }
                .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 12)
                .background(.regularMaterial)
            }
        }
        .confirmationDialog(tab == 1 ? "删除所选历史记录？" : "从书架移除所选内容？", isPresented: $confirmingRemoval, titleVisibility: .visible) {
            Button("删除所选内容", role: .destructive) {
                let selected = entries.filter { selectedIDs.contains("\($0.kind):\($0.id)") }
                if tab == 1 { store.removeFromReadingHistory(selected) }
                else { store.removeFromShelf(selected) }
                selectedIDs.removeAll(); isEditing = false
            }
            Button("取消", role: .cancel) {}
        }
        .confirmationDialog("清空全部浏览历史？", isPresented: $confirmingHistoryClear, titleVisibility: .visible) {
            Button("清空历史", role: .destructive) { store.clearReadingHistory() }
            Button("取消", role: .cancel) {}
        } message: { Text("清空后无法恢复。") }
        .fileImporter(isPresented: $importingLocalBook, allowedContentTypes: [.plainText, UTType(filenameExtension: "epub") ?? .data], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else {
                if case .failure(let error) = result { importError = error.localizedDescription }
                return
            }
            do { _ = try store.importLocalBookFile(url) }
            catch { importError = error.localizedDescription }
        }
        .alert("导入失败", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
            Button("好", role: .cancel) { importError = nil }
        } message: { Text(importError ?? "") }
    }
}

private struct NativeBookCover: View {
    let book: NativeBook
    let width: CGFloat
    let height: CGFloat
    @State private var localImage: Image?

    var body: some View {
        Group {
            if let url = book.coverURL, url.isFileURL {
                if let localImage { localImage.resizable().scaledToFill() }
                else { placeholder }
            } else if let url = book.coverURL {
                AsyncImage(url: url) { image in image.resizable().scaledToFill() } placeholder: { placeholder }
            } else {
                placeholder
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .task(id: book.coverURL) {
            guard let url = book.coverURL, url.isFileURL else { localImage = nil; return }
            let data = try? await Task.detached(priority: .utility) { try Data(contentsOf: url, options: .mappedIfSafe) }.value
#if os(iOS)
            localImage = data.flatMap { UIImage(data: $0) }.map { Image(uiImage: $0) }
#else
            localImage = data.flatMap { NSImage(data: $0) }.map { Image(nsImage: $0) }
#endif
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 10).fill(book.color.gradient)
            .overlay(Image(systemName: "book.closed.fill").foregroundStyle(.white.opacity(0.78)))
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
        NativeBookCover(book: book, width: width, height: height)
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
    @State private var comments: [NativeBookComment] = []
    @State private var commentTotalCount = 0
    @State private var commentScoreCount = 0
    @State private var commentScoreContext = ""
    @State private var commentOffset = 0
    @State private var commentsHasMore = false
    @State private var commentsLoading = false
    @State private var commentsError: String?
    @State private var loading = true
    @State private var error: String?
    @State private var reading = false
    @State private var readingChapterID: String?
    @State private var showDirectory = false
    @State private var cacheError: String?

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
                detailSection("目录") {
                    if loading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 52)
                    } else if let error {
                        Text(error).font(.system(size: 13)).foregroundStyle(muted).padding(.vertical, 12)
                    } else {
                        HStack {
                            Text("共\(chapters.count)章").font(.system(size: 11)).foregroundStyle(muted)
                            Spacer()
                            Button("全部") { showDirectory = true }
                                .font(.system(size: 12, weight: .medium)).foregroundStyle(Color(red: 0.72, green: 0.36, blue: 0.24))
                        }
                        ForEach(previewChapters) { chapter in
                            Button {
                                readingChapterID = chapter.id
                                reading = true
                            } label: {
                                HStack {
                                    Text(chapter.title).font(.system(size: 14)).lineLimit(1).foregroundStyle(ink)
                                    Spacer()
                                    if chapter.id == store.savedChapterId(for: book) {
                                        Text("读至").font(.system(size: 10)).foregroundStyle(muted)
                                    }
                                    Image(systemName: "chevron.right").font(.system(size: 11)).foregroundStyle(.tertiary)
                                }.padding(.vertical, 12).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                            if chapter.id != previewChapters.last?.id { Rectangle().fill(line).frame(height: 0.7) }
                        }
                    }
                }
                detailSection(commentSectionTitle, trailing: commentScoreContext.isEmpty ? (commentScoreCount > 0 ? "\(commentScoreCount)人点评" : "") : commentScoreContext) {
                    if comments.isEmpty && commentsLoading {
                        ProgressView().frame(maxWidth: .infinity, minHeight: 52)
                    } else if comments.isEmpty, let commentsError {
                        HStack(spacing: 10) {
                            Text(commentsError).font(.system(size: 13)).foregroundStyle(muted)
                            Button("重试") { Task { await loadComments(reset: true) } }
                                .font(.system(size: 13, weight: .medium))
                        }.padding(.vertical, 12)
                    } else if comments.isEmpty {
                        Text("还没有读者评论").font(.system(size: 13)).foregroundStyle(muted).padding(.vertical, 12)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(comments) { comment in
                                NativeBookCommentRow(comment: comment, ink: ink, muted: muted)
                                if comment.id != comments.last?.id {
                                    Rectangle().fill(line).frame(height: 0.7).padding(.vertical, 12)
                                }
                            }
                            if commentsLoading {
                                ProgressView().frame(maxWidth: .infinity).padding(.vertical, 14)
                            } else if let commentsError {
                                HStack {
                                    Text(commentsError).font(.system(size: 12)).foregroundStyle(muted)
                                    Spacer()
                                    Button("重试") { Task { await loadComments(reset: false) } }
                                        .font(.system(size: 12, weight: .medium))
                                }.padding(.top, 12)
                            } else if commentsHasMore {
                                Button { Task { await loadComments(reset: false) } } label: {
                                    HStack { Spacer(); Text("加载更多书评"); Image(systemName: "chevron.down"); Spacer() }
                                        .font(.system(size: 13, weight: .medium)).foregroundStyle(muted).padding(.vertical, 14)
                                }.buttonStyle(.plain)
                            }
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
                    Text(loading ? "正在加载目录" : (chapters.isEmpty ? "开始阅读" : startReadingTitle))
                        .font(.system(size: 14, weight: .semibold)).lineLimit(1).frame(maxWidth: .infinity, minHeight: 42)
                        .foregroundStyle(.white).background(loading || chapters.isEmpty ? muted : Color(red: 0.94, green: 0.31, blue: 0.22), in: Capsule())
                }.buttonStyle(.plain).disabled(loading || chapters.isEmpty)
            }
            .padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 10)
            .background(Color(red: 0.99, green: 0.98, blue: 0.96).overlay(alignment: .top) { Rectangle().fill(line).frame(height: 1) })
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            ToolbarItem(placement: .automatic) {
                Button("下载到离线", systemImage: "arrow.down.to.line") {
                    Task {
                        do { try await store.cacheBook(book) }
                        catch { cacheError = error.localizedDescription }
                    }
                }
                .disabled(store.offlineCacheProgress[book.id] != nil)
            }
        }
        .overlay(alignment: .bottom) {
            if let progress = store.offlineCacheProgress[book.id] {
                HStack(spacing: 10) {
                    ProgressView(value: progress).tint(Color(red: 0.94, green: 0.31, blue: 0.22))
                    Text("离线缓存 \(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .medium)).monospacedDigit()
                }
                .padding(14).background(.regularMaterial, in: Capsule()).padding(.bottom, 74)
            }
        }
        .alert("离线缓存未完成", isPresented: Binding(get: { cacheError != nil }, set: { if !$0 { cacheError = nil } })) {
            Button("好", role: .cancel) { cacheError = nil }
        } message: { Text(cacheError ?? "") }
        .navigationDestination(isPresented: $reading) {
            ReaderView(book: book, store: store, addToShelf: { store.addToShelf(book) }, startChapterID: readingChapterID)
        }
        .sheet(isPresented: $showDirectory) {
            NativeChapterDirectoryView(chapters: chapters, currentChapterID: store.savedChapterId(for: book)) { chapter in
                readingChapterID = chapter.id
                showDirectory = false
                reading = true
            }
        }
        .task {
            async let detailLoad = store.mediaDetails(for: book)
            async let directoryLoad = store.directory(for: book)
            do { details = try await detailLoad }
            catch { self.error = error.localizedDescription }
            do { chapters = try await directoryLoad }
            catch { if self.error == nil { self.error = error.localizedDescription } }
            await loadComments(reset: true)
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

    private var commentSectionTitle: String {
        commentTotalCount > 0 ? "书评 · \(commentTotalCount)" : "书评"
    }

    private var previewChapters: [NativeChapter] {
        guard !chapters.isEmpty else { return [] }
        guard let current = chapters.firstIndex(where: { $0.id == store.savedChapterId(for: book) }) else { return Array(chapters.prefix(3)) }
        let lower = max(0, current - 1)
        let upper = min(chapters.count, current + 2)
        return Array(chapters[lower..<upper])
    }

    private var startReadingTitle: String {
        if let saved = store.savedChapterId(for: book), let chapter = chapters.first(where: { $0.id == saved }) {
            return "继续阅读 · \(chapter.title)"
        }
        return "开始阅读 · \(chapters[0].title)"
    }

    @MainActor private func loadComments(reset: Bool) async {
        guard !commentsLoading else { return }
        commentsLoading = true
        commentsError = nil
        defer { commentsLoading = false }
        do {
            let page = try await store.bookComments(for: book, offset: reset ? 0 : commentOffset)
            if reset { comments = page.comments } else {
                let existing = Set(comments.map(\.id))
                comments.append(contentsOf: page.comments.filter { !existing.contains($0.id) })
            }
            commentTotalCount = page.totalCount
            commentScoreCount = page.scoreCount
            commentScoreContext = page.scoreContext
            commentOffset = page.nextOffset > 0 ? page.nextOffset : comments.count
            commentsHasMore = page.hasMore && !page.comments.isEmpty
        } catch { commentsError = error.localizedDescription }
    }
}

private struct NativeBookCommentRow: View {
    let comment: NativeBookComment
    let ink: Color
    let muted: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Text(comment.userName).font(.system(size: 12, weight: .medium)).foregroundStyle(ink)
                if comment.score > 0 {
                    HStack(spacing: 2) {
                        ForEach(0..<5, id: \.self) { index in
                            let symbol = comment.score >= (index + 1) * 2 ? "star.fill" : (comment.score == index * 2 + 1 ? "star.leadinghalf.filled" : "star")
                            Image(systemName: symbol).font(.system(size: 9)).foregroundStyle(Color(red: 0.86, green: 0.58, blue: 0.21))
                        }
                    }
                }
                Spacer()
                if let date = comment.createdAt {
                    Text(relativeDate(date)).font(.system(size: 10)).foregroundStyle(muted)
                }
            }
            Text(comment.text).font(.system(size: 13)).lineSpacing(3).foregroundStyle(ink).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 12) {
                if comment.diggCount > 0 { Label("\(comment.diggCount)", systemImage: "hand.thumbsup").labelStyle(.titleAndIcon) }
                if comment.replyCount > 0 { Label("\(comment.replyCount)", systemImage: "bubble.right") }
            }.font(.system(size: 10)).foregroundStyle(muted)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func relativeDate(_ date: Date) -> String {
        let seconds = max(0, Int(Date().timeIntervalSince(date)))
        if seconds < 60 { return "刚刚" }
        if seconds < 3600 { return "\(seconds / 60)分钟前" }
        if seconds < 86400 { return "\(seconds / 3600)小时前" }
        if seconds < 86400 * 30 { return "\(seconds / 86400)天前" }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = Calendar.current.component(.year, from: date) == Calendar.current.component(.year, from: Date()) ? "MM-dd" : "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}

private struct NativeChapterDirectoryView: View {
    let chapters: [NativeChapter]
    let currentChapterID: String?
    let onSelect: (NativeChapter) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredChapters: [NativeChapter] {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return chapters }
        return chapters.filter { $0.title.localizedCaseInsensitiveContains(term) }
    }

    var body: some View {
        NavigationStack {
            List(filteredChapters) { chapter in
                Button { onSelect(chapter) } label: {
                    HStack(spacing: 10) {
                        Text(chapter.title).foregroundStyle(.primary).lineLimit(1)
                        Spacer()
                        if chapter.id == currentChapterID {
                            Text("读至").font(.caption).foregroundStyle(.secondary)
                        }
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "搜索章节")
            .navigationTitle("目录 · 共\(chapters.count)章")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } } }
            .overlay {
                if filteredChapters.isEmpty {
                    ContentUnavailableView("没有找到章节", systemImage: "text.book.closed", description: Text("尝试输入其他章节名称"))
                }
            }
        }
    }
}

private struct ReaderView: View {
    let book: NativeBook
    @ObservedObject var store: NativeReadingStore
    let addToShelf: () -> Void
    var startChapterID: String? = nil
    @Environment(\.dismiss) private var dismiss
    @State private var chapters: [NativeChapter] = []
    @State private var selectedIndex = 0
    @State private var content = ""
    @State private var restoreTextOffset = 0
    @State private var lastVisibleParagraph = 0
    @State private var positionSaveTask: Task<Void, Never>?
    @State private var error: String?
    @State private var isLoading = true
    @AppStorage("xiaoman.reader.fontSize") private var fontSize = 18.0
    @AppStorage("xiaoman.reader.lineSpacing") private var readerLineSpacing = 10.0
    @AppStorage("xiaoman.reader.paper") private var readerPaperID = "warm"
    @AppStorage("xiaoman.reader.pageMode") private var readerPageMode = "paged"
    @AppStorage("xiaoman.reader.horizontalPadding") private var readerHorizontalPadding = 24.0
    @AppStorage("xiaoman.reader.paragraphSpacing") private var readerParagraphSpacing = 12.0
    @AppStorage("xiaoman.reader.verticalPadding") private var readerVerticalPadding = 16.0
    @AppStorage("xiaoman.reader.fontWeight") private var readerFontWeightValue = 400
    @AppStorage("xiaoman.reader.letterSpacing") private var readerLetterSpacing = 0.0
    @AppStorage("xiaoman.reader.titleSize") private var readerTitleSize = 20.0
    @AppStorage("xiaoman.reader.titleAlignment") private var readerTitleAlignment = "start"
    @State private var pagedPageIndex = 0
    @State private var pagedTextOffset = 0

    private var readerPaper: Color {
        switch readerPaperID {
        case "white": Color.white
        case "eyeCare": Color(red: 0.91, green: 0.945, blue: 0.875)
        case "parchment": Color(red: 0.953, green: 0.894, blue: 0.761)
        case "night": Color(red: 0.10, green: 0.10, blue: 0.11)
        case "eink": Color.white
        default: Color(red: 0.98, green: 0.96, blue: 0.90)
        }
    }

    private var readerInk: Color {
        switch readerPaperID {
        case "night": Color(red: 0.82, green: 0.82, blue: 0.82)
        case "eyeCare": Color(red: 0.153, green: 0.192, blue: 0.157)
        case "parchment": Color(red: 0.286, green: 0.239, blue: 0.169)
        case "eink": Color.black
        default: Color(red: 0.16, green: 0.15, blue: 0.13)
        }
    }

    private var readerFontWeight: Font.Weight {
        switch readerFontWeightValue {
        case ...300: .light
        case 301...400: .regular
        case 401...500: .medium
        case 501...600: .semibold
        default: .bold
        }
    }

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
            } else if readerPageMode == "paged" {
                GeometryReader { geometry in
                    let pageWidth = max(180, min(geometry.size.width - readerHorizontalPadding * 2, 720))
                    let pageHeight = max(160, geometry.size.height - 110 - readerVerticalPadding * 2)
                    let pages = Self.paginatedPages(readerText, width: pageWidth, height: pageHeight, fontSize: fontSize, fontWeight: readerFontWeightValue, letterSpacing: readerLetterSpacing, lineSpacing: readerLineSpacing, paragraphSpacing: readerParagraphSpacing)
                    let visibleIndex = min(max(0, pagedPageIndex), max(0, pages.count - 1))
                    VStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(book.title).font(.system(size: 13, weight: .medium)).foregroundStyle(readerInk.opacity(0.65)).lineLimit(1)
                            if chapters.indices.contains(selectedIndex) {
                                Text(chapters[selectedIndex].title).font(.system(size: readerTitleSize, weight: .semibold)).foregroundStyle(readerInk).lineLimit(1)
                            }
                        }
                        .frame(width: pageWidth, height: 54, alignment: readerTitleAlignment == "center" ? .center : .leading)
                        .multilineTextAlignment(readerTitleAlignment == "center" ? .center : .leading)
                        Text(pages.isEmpty ? "" : pages[visibleIndex].text)
                            .font(.system(size: fontSize, weight: readerFontWeight, design: .serif))
                            .lineSpacing(readerLineSpacing)
                            .tracking(readerLetterSpacing)
                            .foregroundStyle(readerInk)
                            .frame(width: pageWidth, height: pageHeight, alignment: .topLeading)
                            .frame(maxWidth: .infinity)
                        HStack {
                            Button { turnPage(-1, pages: pages) } label: { Image(systemName: "chevron.left") }
                                .disabled(pagedPageIndex == 0 && selectedIndex == 0)
                            Spacer()
                            Text("\(visibleIndex + 1) / \(max(1, pages.count))").font(.system(size: 12, design: .monospaced)).foregroundStyle(readerInk.opacity(0.64))
                            Spacer()
                            Button { turnPage(1, pages: pages) } label: { Image(systemName: "chevron.right") }
                                .disabled(pagedPageIndex + 1 >= pages.count && selectedIndex + 1 >= chapters.count)
                        }
                        .buttonStyle(.plain).foregroundStyle(readerInk.opacity(0.75))
                        .frame(width: pageWidth, height: 40)
                    }
                    .padding(.horizontal, readerHorizontalPadding).padding(.vertical, readerVerticalPadding)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(DragGesture(minimumDistance: 24).onEnded { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        turnPage(value.translation.width < 0 ? 1 : -1, pages: pages)
                    })
                    .onChange(of: content) { _, _ in
                        pagedTextOffset = restoreTextOffset
                        pagedPageIndex = pageIndex(for: restoreTextOffset, in: pages)
                    }
                    .onChange(of: geometry.size) { _, _ in
                        pagedPageIndex = pageIndex(for: pagedTextOffset, in: pages)
                    }
                    .onChange(of: fontSize) { _, _ in
                        pagedPageIndex = pageIndex(for: pagedTextOffset, in: pages)
                    }
                    .onChange(of: readerLineSpacing) { _, _ in
                        pagedPageIndex = pageIndex(for: pagedTextOffset, in: pages)
                    }
                    .onChange(of: readerParagraphSpacing) { _, _ in
                        pagedPageIndex = pageIndex(for: pagedTextOffset, in: pages)
                    }
                    .onChange(of: readerHorizontalPadding) { _, _ in
                        pagedPageIndex = pageIndex(for: pagedTextOffset, in: pages)
                    }
                    .onChange(of: readerVerticalPadding) { _, _ in
                        pagedPageIndex = pageIndex(for: pagedTextOffset, in: pages)
                    }
                    .onChange(of: readerFontWeightValue) { _, _ in
                        pagedPageIndex = pageIndex(for: pagedTextOffset, in: pages)
                    }
                    .onChange(of: readerLetterSpacing) { _, _ in
                        pagedPageIndex = pageIndex(for: pagedTextOffset, in: pages)
                    }
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            Text(book.title).font(.system(size: readerTitleSize, weight: .semibold)).foregroundStyle(readerInk).multilineTextAlignment(readerTitleAlignment == "center" ? .center : .leading).padding(.bottom, 18)
                            if !chapters.isEmpty { Text(chapters[selectedIndex].title).font(.subheadline).foregroundStyle(readerInk.opacity(0.7)).multilineTextAlignment(readerTitleAlignment == "center" ? .center : .leading).padding(.bottom, 16) }
                            ForEach(Array(readerParagraphs.enumerated()), id: \.offset) { index, paragraph in
                                Text(paragraph)
                                    .font(.system(size: fontSize, weight: readerFontWeight, design: .serif))
                                    .lineSpacing(readerLineSpacing)
                                    .tracking(readerLetterSpacing)
                                    .foregroundStyle(readerInk)
                                    .textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.bottom, readerParagraphSpacing)
                                    .background {
                                        GeometryReader { geometry in
                                            Color.clear.preference(key: ReaderParagraphFramesKey.self, value: [index: geometry.frame(in: .named("readerScroll")).minY])
                                        }
                                    }
                                    .id(index)
                            }
                        }
                        .frame(maxWidth: 720, alignment: .leading)
                        .padding(.horizontal, readerHorizontalPadding).padding(.vertical, readerVerticalPadding)
                        .frame(maxWidth: .infinity)
                    }
                    .coordinateSpace(name: "readerScroll")
                    .onPreferenceChange(ReaderParagraphFramesKey.self) { frames in
                        guard !frames.isEmpty else { return }
                        let aboveOrAtTop = frames.filter { $0.value <= 120 }
                        let visible = aboveOrAtTop.max(by: { $0.value < $1.value })?.key ?? frames.min(by: { $0.value < $1.value })?.key ?? 0
                        lastVisibleParagraph = visible
                        schedulePositionSave(paragraphIndex: visible)
                    }
                    .task(id: "\(selectedIndex)-\(content.count)") {
                        guard !readerParagraphs.isEmpty else { return }
                        let target = paragraphIndex(forTextOffset: restoreTextOffset)
                        lastVisibleParagraph = target
                        try? await Task.sleep(for: .milliseconds(60))
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }
        }
        .background(readerPaper.ignoresSafeArea())
        .toolbar {
            ToolbarItem(placement: .automatic) { Button("完成") { dismiss() } }
            ToolbarItem(placement: .automatic) { Button("加入书架", systemImage: "books.vertical") { addToShelf() } }
            ToolbarItem(placement: .automatic) {
                Menu {
                    Picker("翻页模式", selection: $readerPageMode) {
                        Text("分页阅读").tag("paged")
                        Text("滚动阅读").tag("scroll")
                    }
                    Section("字号 · \(Int(fontSize))") { Slider(value: $fontSize, in: 16...32, step: 1) }
                    Section("行距 · \(Int(readerLineSpacing))") { Slider(value: $readerLineSpacing, in: 4...24, step: 1) }
                    Section("段间距 · \(Int(readerParagraphSpacing))") { Slider(value: $readerParagraphSpacing, in: 0...32, step: 1) }
                    Section("左右边距 · \(Int(readerHorizontalPadding))") { Slider(value: $readerHorizontalPadding, in: 12...40, step: 1) }
                    Section("上下边距 · \(Int(readerVerticalPadding))") { Slider(value: $readerVerticalPadding, in: 0...48, step: 1) }
                    Section("字距 · \(readerLetterSpacing, specifier: "%.1f")") { Slider(value: $readerLetterSpacing, in: -0.5...3, step: 0.1) }
                    Picker("字重", selection: $readerFontWeightValue) {
                        Text("细").tag(300); Text("标准").tag(400); Text("适中").tag(500); Text("偏粗").tag(600); Text("粗").tag(700)
                    }
                    Picker("标题对齐", selection: $readerTitleAlignment) {
                        Text("居左").tag("start"); Text("居中").tag("center")
                    }
                    Section("阅读底色") {
                        Picker("阅读底色", selection: $readerPaperID) {
                            Text("米白").tag("warm")
                            Text("纯白").tag("white")
                            Text("青绿").tag("eyeCare")
                            Text("纸张").tag("parchment")
                            Text("夜间").tag("night")
                            Text("墨水屏").tag("eink")
                        }
                    }
                } label: { Image(systemName: "textformat.size") }
            }
        }
        .onAppear { store.beginReadingSession() }
        .onDisappear {
            positionSaveTask?.cancel()
            savePosition(paragraphIndex: lastVisibleParagraph)
            store.endReadingSession()
        }
        .task { await loadDirectory() }
    }

    private func loadDirectory() async {
        do {
            chapters = try await store.directory(for: book)
            guard !chapters.isEmpty else { throw ReaderError.emptyDirectory }
            let savedId = startChapterID ?? store.savedChapterId(for: book)
            let resumeIndex = chapters.firstIndex(where: { $0.id == savedId }) ?? 0
            await openChapter(resumeIndex)
        } catch { self.error = error.localizedDescription; isLoading = false }
    }

    private func openChapter(_ index: Int) async {
        guard chapters.indices.contains(index) else { return }
        positionSaveTask?.cancel()
        if !content.isEmpty { savePosition(paragraphIndex: lastVisibleParagraph) }
        isLoading = true
        error = nil
        do {
            let chapter = chapters[index]
            let savedOffset = store.savedTextOffset(for: book, chapter: chapter)
            content = try await store.content(for: chapter, book: book)
            selectedIndex = index
            restoreTextOffset = savedOffset
            pagedTextOffset = savedOffset
            pagedPageIndex = 0
            lastVisibleParagraph = 0
            store.recordProgress(for: book, chapter: chapter, progress: Double(index + 1) / Double(chapters.count))
        } catch { self.error = error.localizedDescription }
        isLoading = false
    }

    private var readerText: String {
        store.applyTextReplacements(to: formattedContent(content))
    }

    private var readerParagraphs: [String] {
        readerText.components(separatedBy: "\n")
    }

    private func paragraphStartOffset(_ paragraphIndex: Int) -> Int {
        readerParagraphs.prefix(max(0, paragraphIndex)).reduce(0) { $0 + $1.utf16.count + 1 }
    }

    private func paragraphIndex(forTextOffset offset: Int) -> Int {
        var consumed = 0
        for (index, paragraph) in readerParagraphs.enumerated() {
            if offset < consumed + paragraph.utf16.count + 1 { return index }
            consumed += paragraph.utf16.count + 1
        }
        return max(0, readerParagraphs.count - 1)
    }

    private func schedulePositionSave(paragraphIndex: Int) {
        positionSaveTask?.cancel()
        positionSaveTask = Task {
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            savePosition(paragraphIndex: paragraphIndex)
        }
    }

    private func savePosition(paragraphIndex: Int) {
        guard chapters.indices.contains(selectedIndex) else { return }
        let offset = readerPageMode == "paged" ? pagedTextOffset : paragraphStartOffset(paragraphIndex)
        store.recordTextPosition(for: book, chapter: chapters[selectedIndex], chapterIndex: selectedIndex, chapterCount: chapters.count, textOffset: offset, textLength: readerText.utf16.count)
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

    private func turnPage(_ direction: Int, pages: [(range: NSRange, text: String)]) {
        guard !pages.isEmpty else { return }
        if direction > 0 {
            if pagedPageIndex + 1 < pages.count {
                pagedPageIndex += 1
            } else if selectedIndex + 1 < chapters.count {
                Task { await openChapter(selectedIndex + 1) }
                return
            }
        } else if pagedPageIndex > 0 {
            pagedPageIndex -= 1
        } else if selectedIndex > 0 {
            Task { await openChapter(selectedIndex - 1) }
            return
        }
        let index = min(max(0, pagedPageIndex), pages.count - 1)
        pagedTextOffset = pages[index].range.location
        if chapters.indices.contains(selectedIndex) {
            store.recordTextPosition(for: book, chapter: chapters[selectedIndex], chapterIndex: selectedIndex, chapterCount: chapters.count, textOffset: pagedTextOffset, textLength: readerText.utf16.count)
        }
    }

    private func pageIndex(for offset: Int, in pages: [(range: NSRange, text: String)]) -> Int {
        pages.firstIndex(where: { NSLocationInRange(offset, $0.range) }) ?? max(0, pages.count - 1)
    }

    private static func paginatedPages(_ text: String, width: CGFloat, height: CGFloat, fontSize: Double, fontWeight: Int, letterSpacing: Double, lineSpacing: Double, paragraphSpacing: Double) -> [(range: NSRange, text: String)] {
        let source = text as NSString
        guard source.length > 0 else { return [(NSRange(location: 0, length: 0), "")] }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = lineSpacing
        paragraph.paragraphSpacing = paragraphSpacing
        paragraph.lineBreakMode = .byWordWrapping
        let regularFont = CTFontCreateWithName("Songti SC" as CFString, CGFloat(fontSize), nil)
        let font = fontWeight >= 600 ? (CTFontCreateCopyWithSymbolicTraits(regularFont, CGFloat(fontSize), nil, .boldTrait, .boldTrait) ?? regularFont) : regularFont
        let attributed = NSAttributedString(string: text, attributes: [.font: font, .paragraphStyle: paragraph, .kern: letterSpacing])
        let framesetter = CTFramesetterCreateWithAttributedString(attributed)
        var result: [(range: NSRange, text: String)] = []
        var offset = 0
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: width, height: height), transform: nil)
        while offset < source.length {
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: offset, length: 0), path, nil)
            let visible = CTFrameGetVisibleStringRange(frame)
            guard visible.length > 0 else { break }
            let range = NSRange(location: offset, length: Int(visible.length))
            result.append((range, source.substring(with: range)))
            offset = NSMaxRange(range)
        }
        if result.isEmpty { return [(NSRange(location: 0, length: source.length), text)] }
        return result
    }
}

private struct ReaderParagraphFramesKey: PreferenceKey {
    static var defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private enum ReaderError: LocalizedError {
    case emptyDirectory
    var errorDescription: String? { "作品目录没有返回可读章节" }
}

private struct SettingsView: View {
    @ObservedObject var store: NativeReadingStore
    let onReadOffline: (NativeBook) -> Void
    @State private var selectedEntry: String?
    private let entries: [(String, String, String)] = [
        ("统计", "chart.bar", "阅读记录、藏书与阅读时长"),
        ("设置", "gearshape", "阅读、外观、播放与本地数据"),
        ("正文替换", "text.badge.star", "自定义普通文本或正则替换规则"),
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
                    } else if route.title == "离线缓存" {
                        OfflineCacheView(store: store, onRead: onReadOffline)
                    } else if route.title == "设置" {
                        NativeReadingPreferencesView()
                    } else if route.title == "正文替换" {
                        NativeTextReplacementView(store: store)
                    } else if route.title == "备份与导入" {
                        NativeLibraryBackupView(store: store)
                    } else if route.title == "关于" {
                        List {
                            LabeledContent("应用名称", value: "小满阅读")
                            LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.1.0")
                            LabeledContent("构建", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1")
                            Text("原生 iOS 与 macOS 阅读客户端，内容由 fqapp 本地服务提供。")
                                .font(.footnote).foregroundStyle(.secondary)
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

private struct NativeTextReplacementView: View {
    @ObservedObject var store: NativeReadingStore
    @State private var editingRule: NativeTextReplacementRule?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                Toggle("启用正文替换", isOn: Binding(get: { store.textReplacementEnabled }, set: { save(enabled: $0, rules: store.textReplacementRules) }))
            } footer: {
                Text("替换仅作用于阅读器显示，不会修改服务端原文或离线缓存。最多保存 50 条规则。")
            }
            Section("替换规则") {
                if store.textReplacementRules.isEmpty {
                    ContentUnavailableView("还没有替换规则", systemImage: "text.badge.star", description: Text("添加普通文本或正则表达式规则。"))
                }
                ForEach(store.textReplacementRules) { rule in
                    HStack(spacing: 10) {
                        Toggle(isOn: Binding(get: { rule.enabled }, set: { value in
                            var rules = store.textReplacementRules
                            guard let index = rules.firstIndex(where: { $0.id == rule.id }) else { return }
                            rules[index].enabled = value
                            save(enabled: store.textReplacementEnabled, rules: rules)
                        })) { EmptyView() }
                            .labelsHidden()
                        Button { editingRule = rule } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(rule.pattern).font(.system(.body, design: .monospaced)).lineLimit(1).foregroundStyle(.primary)
                                Text("替换为：\(rule.replacement.isEmpty ? "（删除匹配文本）" : rule.replacement) · \(rule.isRegex ? "正则" : "普通文本")")
                                    .font(.caption).lineLimit(1).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain)
                        Spacer(minLength: 0)
                    }
                    .swipeActions {
                        Button("删除", systemImage: "trash", role: .destructive) {
                            save(enabled: store.textReplacementEnabled, rules: store.textReplacementRules.filter { $0.id != rule.id })
                        }
                        Button("编辑", systemImage: "pencil") { editingRule = rule }.tint(.blue)
                    }
                }
                Button { editingRule = NativeTextReplacementRule() } label: { Label("添加替换规则", systemImage: "plus") }
                    .disabled(store.textReplacementRules.count >= 50)
            }
        }
        .navigationTitle("正文替换")
        .sheet(item: $editingRule) { rule in
            NativeTextReplacementEditor(rule: rule) { updated in
                var rules = store.textReplacementRules
                if let index = rules.firstIndex(where: { $0.id == updated.id }) { rules[index] = updated }
                else { rules.append(updated) }
                save(enabled: store.textReplacementEnabled, rules: rules)
            }
        }
        .alert("未能保存规则", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
            Button("好", role: .cancel) { errorMessage = nil }
        } message: { Text(errorMessage ?? "") }
    }

    private func save(enabled: Bool, rules: [NativeTextReplacementRule]) {
        do { try store.saveTextReplacements(enabled: enabled, rules: rules) }
        catch { errorMessage = error.localizedDescription }
    }
}

private struct NativeTextReplacementEditor: View {
    let rule: NativeTextReplacementRule
    let onSave: (NativeTextReplacementRule) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var pattern: String
    @State private var replacement: String
    @State private var isRegex: Bool
    @State private var enabled: Bool
    @State private var errorMessage: String?

    init(rule: NativeTextReplacementRule, onSave: @escaping (NativeTextReplacementRule) -> Void) {
        self.rule = rule
        self.onSave = onSave
        _pattern = State(initialValue: rule.pattern)
        _replacement = State(initialValue: rule.replacement)
        _isRegex = State(initialValue: rule.isRegex)
        _enabled = State(initialValue: rule.enabled)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("匹配") {
                    TextField(isRegex ? "正则表达式" : "要查找的文本", text: $pattern)
                    if isRegex { Text("支持 NSRegularExpression 语法，例如 `\\s+`。") .font(.footnote).foregroundStyle(.secondary) }
                    TextField("替换为（留空表示删除）", text: $replacement)
                    Toggle("正则表达式", isOn: $isRegex)
                    Toggle("启用此规则", isOn: $enabled)
                }
                Section {
                    Text("按列表顺序依次应用。匹配内容和替换内容最多 2048 字，替换内容不能包含换行。")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle(rule.pattern.isEmpty ? "添加规则" : "编辑规则")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("取消") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("保存") { save() } }
            }
            .alert("规则无效", isPresented: Binding(get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } })) {
                Button("好", role: .cancel) { errorMessage = nil }
            } message: { Text(errorMessage ?? "") }
        }
    }

    private func save() {
        guard !pattern.isEmpty else { errorMessage = "匹配内容不能为空。"; return }
        guard pattern.count <= 2048, replacement.count <= 2048 else { errorMessage = "匹配内容和替换内容不能超过 2048 字。"; return }
        guard !replacement.contains(where: { $0.isNewline }) else { errorMessage = "替换内容不能包含换行。"; return }
        if isRegex, (try? NSRegularExpression(pattern: pattern)) == nil { errorMessage = "正则表达式无效。"; return }
        var updated = rule
        updated.pattern = pattern
        updated.replacement = replacement
        updated.isRegex = isRegex
        updated.enabled = enabled
        onSave(updated)
        dismiss()
    }
}

private struct NativeReadingPreferencesView: View {
    @AppStorage("xiaoman.reader.fontSize") private var fontSize = 18.0
    @AppStorage("xiaoman.reader.lineSpacing") private var lineSpacing = 10.0
    @AppStorage("xiaoman.reader.paper") private var paper = "warm"
    @AppStorage("xiaoman.reader.horizontalPadding") private var horizontalPadding = 24.0
    @AppStorage("xiaoman.reader.paragraphSpacing") private var paragraphSpacing = 12.0
    @AppStorage("xiaoman.reader.verticalPadding") private var verticalPadding = 16.0
    @AppStorage("xiaoman.reader.fontWeight") private var fontWeight = 400
    @AppStorage("xiaoman.reader.letterSpacing") private var letterSpacing = 0.0
    @AppStorage("xiaoman.reader.titleSize") private var titleSize = 20.0
    @AppStorage("xiaoman.reader.titleAlignment") private var titleAlignment = "start"

    var body: some View {
        Form {
            Section("阅读排版") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("正文字号"); Spacer(); Text("\(Int(fontSize)) pt").foregroundStyle(.secondary) }
                    Slider(value: $fontSize, in: 16...32, step: 1)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("段落行距"); Spacer(); Text("\(Int(lineSpacing)) pt").foregroundStyle(.secondary) }
                    Slider(value: $lineSpacing, in: 4...24, step: 1)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("段间距"); Spacer(); Text("\(Int(paragraphSpacing)) pt").foregroundStyle(.secondary) }
                    Slider(value: $paragraphSpacing, in: 0...32, step: 1)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("左右边距"); Spacer(); Text("\(Int(horizontalPadding)) pt").foregroundStyle(.secondary) }
                    Slider(value: $horizontalPadding, in: 12...40, step: 1)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("上下边距"); Spacer(); Text("\(Int(verticalPadding)) pt").foregroundStyle(.secondary) }
                    Slider(value: $verticalPadding, in: 0...48, step: 1)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("字距"); Spacer(); Text(String(format: "%.1f pt", letterSpacing)).foregroundStyle(.secondary) }
                    Slider(value: $letterSpacing, in: -0.5...3, step: 0.1)
                }
                Picker("字重", selection: $fontWeight) {
                    Text("细").tag(300); Text("标准").tag(400); Text("适中").tag(500); Text("偏粗").tag(600); Text("粗").tag(700)
                }
                VStack(alignment: .leading, spacing: 8) {
                    HStack { Text("标题字号"); Spacer(); Text("\(Int(titleSize)) pt").foregroundStyle(.secondary) }
                    Slider(value: $titleSize, in: 16...40, step: 1)
                }
                Picker("标题对齐", selection: $titleAlignment) {
                    Text("居左").tag("start"); Text("居中").tag("center")
                }
                Picker("阅读底色", selection: $paper) {
                    Text("米白").tag("warm")
                    Text("纯白").tag("white")
                    Text("青绿").tag("eyeCare")
                    Text("纸张").tag("parchment")
                    Text("夜间").tag("night")
                    Text("墨水屏").tag("eink")
                }
            }
            Section {
                Text("阅读器中也可随时调整这些选项，设置会自动保存到本机。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

private struct OfflineCacheView: View {
    @ObservedObject var store: NativeReadingStore
    let onRead: (NativeBook) -> Void
    @State private var confirmClear: NativeBook?

    var body: some View {
        Group {
            if store.offlineBooks.isEmpty {
                ContentUnavailableView("还没有离线内容", systemImage: "arrow.down.to.line", description: Text("在小说详情页选择“下载到离线”，缓存后可在无网络时继续阅读。"))
            } else {
                List {
                    ForEach(store.offlineBooks) { book in
                        HStack(spacing: 12) {
                            Button { onRead(book) } label: {
                                HStack(spacing: 12) {
                                    NativeCoverPlaceholder(item: book).frame(width: 48, height: 68).clipShape(RoundedRectangle(cornerRadius: 6))
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(book.title).font(.body.weight(.semibold)).lineLimit(2)
                                        Text("\(store.cachedChapterCount(for: book)) 章 · \(ByteCountFormatter.string(fromByteCount: store.offlineCacheSize(for: book), countStyle: .file))")
                                            .font(.caption).foregroundStyle(.secondary)
                                        if let progress = store.offlineCacheProgress[book.id] {
                                            ProgressView(value: progress).tint(Color(red: 0.94, green: 0.31, blue: 0.22))
                                        } else {
                                            Text("点按继续阅读").font(.caption2).foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 4)
                                }
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            Button(role: .destructive) { confirmClear = book } label: {
                                Image(systemName: "trash").frame(width: 36, height: 44)
                            }
                            .buttonStyle(.borderless)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .confirmationDialog("删除这本书的离线内容？", isPresented: Binding(get: { confirmClear != nil }, set: { if !$0 { confirmClear = nil } }), titleVisibility: .visible) {
            Button("删除离线内容", role: .destructive) {
                if let book = confirmClear { store.removeOfflineCache(for: book) }
                confirmClear = nil
            }
        }
    }
}

private struct SettingsRoute: Identifiable {
    let title: String
    var id: String { title }
}
