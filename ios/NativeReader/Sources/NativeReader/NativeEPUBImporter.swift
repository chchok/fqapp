import Foundation

struct NativeImportedTextChapter {
    let title: String
    let text: String
}

struct NativeImportedBookDocument {
    let title: String
    let author: String
    let chapters: [NativeImportedTextChapter]
    let cover: Data?
    let coverExtension: String?
}

enum NativeEPUBImporter {
    static func parse(_ data: Data, fallbackTitle: String) throws -> NativeImportedBookDocument {
        guard data.count <= 32 * 1024 * 1024 else { throw NativeClientError.message("请选择小于 32 MB 的 EPUB 文件") }
        let archive = try NativeZIPArchive(data: data)
        guard let container = archive.entries["META-INF/container.xml"] else {
            throw NativeClientError.message("EPUB 缺少 META-INF/container.xml")
        }
        let containerXML = try NativeXMLDocument(data: archive.extract(container), kind: .container)
        guard let packagePath = containerXML.rootfile, !packagePath.isEmpty else {
            throw NativeClientError.message("EPUB 目录文件无效")
        }
        let normalizedPackagePath = Self.resolve(path: packagePath, relativeTo: "")
        guard let packageEntry = archive.entries[normalizedPackagePath] else {
            throw NativeClientError.message("EPUB 目录文件不存在")
        }
        let package = try NativeXMLDocument(data: archive.extract(packageEntry), kind: .package)
        let base = (normalizedPackagePath as NSString).deletingLastPathComponent
        var chapters: [NativeImportedTextChapter] = []
        for id in package.spine {
            guard let item = package.manifest[id], item.mediaType.contains("html") || item.mediaType.contains("xhtml") else { continue }
            if item.properties.split(whereSeparator: \.isWhitespace).contains("nav") { continue }
            let path = Self.resolve(path: item.href, relativeTo: base)
            guard let entry = archive.entries[path] else { continue }
            let document = try NativeXMLDocument(data: archive.extract(entry), kind: .chapter)
            let text = Self.normalize(document.bodyText)
            guard !text.isEmpty else { continue }
            let title = Self.normalize(document.chapterTitle)
            if !title.isEmpty && text.filter({ !$0.isWhitespace }) == title.filter({ !$0.isWhitespace }) { continue }
            chapters.append(NativeImportedTextChapter(title: title.isEmpty ? "第\(chapters.count + 1)章" : title, text: text))
            guard chapters.count <= 20_000 else { throw NativeClientError.message("EPUB 章节数量超过支持上限") }
        }
        guard !chapters.isEmpty else { throw NativeClientError.message("EPUB 中没有可阅读的章节") }
        let cover = Self.extractCover(package: package, archive: archive, base: base)
        return NativeImportedBookDocument(title: package.title.isEmpty ? fallbackTitle : package.title, author: package.author, chapters: chapters, cover: cover?.0, coverExtension: cover?.1)
    }

