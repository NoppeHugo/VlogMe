import XCTest
@testable import VlogMe

/// Tests unitaires « purs » (sans device ni système de fichiers) pour la logique de base.
final class VlogMeTests: XCTestCase {

    func testAspectRatioRenderSizes() {
        XCTAssertEqual(AspectRatio.vertical.renderSize, CGSize(width: 1080, height: 1920))
        XCTAssertEqual(AspectRatio.horizontal.renderSize, CGSize(width: 1920, height: 1080))
    }

    func testAspectRatioToggle() {
        var ratio = AspectRatio.vertical
        ratio.toggle()
        XCTAssertEqual(ratio, .horizontal)
        ratio.toggle()
        XCTAssertEqual(ratio, .vertical)
    }

    func testCameraFacingToggle() {
        var facing = CameraFacing.back
        facing.toggle()
        XCTAssertEqual(facing, .front)
        XCTAssertEqual(facing.avPosition, .front)
    }

    func testVideoSegmentCodableRoundTrip() throws {
        let segment = VideoSegment(
            fileName: "abc.mov",
            durationSeconds: 12.5,
            facing: .front
        )
        let data = try JSONEncoder().encode(segment)
        let decoded = try JSONDecoder().decode(VideoSegment.self, from: data)
        XCTAssertEqual(decoded, segment)
    }
}
