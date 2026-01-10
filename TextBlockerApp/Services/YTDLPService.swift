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

struct YouTubeVideo: Identifiable {
    let id: String
    let title: String
    let duration: Int?
    let thumbnailURL: URL?
}

actor YTDLPService {
    static let shared = YTDLPService()

    private let ytdlpPath: String

    init(ytdlpPath: String = "/opt/homebrew/bin/yt-dlp") {
        self.ytdlpPath = ytdlpPath
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

    func downloadVideo(
        url: String,
        outputDir: URL,
        format: String = "bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/best[height<=720][ext=mp4]/best",
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws -> URL {
        let video = try await getVideoInfo(url: url)
        let sanitizedTitle = sanitizeFilename(video.title)
        let outputPath = outputDir.appendingPathComponent("\(sanitizedTitle)_\(video.id).mp4")

        try await runYTDLPWithProgress(
            args: [
                "-f", format,
                "--merge-output-format", "mp4",
                "-o", outputPath.path,
                url
            ],
            progressHandler: progressHandler
        )

        return outputPath
    }

    func downloadVideo(
        videoId: String,
        outputDir: URL,
        format: String = "bestvideo[height<=720][ext=mp4]+bestaudio[ext=m4a]/best[height<=720][ext=mp4]/best",
        progressHandler: @escaping @Sendable (Double, String) -> Void
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
        try await withCheckedThrowingContinuation { continuation in
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
        progressHandler: @escaping @Sendable (Double, String) -> Void
    ) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: self.ytdlpPath)
                process.arguments = ["--newline"] + args

                let pipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = pipe
                process.standardError = errorPipe

                // Parse progress output
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty,
                          let text = String(data: data, encoding: .utf8) else { return }

                    for line in text.components(separatedBy: "\n") {
                        // Parse: [download]  45.2% of 100.00MiB at 5.00MiB/s
                        if line.contains("[download]") && line.contains("%") {
                            if let range = line.range(of: #"(\d+\.?\d*)%"#, options: .regularExpression) {
                                let percentStr = line[range].dropLast()
                                if let percent = Double(percentStr) {
                                    DispatchQueue.main.async {
                                        progressHandler(percent / 100, line)
                                    }
                                }
                            }
                        }
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()

                    pipe.fileHandleForReading.readabilityHandler = nil

                    if process.terminationStatus != 0 {
                        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                        let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: YTDLPError.processError(errorOutput))
                    } else {
                        DispatchQueue.main.async {
                            progressHandler(1.0, "Complete")
                        }
                        continuation.resume(returning: ())
                    }
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
