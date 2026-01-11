import Foundation
import os.log

private let logger = Logger(subsystem: "com.textblocker", category: "FFmpegService")

enum FFmpegError: LocalizedError {
    case processError(String)
    case parseError(String)
    case notInstalled
    case cancelled

    var errorDescription: String? {
        switch self {
        case .processError(let msg): return "FFmpeg error: \(msg)"
        case .parseError(let msg): return "Parse error: \(msg)"
        case .notInstalled: return "FFmpeg not installed. Run: brew install ffmpeg"
        case .cancelled: return "Operation cancelled"
        }
    }
}

struct VideoInfo {
    let width: Int
    let height: Int
    let duration: Double
    let fps: Double
    let bitrate: Int?
    let pixelFormat: String
}

actor FFmpegService {
    static let shared = FFmpegService()

    private let ffmpegPath: String
    private let ffprobePath: String

    init(
        ffmpegPath: String? = nil,
        ffprobePath: String? = nil
    ) {
        self.ffmpegPath = ffmpegPath
            ?? DependencyLocator.findExecutable(named: "ffmpeg")
            ?? "/opt/homebrew/bin/ffmpeg"
        self.ffprobePath = ffprobePath
            ?? DependencyLocator.findExecutable(named: "ffprobe")
            ?? "/opt/homebrew/bin/ffprobe"
    }

    // MARK: - Video Info

    func getVideoInfo(_ url: URL) async throws -> VideoInfo {
        let output = try await runProcess(
            executable: ffprobePath,
            args: [
                "-v", "error",
                "-select_streams", "v:0",
                "-show_entries", "stream=width,height,r_frame_rate,pix_fmt:format=duration,bit_rate",
                "-of", "json",
                url.path
            ]
        )

        guard let data = output.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw FFmpegError.parseError("Could not parse ffprobe output")
        }

        let streams = json["streams"] as? [[String: Any]] ?? []
        let format = json["format"] as? [String: Any] ?? [:]

        guard let stream = streams.first else {
            throw FFmpegError.parseError("No video stream found")
        }

        let width = stream["width"] as? Int ?? 0
        let height = stream["height"] as? Int ?? 0
        let pixFmt = stream["pix_fmt"] as? String ?? "yuv420p"

        // Parse frame rate (e.g., "30000/1001" or "30/1")
        var fps: Double = 30.0
        if let fpsStr = stream["r_frame_rate"] as? String {
            let parts = fpsStr.split(separator: "/")
            if parts.count == 2,
               let num = Double(parts[0]),
               let den = Double(parts[1]),
               den > 0 {
                fps = num / den
            }
        }

        let durationStr = format["duration"] as? String ?? "0"
        let duration = Double(durationStr) ?? 0

        let bitrateStr = format["bit_rate"] as? String
        let bitrate = bitrateStr.flatMap { Int($0) }

        return VideoInfo(
            width: width,
            height: height,
            duration: duration,
            fps: fps,
            bitrate: bitrate,
            pixelFormat: pixFmt
        )
    }

    // MARK: - Frame Extraction

    func extractFrames(
        from videoURL: URL,
        fps: Double,
        height: Int,
        outputDir: URL,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws -> [URL] {
        let info = try await getVideoInfo(videoURL)

        // Calculate width maintaining aspect ratio
        let aspectRatio = Double(info.width) / Double(info.height)
        let width = Int(Double(height) * aspectRatio)
        // Ensure width is even for video encoding
        let evenWidth = width % 2 == 0 ? width : width + 1

        let args = [
            "-i", videoURL.path,
            "-vf", "fps=\(fps),scale=\(evenWidth):\(height)",
            "-q:v", "2",
            "-vsync", "vfr",
            "\(outputDir.path)/frame_%06d.jpg"
        ]

        try await runFFmpegWithProgress(
            args: args,
            totalDuration: info.duration,
            progressHandler: progressHandler
        )

        // Return list of extracted frame files
        let files = try FileManager.default.contentsOfDirectory(
            at: outputDir,
            includingPropertiesForKeys: [.contentModificationDateKey]
        )
        return files
            .filter { $0.pathExtension.lowercased() == "jpg" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    // MARK: - Apply Filters

    func applyTextBlockingFilters(
        inputURL: URL,
        outputURL: URL,
        filterSpec: String,
        quality: VideoQuality,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        let info = try await getVideoInfo(inputURL)

        var args = ["-y", "-i", inputURL.path]

        // Add filter if not empty
        if !filterSpec.isEmpty {
            args += ["-vf", filterSpec]
        }

        // Quality settings
        args += quality.ffmpegArgs

        // Audio handling - copy if possible
        args += ["-c:a", "aac", "-b:a", "192k"]

        // Pixel format and optimization
        args += ["-pix_fmt", info.pixelFormat]
        args += ["-movflags", "+faststart"]

        // Output
        args += [outputURL.path]

        try await runFFmpegWithProgress(
            args: args,
            totalDuration: info.duration,
            progressHandler: progressHandler
        )
    }

    // MARK: - Private Methods

    private func runProcess(executable: String, args: [String]) async throws -> String {
        try assertExecutableAvailable(executable)
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executable)
                process.arguments = args

                let pipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = pipe
                process.standardError = errorPipe

                // Collect output data asynchronously to avoid pipe buffer deadlock
                var outputData = Data()
                var errorData = Data()
                let outputLock = NSLock()
                let errorLock = NSLock()

                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty {
                        outputLock.lock()
                        outputData.append(data)
                        outputLock.unlock()
                    }
                }

                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty {
                        errorLock.lock()
                        errorData.append(data)
                        errorLock.unlock()
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()

                    // Stop reading handlers
                    pipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil

                    // Read any remaining data
                    outputLock.lock()
                    outputData.append(pipe.fileHandleForReading.readDataToEndOfFile())
                    outputLock.unlock()

                    errorLock.lock()
                    errorData.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
                    errorLock.unlock()

                    let output = String(data: outputData, encoding: .utf8) ?? ""

                    if process.terminationStatus != 0 {
                        let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        continuation.resume(throwing: FFmpegError.processError(errorOutput))
                    } else {
                        continuation.resume(returning: output)
                    }
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func runFFmpegWithProgress(
        args: [String],
        totalDuration: Double,
        progressHandler: @escaping @Sendable (Double) -> Void
    ) async throws {
        try assertExecutableAvailable(ffmpegPath)
        let executablePath = ffmpegPath  // Capture before dispatch to avoid actor deadlock
        // Use -progress pipe:1 to get progress updates
        let fullArgs = ["-progress", "pipe:1", "-nostats"] + args

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: executablePath)
                process.arguments = fullArgs

                let pipe = Pipe()
                let errorPipe = Pipe()
                process.standardOutput = pipe
                process.standardError = errorPipe

                // Track max progress to prevent going backwards
                final class ProgressState: @unchecked Sendable {
                    private let lock = NSLock()
                    private var maxProgress: Double = 0

                    func shouldUpdate(_ progress: Double) -> Bool {
                        lock.lock()
                        let shouldUpdate = progress > maxProgress
                        if shouldUpdate {
                            maxProgress = progress
                        }
                        lock.unlock()
                        return shouldUpdate
                    }
                }

                let progressState = ProgressState()
                let recordProgress: @Sendable (Double) -> Void = { progress in
                    if progressState.shouldUpdate(progress) {
                        DispatchQueue.main.async {
                            progressHandler(progress)
                        }
                    }
                }

                // Collect error output asynchronously to avoid pipe buffer deadlock
                var errorData = Data()
                let errorLock = NSLock()

                errorPipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    if !data.isEmpty {
                        errorLock.lock()
                        errorData.append(data)
                        errorLock.unlock()
                    }
                }

                // Parse progress output
                pipe.fileHandleForReading.readabilityHandler = { handle in
                    let data = handle.availableData
                    guard !data.isEmpty,
                          let text = String(data: data, encoding: .utf8) else { return }

                    // Parse "out_time_ms=12345678" or "out_time_us=12345678" lines
                    for line in text.components(separatedBy: "\n") {
                        if line.hasPrefix("out_time_us=") {
                            let value = line.replacingOccurrences(of: "out_time_us=", with: "")
                            if let us = Double(value), us > 0 {
                                let seconds = us / 1_000_000
                                let progress = min(max(seconds / totalDuration, 0), 1.0)
                                recordProgress(progress)
                            }
                        } else if line.hasPrefix("out_time_ms=") {
                            let value = line.replacingOccurrences(of: "out_time_ms=", with: "")
                            if let ms = Double(value), ms > 0 {
                                let seconds = ms / 1_000
                                let progress = min(max(seconds / totalDuration, 0), 1.0)
                                recordProgress(progress)
                            }
                        }
                    }
                }

                do {
                    try process.run()
                    process.waitUntilExit()

                    pipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil

                    // Read any remaining error data
                    errorLock.lock()
                    errorData.append(errorPipe.fileHandleForReading.readDataToEndOfFile())
                    errorLock.unlock()

                    if process.terminationStatus != 0 {
                        let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                        logger.error("FFmpeg error: \(errorOutput)")
                        continuation.resume(throwing: FFmpegError.processError(errorOutput))
                    } else {
                        // Don't call progressHandler(1.0) here - it would race with
                        // the caller setting status to .completed, potentially overwriting it
                        continuation.resume(returning: ())
                    }
                } catch {
                    pipe.fileHandleForReading.readabilityHandler = nil
                    errorPipe.fileHandleForReading.readabilityHandler = nil
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func assertExecutableAvailable(_ path: String) throws {
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw FFmpegError.notInstalled
        }
    }
}
