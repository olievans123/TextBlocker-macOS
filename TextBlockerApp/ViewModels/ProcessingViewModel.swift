import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.textblocker", category: "Processing")

private enum ProcessingError: LocalizedError {
    case noFramesExtracted

    var errorDescription: String? {
        switch self {
        case .noFramesExtracted:
            return "No frames were extracted. Check the sample rate and input video."
        }
    }
}

@MainActor
class ProcessingViewModel: ObservableObject {

    @Published var jobs: [ProcessingJob] = []
    @Published var isProcessing = false
    @Published var currentPhase: String = ""
    @Published var error: String?

    private let ffmpeg = FFmpegService.shared
    private let ytdlp = YTDLPService.shared
    private let vision = VisionOCRService.shared
    private let hasher = PerceptualHashService()
    private let settings = SettingsService.shared
    private var activeDownloadToken: UUID?

    // MARK: - Public Interface

    func processVideo(at url: URL) async {
        let job = ProcessingJob(inputURL: url, type: .localFile)
        jobs.append(job)
        await processJob(job)
    }

    func processFolder(at url: URL) async {
        let videoExtensions = ["mp4", "mkv", "mov", "avi", "webm", "m4v"]

        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            error = "Cannot read folder"
            return
        }

        var videoURLs: [URL] = []
        while let fileURL = enumerator.nextObject() as? URL {
            if videoExtensions.contains(fileURL.pathExtension.lowercased()) {
                videoURLs.append(fileURL)
            }
        }

        for videoURL in videoURLs {
            let job = ProcessingJob(inputURL: videoURL, type: .localFile)
            jobs.append(job)
        }

