import Foundation
import os.log

private let logger = Logger(subsystem: "com.textblocker", category: "YTDLP")

enum YTDLPError: LocalizedError {
    case processError(String)
    case parseError(String)
    case notInstalled
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .processError(let msg): return "yt-dlp error: \(msg)"
        case .parseError(let msg): return "Parse error: \(msg)"
        case .notInstalled: return "yt-dlp not installed. Run: brew install yt-dlp"
        case .invalidURL: return "Invalid YouTube URL"
        }
    }
}

enum YTDLPProgressStage {
    case downloading
    case merging
}

struct YTDLPProgressUpdate {
    let stage: YTDLPProgressStage
    let progress: Double?
    let message: String
}

struct YouTubeVideo: Identifiable {
    let id: String
    let title: String
    let duration: Int?
    let thumbnailURL: URL?
}

actor YTDLPService {
    static let shared = YTDLPService()

    private let ytdlpPath: String

    init(ytdlpPath: String? = nil) {
        self.ytdlpPath = ytdlpPath
            ?? DependencyLocator.findExecutable(named: "yt-dlp")
            ?? "/opt/homebrew/bin/yt-dlp"
    }

    // MARK: - Video Info

    func getVideoInfo(url: String) async throws -> YouTubeVideo {
        let output = try await runYTDLP(args: [
            "--no-playlist",
            "--print", "%(id)s\t%(title)s\t%(duration)s",
            url
        ])

        let parts = output.trimmingCharacters(in: .whitespacesAndNewlines).split(separator: "\t")
        guard parts.count >= 2 else {
            throw YTDLPError.parseError("Could not parse video info")
        }

        let id = String(parts[0])
        let title = String(parts[1])
        let duration = parts.count > 2 ? Int(parts[2]) : nil

        return YouTubeVideo(
            id: id,
            title: title,
            duration: duration,
            thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg")
        )
    }

    // MARK: - Playlist

    func getPlaylistVideos(url: String) async throws -> [YouTubeVideo] {
        let output = try await runYTDLP(args: [
            "--flat-playlist",
            "-j",
            url
        ])

        var videos: [YouTubeVideo] = []

        for line in output.components(separatedBy: "\n") where !line.isEmpty {
            guard let data = line.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let id = json["id"] as? String else {
                continue
            }

            let title = json["title"] as? String ?? "Unknown"
            let duration = json["duration"] as? Int

            videos.append(YouTubeVideo(
                id: id,
                title: title,
                duration: duration,
                thumbnailURL: URL(string: "https://i.ytimg.com/vi/\(id)/maxresdefault.jpg")
            ))
        }

        return videos
    }

    // MARK: - Download

    func outputURL(forTitle title: String, id: String, outputDir: URL) -> URL {
        let sanitizedTitle = sanitizeFilename(title)
        return outputDir.appendingPathComponent("\(sanitizedTitle)_\(id).mp4")
    }

    func downloadVideo(
        url: String,
        outputURL: URL,
        duration: Double?,
        format: String = "best[height<=720][ext=mp4]/bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/best",
        progressHandler: @escaping @Sendable (YTDLPProgressUpdate) -> Void
    ) async throws -> URL {
        try await runYTDLPWithProgress(
            args: [
                "--force-overwrites",
                "-f", format,
                "--merge-output-format", "mp4",
                "-o", outputURL.path,
                url
            ],
            duration: duration,
            progressHandler: progressHandler
        )

        return outputURL
    }

    func downloadVideo(
        url: String,
        outputDir: URL,
        format: String = "best[height<=720][ext=mp4]/bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/best",
        progressHandler: @escaping @Sendable (YTDLPProgressUpdate) -> Void
    ) async throws -> URL {
        let video = try await getVideoInfo(url: url)
        let outputURL = outputURL(forTitle: video.title, id: video.id, outputDir: outputDir)
        return try await downloadVideo(
            url: url,
            outputURL: outputURL,
            duration: video.duration.map(Double.init),
            format: format,
            progressHandler: progressHandler
        )
    }

    func downloadVideo(
        videoId: String,
        outputDir: URL,
        format: String = "best[height<=720][ext=mp4]/bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/best",
        progressHandler: @escaping @Sendable (YTDLPProgressUpdate) -> Void
    ) async throws -> URL {
        let url = "https://www.youtube.com/watch?v=\(videoId)"
        return try await downloadVideo(
            url: url,
            outputDir: outputDir,
            format: format,
            progressHandler: progressHandler
        )
    }

    // MARK: - Private

    private func sanitizeFilename(_ name: String) -> String {
        let invalidChars = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        return name
            .components(separatedBy: invalidChars)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespaces)
            .prefix(100)
            .description
    }

    private func runYTDLP(args: [String]) async throws -> String {
        try assertExecutableAvailable()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.ytdlpPath)
                process.arguments = args

                let pipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = pipe
                process.standardError = errorPipe

                do {
                    try process.run()
                    process.waitUntilExit()

                    let data = pipe.fileHandleForReading.readDataToEndOfFile()
                    let output = String(data: data, encoding: .utf8) ?? ""

                    if process.terminationStatus != 0 {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: YTDLPError.processError(errorOutput))
                    } else {
                        continuation.resume(returning: output)
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runYTDLPWithProgress(
        args: [String],
        duration: Double?,
        progressHandler: @escaping @Sendable (YTDLPProgressUpdate) -> Void
    ) async throws {
        try assertExecutableAvailable()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.ytdlpPath)
                process.arguments = ["--newline"] + args

                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe

                final class OutputBuffer: @unchecked Sendable {
                    private let lock = NSLock()
                    private var buffer = ""
                    private let maxSize: Int

                    init(maxSize: Int) {
                        self.maxSize = maxSize
                    }

                    func append(_ text: String) {
                        lock.lock()
                        buffer.append(text)
                        if buffer.count > maxSize {
                            buffer = String(buffer.suffix(maxSize))
                        }
                        lock.unlock()
                    }

                    func snapshot() -> String {
                        lock.lock()
                        let value = buffer
                        lock.unlock()
                        return value
                    }
                }

                let outputBuffer = OutputBuffer(maxSize: 20_000)
                let progressState = ProgressState()
                let mergeState = ProgressState()

                // Parse progress output
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty,
                          let text = String(data: data, encoding: .utf8) else { return }

                    outputBuffer.append(text)
                    for line in text.components(separatedBy: "\n") {
                        // Parse: [download]  45.2% of 100.00MiB at 5.00MiB/s
                        if line.contains("[download]") && line.contains("%") {
                            if let range = line.range(of: #"(\d+\.?\d*)%"#, options: .regularExpression) {
                                let percentStr = line[range].dropLast()
                                if let percent = Double(percentStr) {
                                    let progress = percent / 100
                                    progressState.update(progress)
                                    DispatchQueue.main.async {
                                        progressHandler(YTDLPProgressUpdate(
                                            stage: .downloading,
                                            progress: progress,
                                            message: line
                                        ))
                                    }
                                }
                            }
                        } else if line.contains("time="),
                                  let duration,
                                  duration > 0,
                                  let timeValue = parseFFmpegTime(line) {
                            let progress = min(max(timeValue / duration, 0), 1)
                            mergeState.update(progress)
                            DispatchQueue.main.async {
                                progressHandler(YTDLPProgressUpdate(
                                    stage: .merging,
                                    progress: progress,
                                    message: line
                                ))
                            }
                        } else if line.contains("[Merger]") ||
                                    line.contains("Merging formats") ||
                                    line.contains("[ffmpeg]") ||
                                    line.contains("Post-processing") ||
                                    line.contains("Fixing") ||
                                    line.contains("Destination:") {
                            let progress = mergeState.current()
                            DispatchQueue.main.async {
                                progressHandler(YTDLPProgressUpdate(
                                    stage: .merging,
                                    progress: progress > 0 ? progress : nil,
                                    message: line
                                ))
                            }
                        }
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()

                    pipe.fileHandleForReading.readabilityHandler = nil
                    let remainingData = pipe.fileHandleForReading.readDataToEndOfFile()
                    if let remainingText = String(data: remainingData, encoding: .utf8), !remainingText.isEmpty {
                        outputBuffer.append(remainingText)
                    }

                    if process.terminationStatus != 0 {
                        let snapshot = outputBuffer.snapshot()
                        let errorOutput = snapshot.isEmpty ? "Unknown error" : snapshot
                        continuation.resume(throwing: YTDLPError.processError(errorOutput))
                    } else {
                        DispatchQueue.main.async {
                            progressHandler(YTDLPProgressUpdate(
                                stage: .merging,
                                progress: 1.0,
                                message: "Complete"
                            ))
                        }
                        continuation.resume(returning: ())
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private final class ProgressState: @unchecked Sendable {
        private let lock = NSLock()
        private var value: Double = 0

        func update(_ progress: Double) {
            lock.lock()
            value = progress
            lock.unlock()
        }

        func current() -> Double {
            lock.lock()
            let progress = value
            lock.unlock()
            return progress
        }
    }

    private func assertExecutableAvailable() throws {
        guard FileManager.default.isExecutableFile(atPath: ytdlpPath) else {
            throw YTDLPError.notInstalled
        }
    }
}

private func parseFFmpegTime(_ line: String) -> Double? {
    guard let range = line.range(of: "time=") else { return nil }
    let substring = line[range.upperBound...]
    let timeToken = substring.split(separator: " ").first.map(String.init) ?? ""
    let parts = timeToken.split(separator: ":").map(String.init)
    guard parts.count == 3,
          let hours = Double(parts[0]),
          let minutes = Double(parts[1]),
          let seconds = Double(parts[2]) else {
        return nil
    }
    return hours * 3600 + minutes * 60 + seconds
}
