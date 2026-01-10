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
        languages: [String] = ["en"]
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

                continuation.resume(returning: boxes)
            }

            // Configure for speed over accuracy - we only need boxes
            request.recognitionLevel = .fast
            request.recognitionLanguages = languages
            request.usesLanguageCorrection = false

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
        languages: [String] = ["en"]
    ) async throws -> [CGRect] {
        guard let image = NSImage(contentsOf: imageURL),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            throw VisionError.imageLoadFailed
        }

        return try await detectTextRegions(in: cgImage, languages: languages)
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
