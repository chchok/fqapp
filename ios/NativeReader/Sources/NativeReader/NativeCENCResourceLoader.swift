import AVFoundation
import Foundation

private enum NativeCENCError: LocalizedError {
    case message(String)
    var errorDescription: String? {
        switch self { case .message(let text): return text }
    }
}

private final class NativeCENCRangeSource: @unchecked Sendable {
    let url: URL
    private let lock = NSLock()
    private var length: Int64?
    private var activeTask: URLSessionDataTask?

    init(url: URL) { self.url = url }

    func size() -> Int64 {
        lock.lock()
        let cached = length
        lock.unlock()
        if let cached { return cached }
        guard let (data, response) = request(offset: 0, count: 1), data.count == 1,
              let total = Self.totalLength(response) else { return -1 }
        lock.lock(); length = total; lock.unlock()
        return total
    }

    func read(offset: UInt64, into buffer: UnsafeMutablePointer<UInt8>?, count: Int) -> Int {
        guard count > 0, let buffer, offset <= UInt64(Int64.max),
              let (data, response) = request(offset: Int64(offset), count: count),
              Self.totalLength(response) == size(), data.count <= count else { return -1 }
        data.copyBytes(to: buffer, count: data.count)
        return data.count
    }

    func cancel() {
        lock.lock(); let task = activeTask; activeTask = nil; lock.unlock()
        task?.cancel()
    }

    private func request(offset: Int64, count: Int) -> (Data, HTTPURLResponse)? {
        guard offset >= 0, count > 0, Int64(count - 1) <= Int64.max - offset else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 35)
        request.setValue("bytes=\(offset)-\(offset + Int64(count) - 1)", forHTTPHeaderField: "Range")
        request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        let semaphore = DispatchSemaphore(value: 0)
        var result: (Data, HTTPURLResponse)?
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let data, let response = response as? HTTPURLResponse,
               response.statusCode == 206,
               response.value(forHTTPHeaderField: "Content-Encoding").map({ $0.lowercased() == "identity" }) ?? true,
               Self.rangeMatches(response, offset: offset, count: data.count) {
                result = (data, response)
            }
            semaphore.signal()
        }
        lock.lock(); activeTask = task; lock.unlock()
        task.resume()
        _ = semaphore.wait(timeout: .now() + 40)
        lock.lock(); if activeTask === task { activeTask = nil }; lock.unlock()
        return result
    }

    private static func totalLength(_ response: HTTPURLResponse) -> Int64? {
        guard let value = response.value(forHTTPHeaderField: "Content-Range"),
              let slash = value.lastIndex(of: "/"), let result = Int64(value[value.index(after: slash)...]), result >= 0 else { return nil }
        return result
    }

    private static func rangeMatches(_ response: HTTPURLResponse, offset: Int64, count: Int) -> Bool {
        guard let value = response.value(forHTTPHeaderField: "Content-Range"),
              value.lowercased().hasPrefix("bytes "), let dash = value.firstIndex(of: "-"),
              let space = value.firstIndex(of: " "), let slash = value.lastIndex(of: "/"),
              let start = Int64(value[value.index(after: space)..<dash]),
              let end = Int64(value[value.index(after: dash)..<slash]) else { return false }
        return start == offset && end >= start && end - start + 1 == count
    }
}

private let nativeCENCSize: @convention(c) (UnsafeMutableRawPointer?) -> Int64 = { user in
    guard let user else { return -1 }
    return Unmanaged<NativeCENCRangeSource>.fromOpaque(user).takeUnretainedValue().size()
}

private let nativeCENCRead: @convention(c) (UnsafeMutableRawPointer?, UInt64, UnsafeMutablePointer<UInt8>?, Int) -> Int = { user, offset, buffer, count in
    guard let user else { return -1 }
    return Unmanaged<NativeCENCRangeSource>.fromOpaque(user).takeUnretainedValue().read(offset: offset, into: buffer, count: count)
}

private let nativeCENCCancel: @convention(c) (UnsafeMutableRawPointer?) -> Void = { user in
    guard let user else { return }
    Unmanaged<NativeCENCRangeSource>.fromOpaque(user).takeUnretainedValue().cancel()
}

private let nativeCENCClose: @convention(c) (UnsafeMutableRawPointer?) -> Void = { user in
    guard let user else { return }
    _ = Unmanaged<NativeCENCRangeSource>.fromOpaque(user).takeRetainedValue()
}

