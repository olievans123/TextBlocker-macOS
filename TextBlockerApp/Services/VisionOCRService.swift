import Vision
import AppKit
import os.log

private let logger = Logger(subsystem: "com.textblocker", category: "VisionOCR")

enum VisionError: LocalizedError {
    case imageLoadFailed
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .imageLoadFailed: return "Failed to load image"
        case .requestFailed(let msg): return "Vision request failed: \(msg)"
        }
    }
}

actor VisionOCRService {
    static let shared = VisionOCRService()

    /// Detect text bounding boxes in an image
    /// Returns boxes in normalized coordinates (0-1), origin at bottom-left
    func detectTextRegions(
        in cgImage: CGImage,
        languages: [String] = ["en"],
        useAccurateMode: Bool = true,
        minimumTextHeight: Float = 0.0
    ) async throws -> [CGRect] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: VisionError.requestFailed(error.localizedDescription))
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: [])
                    return
                }

                // Extract bounding boxes from observations
                let boxes = observations.map { observation in
                    observation.boundingBox
                }

                logger.info("Vision detected \(boxes.count) text regions")

                continuation.resume(returning: boxes)
            }

            // Use accurate mode for better detection (slower but finds more text)
            request.recognitionLevel = useAccurateMode ? .accurate : .fast
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = true  // Helps with stylized/cursive text
            request.automaticallyDetectsLanguage = true  // Auto-detect languages not in list

            // Use latest revision for best detection of varied fonts
            if #available(macOS 13.0, *) {
                request.revision = VNRecognizeTextRequestRevision3
            }

            // Set minimum text height - use very small default to catch small text
            request.minimumTextHeight = minimumTextHeight > 0 ? minimumTextHeight : 0.01

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Detect text in image file
    func detectTextRegions(
        in imageURL: URL,
        languages: [String] = ["en"],
        useAccurateMode: Bool = true,
        minimumTextHeight: Float = 0.0
    ) async throws -> [CGRect] {
        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw VisionError.imageLoadFailed
        }

        return try await detectTextRegions(
            in: cgImage,
            languages: languages,
            useAccurateMode: useAccurateMode,
            minimumTextHeight: minimumTextHeight
        )
    }

    /// Convert normalized Vision coordinates to pixel coordinates
    /// Vision uses bottom-left origin, we convert to top-left for ffmpeg
    func denormalizeBoxes(
        _ boxes: [CGRect],
        imageWidth: Int,
        imageHeight: Int
    ) -> [CGRect] {
        boxes.map { rect in
            let x = rect.origin.x * CGFloat(imageWidth)
            // Flip Y axis: Vision is bottom-left origin, ffmpeg is top-left
            let y = (1 - rect.origin.y - rect.height) * CGFloat(imageHeight)
            let width = rect.width * CGFloat(imageWidth)
            let height = rect.height * CGFloat(imageHeight)
            return CGRect(x: x, y: y, width: width, height: height)
        }
    }
}
