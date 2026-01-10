import Foundation
import CoreGraphics

/// A detected text region with its time range
struct TextRegion: Identifiable, Equatable {
    let id = UUID()
    var box: CGRect
    var startTime: Double
    var endTime: Double

    /// Duration this region is visible
    var duration: Double {
        endTime - startTime
    }

    /// Check if this region overlaps with another (within padding)
    func overlaps(with other: TextRegion, padding: CGFloat = 0) -> Bool {
        let paddedBox = box.insetBy(dx: -padding, dy: -padding)
        let otherPaddedBox = other.box.insetBy(dx: -padding, dy: -padding)
        return paddedBox.intersects(otherPaddedBox)
    }

    /// Merge with another region, expanding the box and time range
    mutating func merge(with other: TextRegion) {
        box = box.union(other.box)
        startTime = min(startTime, other.startTime)
        endTime = max(endTime, other.endTime)
    }

    /// Generate ffmpeg drawbox filter string
    func toFFmpegFilter(padding: Int, scale: Double) -> String {
        let x = max(0, Int(box.origin.x * scale) - padding)
        let y = max(0, Int(box.origin.y * scale) - padding)
        let w = Int(box.width * scale) + (padding * 2)
        let h = Int(box.height * scale) + (padding * 2)

        let enable = "between(t,\(String(format: "%.2f", startTime)),\(String(format: "%.2f", endTime + 0.5)))"

        return "drawbox=x=\(x):y=\(y):w=\(w):h=\(h):color=black:t=fill:enable='\(enable)'"
    }
}

/// Frame detection result
struct FrameDetection {
    let frameIndex: Int
    let timestamp: Double
    let boxes: [CGRect]
    let hash: UInt64
}