    private static func extractCover(package: NativeXMLDocument, archive: NativeZIPArchive, base: String) -> (Data, String)? {
        func candidate(_ raw: String?) -> String? {
            guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty else { return nil }
            let reference = value.hasPrefix("#") ? String(value.dropFirst()) : value
            if let item = package.manifest[reference] {
                let path = resolve(path: item.href, relativeTo: base)
                if archive.entries[path] != nil { return path }
            }
            if value.hasPrefix("#") { return nil }
            for path in [resolve(path: value, relativeTo: ""), resolve(path: value, relativeTo: base)] where archive.entries[path] != nil { return path }
            return nil
        }
        var selected: String?
        selected = package.manifest.first(where: { $0.value.properties.split(whereSeparator: \.isWhitespace).contains("cover-image") }).flatMap { candidate($0.value.href) }
        if selected == nil {
            for meta in package.metadata where meta["property"]?.lowercased() == "cover-image" {
                selected = candidate(meta["refines"]) ?? candidate(meta["text"]) ?? candidate(meta["content"])
                if selected != nil { break }
            }
        }
        if selected == nil, let legacy = package.metadata.first(where: { $0["name"]?.lowercased() == "cover" }) {
            selected = candidate(legacy["content"])
        }
        if selected == nil, let guide = package.guideReferences.first(where: { $0["type"]?.lowercased() == "cover" }) {
            selected = candidate(guide["href"])
        }
        if selected == nil {
            selected = package.manifest.first(where: { entry in
                let hint = entry.key.range(of: #"(?:^|[/_.~\\-])(cover|frontcover|titlepage|title-page)(?:$|[/_.~\\-])"#, options: .regularExpression) != nil || entry.value.href.range(of: #"(?:^|[/_.~\\-])(cover|frontcover|titlepage|title-page)(?:$|[/_.~\\-])"#, options: .regularExpression) != nil
                return hint && entry.value.mediaType.lowercased().hasPrefix("image/")
            }).flatMap { candidate($0.value.href) }
        }
        guard let path = selected, let entry = archive.entries[path], entry.uncompressedSize > 0, entry.uncompressedSize <= 8 * 1024 * 1024 else { return nil }
        do {
            let data = try archive.extract(entry)
            if data.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return (data, "png") }
            if data.starts(with: [0xFF, 0xD8, 0xFF]) { return (data, "jpg") }
            if data.starts(with: [0x47, 0x49, 0x46, 0x38]) { return (data, "gif") }
            if data.starts(with: [0x52, 0x49, 0x46, 0x46]), data.count >= 12, data[8..<12].elementsEqual([0x57, 0x45, 0x42, 0x50]) { return (data, "webp") }
        } catch { return nil }
        return nil
    }

    private static func resolve(path: String, relativeTo base: String) -> String {
        let withoutSuffix = path.split(whereSeparator: { $0 == "#" || $0 == "?" }).first.map(String.init) ?? ""
        guard !withoutSuffix.hasPrefix("/"), !withoutSuffix.contains("\\") else { return "" }
        let decoded = withoutSuffix.removingPercentEncoding ?? withoutSuffix
        var parts = base.split(separator: "/").map(String.init)
        for part in decoded.split(separator: "/").map(String.init) {
            switch part {
            case "", ".": continue
            case "..": if parts.isEmpty { return "" }; parts.removeLast()
            default: parts.append(part)
            }
        }
        return parts.joined(separator: "/")
    }

