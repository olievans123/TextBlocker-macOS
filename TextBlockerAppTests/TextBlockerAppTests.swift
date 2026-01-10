import CoreGraphics
import XCTest

@testable import TextBlockerApp

final class TextBlockerAppTests: XCTestCase {
    func testTextRegionFFmpegFilterFormatting() {
        let region = TextRegion(
            box: CGRect(x: 10, y: 20, width: 100, height: 50),
            startTime: 1.0,
            endTime: 2.5
        )

        let filter = region.toFFmpegFilter(padding: 5, scale: 1.0)

        XCTAssertTrue(filter.contains("drawbox=x=5:y=15:w=110:h=60"))
        XCTAssertTrue(filter.contains("between(t,1.00,3.00)"))
    }

    func testTextRegionOverlapAndMerge() {
        let regionA = TextRegion(
            box: CGRect(x: 0, y: 0, width: 10, height: 10),
            startTime: 0,
            endTime: 1
        )
        var regionB = TextRegion(
            box: CGRect(x: 9, y: 9, width: 5, height: 5),
            startTime: 0.5,
            endTime: 2
        )

        XCTAssertTrue(regionA.overlaps(with: regionB))
        regionB.merge(with: regionA)
        XCTAssertEqual(regionB.box.minX, 0)
        XCTAssertEqual(regionB.box.minY, 0)
        XCTAssertEqual(regionB.startTime, 0)
        XCTAssertEqual(regionB.endTime, 2)
    }

    func testProcessingJobOverallProgressMapping() {
        let job = ProcessingJob(
            inputURL: URL(fileURLWithPath: "/tmp/video.mp4"),
            type: .localFile
        )

        job.status = .downloading(progress: 0.5)
        XCTAssertEqual(job.status.overallProgress, 0.05, accuracy: 0.0001)

        job.status = .extracting(progress: 0.5)
        XCTAssertEqual(job.status.overallProgress, 0.215, accuracy: 0.0001)

        job.status = .detecting(progress: 0.5)
        XCTAssertEqual(job.status.overallProgress, 0.495, accuracy: 0.0001)

        job.status = .encoding(progress: 0.5)
        XCTAssertEqual(job.status.overallProgress, 0.83, accuracy: 0.0001)
    }

    func testPerceptualHashHammingDistance() {
        let hasher = PerceptualHashService()
        XCTAssertEqual(hasher.hammingDistance(UInt64(0b1010), UInt64(0b0011)), 2)
        XCTAssertTrue(hasher.areSimilar(UInt64(0b1111), UInt64(0b1110), threshold: 1))
        XCTAssertFalse(hasher.areSimilar(UInt64(0b1111), UInt64(0b0000), threshold: 1))
    }
}
