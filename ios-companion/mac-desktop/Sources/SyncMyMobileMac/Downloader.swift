import Foundation

enum PathTools {
    static func sanitizedRelativePath(_ value: String) -> String {
        let parts = value
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .compactMap { part -> String? in
                let text = String(part)
                guard !text.isEmpty, text != ".", text != ".." else {
                    return nil
                }
                let invalid = CharacterSet(charactersIn: #"<>:"|?*"#).union(.controlCharacters)
                let clean = text.components(separatedBy: invalid).joined(separator: "_").trimmingCharacters(in: .whitespacesAndNewlines)
                return clean.isEmpty ? "_" : clean
            }
        return parts.isEmpty ? "unnamed" : parts.joined(separator: "/")
    }

    static func uniqueByTarget(_ files: [RemoteFile]) -> [RemoteFile] {
        var seen = Set<String>()
        var unique: [RemoteFile] = []
        for file in files {
            let key = sanitizedRelativePath(file.relativePath).lowercased()
            if seen.insert(key).inserted {
                unique.append(file)
            }
        }
        return unique
    }
}

final class DownloadManager {
    func download(
        files: [RemoteFile],
        from device: Device,
        destinationRoot: URL,
        workers: Int,
        progress: @escaping (String) async -> Void,
        log: @escaping (String) async -> Void
    ) async -> DownloadResult {
        let files = PathTools.uniqueByTarget(files)
        let workerCount = max(1, min(workers, 16))
        let api = DeviceAPI(baseURL: device.baseURL)
        let deviceFolder = destinationRoot.appending(path: device.name, directoryHint: .isDirectory)

        var result = DownloadResult()
        let semaphore = AsyncSemaphore(value: workerCount)

        await withTaskGroup(of: String.self) { group in
            for file in files {
                group.addTask {
                    await semaphore.wait()
                    defer { Task { await semaphore.signal() } }

                    let relative = PathTools.sanitizedRelativePath(file.relativePath)
                    let target = deviceFolder.appending(path: relative)

                    do {
                        if FileManager.default.fileExists(atPath: target.path),
                           let size = try? FileManager.default.attributesOfItem(atPath: target.path)[.size] as? NSNumber,
                           size.int64Value == file.size {
                            await log("Skipped \(file.relativePath)")
                            await progress("Skipped \(file.relativePath)")
                            return "skipped"
                        }

                        try await api.download(file, to: target)
                        await log("Downloaded \(file.relativePath)")
                        await progress("Downloaded \(file.relativePath)")
                        return "downloaded"
                    } catch {
                        await log("Failed \(file.relativePath): \(error.localizedDescription)")
                        await progress("Failed \(file.relativePath)")
                        return "failed"
                    }
                }
            }

            for await status in group {
                switch status {
                case "downloaded":
                    result.downloaded += 1
                case "skipped":
                    result.skipped += 1
                case "failed":
                    result.failed += 1
                default:
                    break
                }
            }
        }

        return result
    }
}

actor AsyncSemaphore {
    private var value: Int
    private var continuations: [CheckedContinuation<Void, Never>] = []

    init(value: Int) {
        self.value = value
    }

    func wait() async {
        if value > 0 {
            value -= 1
            return
        }
        await withCheckedContinuation { continuation in
            continuations.append(continuation)
        }
    }

    func signal() {
        if continuations.isEmpty {
            value += 1
        } else {
            continuations.removeFirst().resume()
        }
    }
}
