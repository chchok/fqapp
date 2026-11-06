import SwiftUI
import UniformTypeIdentifiers

private struct NativeLibraryBackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data = Data()) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

struct NativeLibraryBackupView: View {
    @ObservedObject var store: NativeReadingStore
    @State private var exporting = false
    @State private var importing = false
    @State private var document = NativeLibraryBackupDocument()
    @State private var defaultFilename = "fqapp-backup.json"
    @State private var preview: NativeLibraryBackupPreview?
    @State private var pendingRestore: Data?
    @State private var message: String?
    @State private var isError = false

    var body: some View {
        Form {
            Section("本机数据") {
                Button(action: exportBackup) {
                    Label("导出备份", systemImage: "square.and.arrow.up")
                }
                Button { importing = true } label: {
                    Label("从备份文件恢复", systemImage: "square.and.arrow.down")
                }
                .fileImporter(isPresented: $importing, allowedContentTypes: [.json], allowsMultipleSelection: false, onCompletion: importBackup)
            }

            if let preview {
                Section("恢复预览") {
                    LabeledContent("备份时间", value: preview.createdAt.formatted(date: .numeric, time: .shortened))
                    LabeledContent("收藏", value: "\(preview.shelfCount) 条")
                    LabeledContent("阅读进度", value: "\(preview.historyCount) 条")
                    LabeledContent("已看剧集", value: "\(preview.episodeCount) 集")
                    if preview.excludedLocalRecords > 0 {
                        Text("备份排除了 \(preview.excludedLocalRecords) 条本地书籍记录。")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    Button("合并恢复到本机", systemImage: "arrow.triangle.merge", action: restoreBackup)
                        .tint(Color(red: 0.94, green: 0.31, blue: 0.22))
                }
            }

            if let message {
                Section { Text(message).font(.footnote).foregroundStyle(isError ? .red : .secondary) }
            }

            Section("备份范围") {
                Text("兼容 FQApp 的 fqapp.library-backup v1。包含在线收藏、小说阅读进度和已看剧集；本地文件、下载缓存、阅读时长与应用设置不会写入备份。恢复只补充缺失记录，不覆盖本机已有项目。")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: defaultFilename, onCompletion: exportCompleted)
    }

    private func exportBackup() {
        do {
            document = NativeLibraryBackupDocument(data: try store.makeLibraryBackup())
            defaultFilename = "fqapp-backup-\(Self.filenameDate()).json"
            message = nil
            exporting = true
        } catch { showError(error.localizedDescription) }
    }

    private func importBackup(_ result: Result<[URL], Error>) {
        do {
            guard let url = try result.get().first else { return }
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            preview = try store.previewLibraryBackup(data)
            pendingRestore = data
            message = nil
        } catch { showError(error.localizedDescription) }
    }

    private func restoreBackup() {
        guard let pendingRestore else { return }
        do {
            let result = try store.mergeLibraryBackup(pendingRestore)
            message = "恢复完成：新增 \(result.shelf) 条收藏、\(result.history) 条进度、\(result.episodes) 集已看记录。已有内容已保留。"
            isError = false
            preview = nil
            self.pendingRestore = nil
        } catch { showError(error.localizedDescription) }
    }

    private func exportCompleted(_ result: Result<URL, Error>) {
        switch result {
        case .success: isError = false; message = "FQApp 备份文件已保存。"
        case .failure(let error): showError(error.localizedDescription)
        }
    }

    private func showError(_ text: String) { isError = true; message = text }

    private static func filenameDate() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }
}
