import Foundation
import SwiftUI
import os.log

private let logger = Logger(subsystem: "com.textblocker", category: "Processing")

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

        do {
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TextBlocker_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            currentPhase = "Downloading video..."

            let localURL = try await ytdlp.downloadVideo(
                url: url,
                outputDir: tempDir
            ) { [weak self] progress, status in
                Task { @MainActor in
                    self?.currentPhase = "Downloading: \(Int(progress * 100))%"
                }
            }

            let job = ProcessingJob(inputURL: localURL, type: .youtubeVideo, sourceURL: url)
            jobs.append(job)
            await processJob(job)
        } catch {
            self.error = error.localizedDescription
            isProcessing = false
        }
    }

    func processYouTubePlaylist(url: String) async {
        isProcessing = true
        currentPhase = "Fetching playlist..."

        do {
            let videos = try await ytdlp.getPlaylistVideos(url: url)
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TextBlocker_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            for (index, video) in videos.enumerated() {
                currentPhase = "Downloading video \(index + 1)/\(videos.count)..."

                let localURL = try await ytdlp.downloadVideo(
                    videoId: video.id,
                    outputDir: tempDir
                ) { [weak self] progress, _ in
                    let idx = index + 1
                    let total = videos.count
                    Task { @MainActor in
                        self?.currentPhase = "Downloading \(idx)/\(total): \(Int(progress * 100))%"
                    }
                }

                let job = ProcessingJob(
                    inputURL: localURL,
                    type: .youtubePlaylist,
                    sourceURL: video.id,
                    title: video.title
                )
                jobs.append(job)
            }

            // Process all downloaded videos
            for job in jobs where job.status == .pending {
                await processJob(job)
            }
        } catch {
            self.error = error.localizedDescription
            isProcessing = false
        }
    }

    func clearCompleted() {
        jobs.removeAll { job in
            if case .completed = job.status { return true }
            if case .failed = job.status { return true }
            return false
        }
    }

    // MARK: - Core Processing Pipeline

    private func processJob(_ job: ProcessingJob) async {
        isProcessing = true
        error = nil

        do {
            // Phase 1: Get video info
            let videoInfo = try await ffmpeg.getVideoInfo(job.inputURL)
            logger.info("Processing: \(videoInfo.width)x\(videoInfo.height), \(videoInfo.duration)s")

            // Phase 2: Extract frames
            currentPhase = "Extracting frames..."
            job.status = .extracting(progress: 0)

            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent("TextBlocker_frames_\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            let frameURLs = try await ffmpeg.extractFrames(
                from: job.inputURL,
                fps: settings.sampleFPS,
                height: settings.ocrHeight,
                outputDir: tempDir
            ) { [weak self, weak job] progress in
                Task { @MainActor in
                    self?.currentPhase = "Extracting frames: \(Int(progress * 100))%"
                    job?.status = .extracting(progress: progress)
                }
            }

            logger.info("Extracted \(frameURLs.count) frames")

            // Phase 3: OCR detection with frame skipping
            currentPhase = "Detecting text..."
            job.status = .detecting(progress: 0)

            var frameDetections: [FrameDetection] = []
            var lastHash: UInt64?
            var lastOCRBoxes: [CGRect] = []
            var lastOCRIndex: Int = 0
            let frameDuration = 1.0 / settings.sampleFPS
            let forceIntervalFrames = Int(settings.forceInterval * settings.sampleFPS)

            for (index, frameURL) in frameURLs.enumerated() {
                let timestamp = Double(index) * frameDuration
                let progress = Double(index) / Double(frameURLs.count)
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
                        languages: settings.languages
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

            job.outputURL = outputURL
            job.status = .completed

            // Cleanup temp files
            try? FileManager.default.removeItem(at: tempDir)

            logger.info("Processing complete: \(outputURL.path)")

        } catch {
            job.status = .failed(error: error.localizedDescription)
            self.error = error.localizedDescription
            logger.error("Processing failed: \(error.localizedDescription)")
        }

        isProcessing = jobs.contains { $0.status.isProcessing }
        if !isProcessing {
            currentPhase = ""
        }
    }

    // MARK: - Box Processing

    private func processDetections(
        _ detections: [FrameDetection],
        mergePad: CGFloat,
        frameDuration: Double
    ) -> [TextRegion] {
        var regions: [TextRegion] = []

        for detection in detections {
            // Merge overlapping boxes within this frame
            let mergedBoxes = mergeBoxes(detection.boxes, padding: mergePad)

            for box in mergedBoxes {
                // Try to extend an existing region with similar box
                if let existingIndex = regions.firstIndex(where: { region in
                    boxesSimilar(region.box, box, tolerance: mergePad)
                }) {
                    // Extend the time range
                    regions[existingIndex].endTime = detection.timestamp
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
}