    private static func normalize(_ text: String) -> String {
        text.replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: .newlines)
            .map { $0.split(whereSeparator: \.isWhitespace).joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct NativeZIPEntry {
    let name: String
    let method: UInt16
    let flags: UInt16
    let crc32: UInt32
    let compressedSize: UInt32
    let uncompressedSize: UInt32
    let localHeaderOffset: UInt32
}

private struct NativeZIPArchive {
    let data: Data
    let entries: [String: NativeZIPEntry]

    init(data: Data) throws {
        self.data = data
        entries = try Self.readEntries(data)
    }

    func extract(_ entry: NativeZIPEntry) throws -> Data {
        guard entry.flags & 0x1 == 0 else { throw NativeClientError.message("EPUB 使用了加密压缩，无法导入") }
        let local = Int(entry.localHeaderOffset)
        guard Self.u32(data, local) == 0x04034B50, local + 30 <= data.count else { throw NativeClientError.message("EPUB 压缩目录损坏") }
        let nameLength = Int(Self.u16(data, local + 26))
        let extraLength = Int(Self.u16(data, local + 28))
        let payload = local + 30 + nameLength + extraLength
        let compressedLength = Int(entry.compressedSize)
        let outputLength = Int(entry.uncompressedSize)
        guard payload >= local, compressedLength <= data.count - min(payload, data.count), payload <= data.count else {
            throw NativeClientError.message("EPUB 文件内容超出边界")
        }
        let compressed = data.subdata(in: payload..<(payload + compressedLength))
        var output = Data(count: outputLength)
        let result = compressed.withUnsafeBytes { source in
            output.withUnsafeMutableBytes { destination in
                fq_native_inflate_zip_data(
                    Int32(entry.method),
                    source.bindMemory(to: UInt8.self).baseAddress,
                    compressed.count,
                    destination.bindMemory(to: UInt8.self).baseAddress,
                    outputLength,
                    entry.crc32
                )
            }
        }
        guard result == 0 else { throw NativeClientError.message("EPUB 内容解压失败（\(entry.name)）") }
        return output
    }

    private static func readEntries(_ data: Data) throws -> [String: NativeZIPEntry] {
        guard data.count >= 22 else { throw NativeClientError.message("EPUB 文件格式无效") }
        let minimum = max(0, data.count - 65_557)
        var endRecord: Int?
        for offset in stride(from: data.count - 22, through: minimum, by: -1) where u32(data, offset) == 0x06054B50 {
            let commentLength = Int(u16(data, offset + 20))
            if offset + 22 + commentLength == data.count { endRecord = offset; break }
        }
        guard let eocd = endRecord,
              u16(data, eocd + 4) == 0,
              u16(data, eocd + 6) == 0,
              u16(data, eocd + 8) == u16(data, eocd + 10) else {
            throw NativeClientError.message("EPUB 压缩目录无效或不受支持")
        }
        let count = Int(u16(data, eocd + 10))
        let directorySize = Int(u32(data, eocd + 12))
        let directoryOffset = Int(u32(data, eocd + 16))
        guard count <= 4_000, directoryOffset <= data.count, directorySize <= data.count - directoryOffset,
              directoryOffset + directorySize <= eocd else { throw NativeClientError.message("EPUB 文件条目过多或目录损坏") }
        var result: [String: NativeZIPEntry] = [:]
        var cursor = directoryOffset
        var expandedTotal: UInt64 = 0
        for _ in 0..<count {
            guard cursor + 46 <= directoryOffset + directorySize, u32(data, cursor) == 0x02014B50 else {
                throw NativeClientError.message("EPUB 中央目录损坏")
            }
            let flags = u16(data, cursor + 8)
            let method = u16(data, cursor + 10)
            let crc = u32(data, cursor + 16)
            let compressed = u32(data, cursor + 20)
            let uncompressed = u32(data, cursor + 24)
            let nameLength = Int(u16(data, cursor + 28))
            let extraLength = Int(u16(data, cursor + 30))
            let commentLength = Int(u16(data, cursor + 32))
            let localOffset = u32(data, cursor + 42)
            let nameStart = cursor + 46
            let next = nameStart + nameLength + extraLength + commentLength
            guard next <= directoryOffset + directorySize else { throw NativeClientError.message("EPUB 条目损坏") }
            let nameData = data.subdata(in: nameStart..<(nameStart + nameLength))
            guard let name = String(data: nameData, encoding: .utf8), !name.hasPrefix("/"), !name.contains("\\") else {
                throw NativeClientError.message("EPUB 中包含无效路径")
            }
            if !name.hasSuffix("/") {
                guard flags & 0x1 == 0, method == 0 || method == 8 else { throw NativeClientError.message("EPUB 包含加密或不支持的压缩格式") }
                expandedTotal += UInt64(uncompressed)
                guard expandedTotal <= 64 * 1024 * 1024 else { throw NativeClientError.message("EPUB 解压后超过 64 MB 限制") }
                result[name] = NativeZIPEntry(name: name, method: method, flags: flags, crc32: crc, compressedSize: compressed, uncompressedSize: uncompressed, localHeaderOffset: localOffset)
            }
            cursor = next
        }
        guard cursor == directoryOffset + directorySize else { throw NativeClientError.message("EPUB 中央目录大小不匹配") }
        return result
    }

    private static func u16(_ data: Data, _ offset: Int) -> UInt16 {
        guard offset >= 0, offset + 2 <= data.count else { return 0 }
        return UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
    }

    private static func u32(_ data: Data, _ offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= data.count else { return 0 }
        return UInt32(data[offset]) | (UInt32(data[offset + 1]) << 8) | (UInt32(data[offset + 2]) << 16) | (UInt32(data[offset + 3]) << 24)
    }
}

private struct NativeEPUBManifestItem {
    let href: String
    let mediaType: String
    let properties: String
}

private final class NativeXMLDocument: NSObject, XMLParserDelegate {
    enum Kind { case container, package, chapter }
    let kind: Kind
    var rootfile: String?
    var title = ""
    var author = ""
    var manifest: [String: NativeEPUBManifestItem] = [:]
    var spine: [String] = []
    var metadata: [[String: String]] = []
    var guideReferences: [[String: String]] = []
    var bodyText = ""
    var chapterTitle = ""
    private var stack: [String] = []
    private var capture: String?
    private var captureDepth = 0
    private var captureText = ""
    private var inBody = false
    private var ignoredDepth = 0
    private var headingTag: String?
    private var headingDepth = 0
    private var headingText = ""

    init(data: Data, kind: Kind) throws {
        self.kind = kind
        super.init()
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.shouldResolveExternalEntities = false
        guard parser.parse() else { throw NativeClientError.message("EPUB XML 无法解析：\(parser.parserError?.localizedDescription ?? "格式错误")") }
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let name = Self.localName(elementName)
        stack.append(name)
        switch kind {
        case .container:
            if name == "rootfile", rootfile == nil { rootfile = attributeDict["full-path"] }
        case .package:
            if name == "item", let id = attributeDict["id"], let href = attributeDict["href"] {
                manifest[id] = NativeEPUBManifestItem(href: href, mediaType: attributeDict["media-type"] ?? "", properties: attributeDict["properties"] ?? "")
            } else if name == "meta" {
                metadata.append(attributeDict)
            } else if name == "itemref", let id = attributeDict["idref"] {
                spine.append(id)
            } else if name == "reference" {
                guideReferences.append(attributeDict)
            } else if (name == "title" || name == "creator") && capture == nil {
                capture = name; captureDepth = stack.count; captureText = ""
            }
        case .chapter:
            if name == "body" { inBody = true }
            if inBody, ["script", "style", "nav"].contains(name) { ignoredDepth += 1 }
            if inBody, ignoredDepth == 0 {
                if ["p", "div", "br", "section", "article", "li", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6"].contains(name) { bodyText.append("\n") }
                if headingTag == nil, ["h1", "h2", "h3", "h4", "h5", "h6"].contains(name) { headingTag = name; headingDepth = stack.count; headingText = "" }
            }
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capture != nil { captureText.append(string) }
        if kind == .chapter, inBody, ignoredDepth == 0 {
            bodyText.append(string)
            if headingTag != nil { headingText.append(string) }
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        if let value = String(data: CDATABlock, encoding: .utf8) { self.parser(parser, foundCharacters: value) }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = Self.localName(elementName)
        if kind == .chapter, inBody, ignoredDepth == 0 {
            if name == headingTag, stack.count == headingDepth {
                chapterTitle = headingText
                headingTag = nil
            }
            if ["p", "div", "br", "section", "article", "li", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6"].contains(name) { bodyText.append("\n") }
        }
        if capture == name, stack.count == captureDepth {
            if kind == .package {
                if name == "title", title.isEmpty { title = captureText }
                if name == "creator", author.isEmpty { author = captureText }
            }
            capture = nil; captureText = ""
        }
        if kind == .chapter, inBody, ["script", "style", "nav"].contains(name), ignoredDepth > 0 { ignoredDepth -= 1 }
        if name == "body" { inBody = false }
        if !stack.isEmpty { stack.removeLast() }
    }

    private static func localName(_ name: String) -> String { name.split(separator: ":").last.map(String.init) ?? name }
}
