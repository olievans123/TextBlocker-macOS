import Foundation
import CoreGraphics
import AppKit

/// Perceptual hashing service using difference hash (dHash) algorithm
/// dHash is simpler than pHash but effective for detecting similar frames
struct PerceptualHashService {

    /// Compute difference hash (dHash) for an image
    /// Returns a 64-bit hash that can be compared using Hamming distance
    func computeHash(from cgImage: CGImage) -> UInt64 {
        // 1. Resize to 9x8 grayscale (9 wide to compute 8 horizontal differences)
        guard let resized = resize(cgImage, to: CGSize(width: 9, height: 8)) else {
            return 0
        }

        // 2. Get grayscale pixel values
        let pixels = getGrayscalePixels(resized)
        guard pixels.count == 72 else { return 0 }  // 9 * 8 = 72

        // 3. Compute hash: compare adjacent horizontal pixels
        var hash: UInt64 = 0
        var bit = 63

        for row in 0..<8 {
            for col in 0..<8 {
                let leftPixel = pixels[row * 9 + col]
                let rightPixel = pixels[row * 9 + col + 1]

                if leftPixel > rightPixel {
                    hash |= (1 << bit)
                }
                bit -= 1
            }
        }

        return hash
    }

    /// Compute hash from image file
    func computeHash(from url: URL) -> UInt64 {
        guard let image = NSImage(contentsOf: url),
              let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            return 0
        }
        return computeHash(from: cgImage)
    }

    /// Compute Hamming distance between two hashes
    /// Lower distance = more similar
    func hammingDistance(_ hash1: UInt64, _ hash2: UInt64) -> Int {
        let xor = hash1 ^ hash2
        return xor.nonzeroBitCount
    }

    /// Check if two frames are similar based on threshold
    /// Default threshold of 10 means up to 10 bits can differ (out of 64)
    func areSimilar(_ hash1: UInt64, _ hash2: UInt64, threshold: Int = 10) -> Bool {
        return hammingDistance(hash1, hash2) <= threshold
    }

    // MARK: - Private Helpers

    private func resize(_ image: CGImage, to size: CGSize) -> CGImage? {
        let context = CGContext(
            data: nil,
            width: Int(size.width),
            height: Int(size.height),
            bitsPerComponent: 8,
            bytesPerRow: Int(size.width),
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        )

        guard let ctx = context else { return nil }

        ctx.interpolationQuality = .low
        ctx.draw(image, in: CGRect(origin: .zero, size: size))

        return ctx.makeImage()
    }

    private func getGrayscalePixels(_ image: CGImage) -> [UInt8] {
        let width = image.width
        let height = image.height
        let bytesPerRow = width

        var pixels = [UInt8](repeating: 0, count: width * height)

        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceGray(),
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else {
            return []
        }

        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        return pixels
    }
}