/// Provides an encrypted MP4 to AVFoundation as a byte-range resource while the
/// shared C crypto core transparently clears CENC AES-CTR sample payloads.
final class NativeCENCResourceLoader: NSObject, AVAssetResourceLoaderDelegate {
    private let source: NativeAudioSource
    private let worker = DispatchQueue(label: "com.chchok.xiaomanreading.cenc-loader", qos: .userInitiated)
    private var stream: OpaquePointer?
    private var rangeSource: NativeCENCRangeSource?

    init(source: NativeAudioSource) {
        self.source = source
        super.init()
    }

    func makePlayerItem() throws -> AVPlayerItem {
        guard var parts = URLComponents(url: source.url, resolvingAgainstBaseURL: false) else {
            throw NativeCENCError.message("加密音频地址无效")
        }
        parts.scheme = "xiaomancenc"
        guard let customURL = parts.url else { throw NativeCENCError.message("加密音频地址无效") }
        let asset = AVURLAsset(url: customURL)
        asset.resourceLoader.setDelegate(self, queue: DispatchQueue(label: "com.chchok.xiaomanreading.cenc-delegate"))
        return AVPlayerItem(asset: asset)
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, shouldWaitForLoadingOfRequestedResource loadingRequest: AVAssetResourceLoadingRequest) -> Bool {
        worker.async { [weak self] in self?.load(loadingRequest) }
        return true
    }

    func resourceLoader(_ resourceLoader: AVAssetResourceLoader, didCancel loadingRequest: AVAssetResourceLoadingRequest) {
        rangeSource?.cancel()
    }

    private func load(_ request: AVAssetResourceLoadingRequest) {
        guard !request.isCancelled else { return }
        do {
            try openStreamIfNeeded()
            guard let stream else { throw NativeCENCError.message("无法打开加密媒体流") }
            if let information = request.contentInformationRequest {
                information.contentType = AVFileType.mp4.rawValue
                information.contentLength = sp_stream_size(stream)
                information.isByteRangeAccessSupported = true
            }
            if let dataRequest = request.dataRequest {
                let offset = max(dataRequest.requestedOffset, dataRequest.currentOffset)
                let bytes = dataRequest.requestsAllDataToEndOfResource
                    ? max(0, sp_stream_size(stream) - offset)
                    : Int64(max(0, dataRequest.requestedLength))
                var error = sp_error()
                guard sp_stream_seek(stream, offset, &error) >= 0 else { throw NativeCENCError.message("加密媒体定位失败") }
                var remaining = bytes
                while remaining > 0 {
                    guard !request.isCancelled else { return }
                    let chunkSize = Int(min(remaining, 64 * 1024))
                    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: chunkSize)
                    defer { buffer.deallocate() }
                    let read = sp_stream_read(stream, buffer, chunkSize, &error)
                    guard read > 0 else { throw NativeCENCError.message("加密媒体读取失败（\(error.code.rawValue)）") }
                    dataRequest.respond(with: Data(bytes: buffer, count: read))
                    remaining -= Int64(read)
                }
            }
            if !request.isCancelled { request.finishLoading() }
        } catch {
            if !request.isCancelled { request.finishLoading(with: error) }
        }
    }

    private func openStreamIfNeeded() throws {
        guard stream == nil else { return }
        guard let keyData = Self.keyData(source.keyHex), keyData.count == 16 else {
            throw NativeCENCError.message("CENC 密钥格式无效")
        }
        let rangeSource = NativeCENCRangeSource(url: source.url)
        self.rangeSource = rangeSource
        let user = Unmanaged.passRetained(rangeSource).toOpaque()
        var io = sp_io(user: user, size: nativeCENCSize, read_at: nativeCENCRead, cancel: nativeCENCCancel, close: nativeCENCClose)
        var error = sp_error()
        let opened = keyData.withUnsafeBytes { bytes in
            sp_stream_open(&io, bytes.bindMemory(to: UInt8.self).baseAddress, &error)
        }
        guard let opened else {
            Unmanaged<NativeCENCRangeSource>.fromOpaque(user).release()
            self.rangeSource = nil
            throw NativeCENCError.message("无法解密音频 MP4（\(error.code.rawValue)）")
        }
        stream = opened
    }

    private static func keyData(_ hex: String?) -> Data? {
        guard let hex, hex.count == 32 else { return nil }
        var bytes = Data(capacity: 16)
        var index = hex.startIndex
        for _ in 0..<16 {
            let end = hex.index(index, offsetBy: 2)
            guard let value = UInt8(hex[index..<end], radix: 16) else { return nil }
            bytes.append(value)
            index = end
        }
        return bytes
    }

    deinit {
        if let stream { sp_stream_close(stream) }
    }
}