        for job in jobs where job.status == .pending {
            await processJob(job)
        }
    }

    func processYouTubeVideo(url: String) async {
        isProcessing = true
        currentPhase = "Fetching video info..."
        defer {
            isProcessing = jobs.contains { $0.status.isProcessing }
            if !isProcessing {
                currentPhase = ""
            }
        }

        var tempDir: URL?
        var job: ProcessingJob?
        do {
            let video = try await ytdlp.getVideoInfo(url: url)

            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TextBlocker_\(UUID().uuidString)")
            tempDir = dir
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let outputURL = await ytdlp.outputURL(forTitle: video.title, id: video.id, outputDir: dir)
            let newJob = ProcessingJob(
                inputURL: outputURL,
                type: .youtubeVideo,
                sourceURL: url,
                title: video.title
            )
            newJob.status = .downloading(progress: 0)
            jobs.append(newJob)
            job = newJob

            currentPhase = youtubePhaseText(
                progress: 0,
                stage: .downloading,
                status: "Starting download",
                title: video.title,
                prefix: nil
            )

            let downloadToken = UUID()
            activeDownloadToken = downloadToken
            _ = try await ytdlp.downloadVideo(
                url: url,
                outputURL: outputURL,
                duration: video.duration.map(Double.init)
            ) { [weak self, weak newJob] update in
                Task { @MainActor in
                    guard self?.activeDownloadToken == downloadToken else { return }
                    let progress = update.progress ?? (update.stage == .merging ? 0 : (newJob?.status.progress ?? 0))
                    switch update.stage {
                    case .downloading:
                        newJob?.status = .downloading(progress: progress)
                    case .merging:
                        newJob?.status = .merging(progress: progress)
                    }
                    self?.currentPhase = self?.youtubePhaseText(
                        progress: update.progress,
                        stage: update.stage,
                        status: update.message,
                        title: video.title,
                        prefix: nil
                    ) ?? ""
                }
            }

            activeDownloadToken = nil
            currentPhase = "Preparing processing - \(video.title)"

            await processJob(newJob)
        } catch {
            if let tempDir, job == nil {
                try? FileManager.default.removeItem(at: tempDir)
            }
            activeDownloadToken = nil
            job?.status = .failed(error: error.localizedDescription)
            self.error = error.localizedDescription
        }
    }

    func processYouTubePlaylist(url: String) async {
        isProcessing = true
        currentPhase = "Fetching playlist..."
        defer {
            isProcessing = jobs.contains { $0.status.isProcessing }
            if !isProcessing {
                currentPhase = ""
            }
        }

        var tempDir: URL?
        do {
            let videos = try await ytdlp.getPlaylistVideos(url: url)
            guard !videos.isEmpty else {
                error = "No videos found in playlist"
                return
            }
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TextBlocker_\(UUID().uuidString)")
            tempDir = dir
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            for (index, video) in videos.enumerated() {
                let outputURL = await ytdlp.outputURL(forTitle: video.title, id: video.id, outputDir: dir)
                let job = ProcessingJob(
                    inputURL: outputURL,
                    type: .youtubePlaylist,
                    sourceURL: video.id,
                    title: video.title
                )
                job.status = .downloading(progress: 0)
                jobs.append(job)

                let idx = index + 1
                let total = videos.count
                currentPhase = youtubePhaseText(
                    progress: 0,
                    stage: .downloading,
                    status: "Starting download",
                    title: video.title,
                    prefix: "\(idx)/\(total)"
                )

                let downloadToken = UUID()
                activeDownloadToken = downloadToken
                do {
                    _ = try await ytdlp.downloadVideo(
                        url: "https://www.youtube.com/watch?v=\(video.id)",
                        outputURL: outputURL,
                        duration: video.duration.map(Double.init)
                    ) { [weak self, weak job] update in
                        Task { @MainActor in
                            guard self?.activeDownloadToken == downloadToken else { return }
                            let progress = update.progress ?? (update.stage == .merging ? 0 : (job?.status.progress ?? 0))
                            switch update.stage {
                            case .downloading:
                                job?.status = .downloading(progress: progress)
                            case .merging:
                                job?.status = .merging(progress: progress)
                            }
                            self?.currentPhase = self?.youtubePhaseText(
                                progress: update.progress,
                                stage: update.stage,
                                status: update.message,
                                title: video.title,
                                prefix: "\(idx)/\(total)"
                            ) ?? ""
                        }
                    }

                    activeDownloadToken = nil
                    currentPhase = "Preparing processing - \(video.title)"
                    await processJob(job)
                } catch {
                    activeDownloadToken = nil
                    job.status = .failed(error: error.localizedDescription)
                    self.error = error.localizedDescription
                }
            }
        } catch {
            if let tempDir {
                try? FileManager.default.removeItem(at: tempDir)
                jobs.removeAll { $0.inputURL.path.hasPrefix(tempDir.path) }
            }
            activeDownloadToken = nil
            self.error = error.localizedDescription
        }
    }

    func clearCompleted() {
        jobs.removeAll { job in
            if case .completed = job.status { return true }
            if case .failed = job.status { return true }
            if case .cancelled = job.status { return true }
            return false
        }
    }

    func cancelJob(_ job: ProcessingJob) {
        job.isCancellationRequested = true
        job.status = .cancelled
    }

    func removeJob(_ job: ProcessingJob) {
        jobs.removeAll { $0.id == job.id }
    }

    // MARK: - Core Processing Pipeline

    private func processJob(_ job: ProcessingJob) async {
        isProcessing = true
        error = nil
        defer {
            isProcessing = jobs.contains { $0.status.isProcessing }
            if !isProcessing {
                currentPhase = ""
            }
        }

        var tempDir: URL?
        do {
            // Check for cancellation
            guard !job.isCancellationRequested else { return }

            // Phase 1: Get video info
            let videoInfo = try await ffmpeg.getVideoInfo(job.inputURL)
            logger.info("Processing: \(videoInfo.width)x\(videoInfo.height), \(videoInfo.duration)s")

            guard !job.isCancellationRequested else { return }

            // Phase 2: Extract frames
            currentPhase = "Extracting frames..."
            job.status = .extracting(progress: 0)

            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TextBlocker_frames_\(UUID().uuidString)")
            tempDir = dir
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

            let frameURLs = try await ffmpeg.extractFrames(
                from: job.inputURL,
                fps: settings.sampleFPS,
                height: settings.ocrHeight,
                outputDir: dir
            ) { [weak self, weak job] progress in
                Task { @MainActor in
                    self?.currentPhase = "Extracting frames: \(Int(progress * 100))%"
                    job?.status = .extracting(progress: progress)
                }
            }

            logger.info("Extracted \(frameURLs.count) frames")
            guard !frameURLs.isEmpty else {
                throw ProcessingError.noFramesExtracted
            }

            // Phase 3: OCR detection with frame skipping
            currentPhase = "Detecting text..."
            job.status = .detecting(progress: 0)

            var frameDetections: [FrameDetection] = []
            var lastHash: UInt64?
            var lastOCRBoxes: [CGRect] = []
            var lastOCRIndex: Int = 0
            let frameDuration = 1.0 / settings.sampleFPS
            let forceIntervalFrames = Int(settings.forceInterval * settings.sampleFPS)

            let totalFrames = frameURLs.count
            for (index, frameURL) in frameURLs.enumerated() {
                // Check for cancellation during detection loop
                if job.isCancellationRequested { break }

                let timestamp = Double(index) * frameDuration
                let progress = Double(index + 1) / Double(totalFrames)
                currentPhase = "Detecting text: \(Int(progress * 100))%"
                job.status = .detecting(progress: progress)

                // Compute perceptual hash
                let hash = hasher.computeHash(from: frameURL)

                // Check if we should skip OCR
                let framesSinceLastOCR = index - lastOCRIndex
                let shouldSkip = settings.skipSimilar &&
                    lastHash != nil &&
                    hasher.areSimilar(hash, lastHash!, threshold: settings.sceneThreshold) &&
                    framesSinceLastOCR < forceIntervalFrames

                var boxes: [CGRect]

                if shouldSkip {
                    // Reuse previous boxes
                    boxes = lastOCRBoxes
                } else {
                    // Run Vision OCR
                    let normalizedBoxes = try await vision.detectTextRegions(
                        in: frameURL,
                        languages: settings.languages,
                        useAccurateMode: settings.useAccurateMode
                    )

                    if index < 5 {
                        logger.info("Frame \(index): detected \(normalizedBoxes.count) text regions")
                        for (j, box) in normalizedBoxes.prefix(3).enumerated() {
                            logger.info("  Box \(j): x=\(box.origin.x), y=\(box.origin.y), w=\(box.width), h=\(box.height)")
                        }
                    }

                    // Denormalize to pixel coordinates
                    boxes = await vision.denormalizeBoxes(
                        normalizedBoxes,
                        imageWidth: videoInfo.width,
                        imageHeight: videoInfo.height
                    )

                    lastOCRBoxes = boxes
                    lastOCRIndex = index
                }

                lastHash = hash

                if !boxes.isEmpty {
                    frameDetections.append(FrameDetection(
                        frameIndex: index,
                        timestamp: timestamp,
                        boxes: boxes,
                        hash: hash
                    ))
                }
            }

            logger.info("Detected text in \(frameDetections.count) frames")

            // Phase 4: Merge overlapping boxes and compress time ranges
            currentPhase = "Processing regions..."

            let regions = processDetections(
                frameDetections,
                mergePad: CGFloat(settings.mergePad),
                frameDuration: frameDuration
            )

            job.detectedRegions = regions.count
            logger.info("Created \(regions.count) text regions")

            // Debug: log first few regions
            for (i, region) in regions.prefix(3).enumerated() {
                logger.info("Region \(i): x=\(Int(region.box.origin.x)), y=\(Int(region.box.origin.y)), w=\(Int(region.box.width)), h=\(Int(region.box.height)), time=\(region.startTime)-\(region.endTime)")
            }

            // Check for cancellation before encoding (most expensive phase)
            guard !job.isCancellationRequested else {
                if let tempDir {
                    try? FileManager.default.removeItem(at: tempDir)
                }
                return
            }

            // Phase 5: Generate filter and encode
            currentPhase = "Encoding video..."
            job.status = .encoding(progress: 0)

            // Boxes are already in original video coordinates (from denormalizeBoxes)
            // so scale = 1.0
            var filterSpec = regions.map { region in
                region.toFFmpegFilter(padding: settings.padding, scale: 1.0)
            }.joined(separator: ",")

            logger.info("Filter spec (first 500 chars): \(String(filterSpec.prefix(500)))")

            // Check filter complexity
            if regions.count > self.settings.maxFilters {
                logger.warning("Filter count \(regions.count) exceeds max \(self.settings.maxFilters), collapsing...")
                filterSpec = collapseFilters(regions: regions, padding: self.settings.padding, scale: 1.0)
            }

            // Generate output path
            let outputURL = generateOutputURL(for: job.inputURL)

            try await ffmpeg.applyTextBlockingFilters(
                inputURL: job.inputURL,
                outputURL: outputURL,
                filterSpec: filterSpec,
                quality: settings.quality
            ) { [weak self, weak job] progress in
                Task { @MainActor in
                    self?.currentPhase = "Encoding: \(Int(progress * 100))%"
                    job?.status = .encoding(progress: progress)
                }
            }

            if job.isCancellationRequested {
                job.status = .cancelled
                try? FileManager.default.removeItem(at: outputURL)
                if let tempDir {
                    try? FileManager.default.removeItem(at: tempDir)
                }
                return
            }

            job.outputURL = outputURL
            job.status = .completed

            // Clear any previous error on success
            self.error = nil

            // Cleanup temp files
            if let tempDir {
                try? FileManager.default.removeItem(at: tempDir)
            }

            logger.info("Processing complete: \(outputURL.path)")

        } catch {
            job.status = .failed(error: error.localizedDescription)
            self.error = error.localizedDescription
            logger.error("Processing failed: \(error.localizedDescription)")
            if let tempDir {
                try? FileManager.default.removeItem(at: tempDir)
            }
        }
    }

    // MARK: - Box Processing

    private func processDetections(
        _ detections: [FrameDetection],
        mergePad: CGFloat,
        frameDuration: Double
    ) -> [TextRegion] {
        var regions: [TextRegion] = []

        // Maximum gap allowed to extend a region (2 seconds)
        let maxGap = 2.0

        for detection in detections {
            // Merge overlapping boxes within this frame
            let mergedBoxes = mergeBoxes(detection.boxes, padding: mergePad)

            for box in mergedBoxes {
                // Try to extend an existing region with similar box
                // BUT only if the detection is close in time (no big gaps)
                if let existingIndex = regions.firstIndex(where: { region in
                    boxesSimilar(region.box, box, tolerance: mergePad) &&
                    (detection.timestamp - region.endTime) <= maxGap
                }) {
                    // Extend the time range
                    regions[existingIndex].endTime = detection.timestamp + frameDuration
                } else {
                    // Create new region
                    regions.append(TextRegion(
                        box: box,
                        startTime: detection.timestamp,
                        endTime: detection.timestamp + frameDuration
                    ))
                }
            }
        }

        return regions
    }

    private func mergeBoxes(_ boxes: [CGRect], padding: CGFloat) -> [CGRect] {
        guard !boxes.isEmpty else { return [] }

        var merged = boxes
        var didMerge = true

        while didMerge {
            didMerge = false
            var newMerged: [CGRect] = []

            for box in merged {
                let paddedBox = box.insetBy(dx: -padding, dy: -padding)

                if let existingIndex = newMerged.firstIndex(where: { $0.insetBy(dx: -padding, dy: -padding).intersects(paddedBox) }) {
                    newMerged[existingIndex] = newMerged[existingIndex].union(box)
                    didMerge = true
                } else {
                    newMerged.append(box)
                }
            }

            merged = newMerged
        }

        return merged
    }

    private func boxesSimilar(_ box1: CGRect, _ box2: CGRect, tolerance: CGFloat) -> Bool {
        let xDiff = abs(box1.origin.x - box2.origin.x)
        let yDiff = abs(box1.origin.y - box2.origin.y)
        let wDiff = abs(box1.width - box2.width)
        let hDiff = abs(box1.height - box2.height)

        return xDiff <= tolerance && yDiff <= tolerance && wDiff <= tolerance && hDiff <= tolerance
    }

    private func collapseFilters(regions: [TextRegion], padding: Int, scale: Double) -> String {
        guard !regions.isEmpty else { return "" }

        // Find bounding box of all regions
        var minX = CGFloat.infinity
        var minY = CGFloat.infinity
        var maxX = CGFloat.zero
        var maxY = CGFloat.zero
        var minTime = Double.infinity
        var maxTime = Double.zero

        for region in regions {
            minX = min(minX, region.box.minX)
            minY = min(minY, region.box.minY)
            maxX = max(maxX, region.box.maxX)
            maxY = max(maxY, region.box.maxY)
            minTime = min(minTime, region.startTime)
            maxTime = max(maxTime, region.endTime)
        }

        let megaRegion = TextRegion(
            box: CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY),
            startTime: minTime,
            endTime: maxTime
        )

        return megaRegion.toFFmpegFilter(padding: padding, scale: scale)
    }

    private func generateOutputURL(for inputURL: URL) -> URL {
        let directory = inputURL.deletingLastPathComponent()
        let baseName = inputURL.deletingPathExtension().lastPathComponent
        return directory.appendingPathComponent("\(baseName)_blocked.mp4")
    }

    private func youtubePhaseText(
        progress: Double?,
        stage: YTDLPProgressStage,
        status: String,
        title: String,
        prefix: String?
    ) -> String {
        let titleSuffix = title.isEmpty ? "" : " - \(title)"
        let prefixText = prefix.map { "\($0) " } ?? ""

        switch stage {
        case .merging:
            if let progress, progress > 0 {
                return "\(prefixText)Merging: \(Int(progress * 100))%\(titleSuffix)"
            }
            return "\(prefixText)Merging audio + video\(titleSuffix)"
        case .downloading:
            let lower = status.lowercased()
            if lower.contains("destination") {
                return "\(prefixText)Starting download\(titleSuffix)"
            }
            let value = progress ?? 0
            if value >= 0.999 {
                return "\(prefixText)Download complete\(titleSuffix)"
            }
            return "\(prefixText)Downloading: \(Int(value * 100))%\(titleSuffix)"
        }
    }
}
