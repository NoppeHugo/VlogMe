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

    // MARK: - Vlog à plusieurs

    /// Un segment sans `capturedAt` (ancien format) retombe sur `createdAt` pour le tri.
    func testSortDateFallsBackToCreatedAt() {
        let created = Date(timeIntervalSince1970: 1_000)
        let captured = Date(timeIntervalSince1970: 900)
        let legacy = VideoSegment(fileName: "a.mov", durationSeconds: 1, facing: .back, createdAt: created)
        let precise = VideoSegment(fileName: "b.mov", durationSeconds: 1, facing: .back, createdAt: created, capturedAt: captured)
        XCTAssertEqual(legacy.sortDate, created)
        XCTAssertEqual(precise.sortDate, captured)
    }

    /// Les clips de plusieurs participants se remettent dans l'ordre réel de capture,
    /// quel que soit l'ordre d'arrivée (synchro tardive au retour du réseau).
    func testChronologicalMergeAcrossAuthors() {
        let t0 = Date(timeIntervalSince1970: 0)
        let mine1   = VideoSegment(fileName: "m1.mov", durationSeconds: 1, facing: .back, capturedAt: t0.addingTimeInterval(10))
        let theirs1 = VideoSegment(fileName: "t1.mov", durationSeconds: 1, facing: .back, capturedAt: t0.addingTimeInterval(5), authorID: "ami", authorName: "Léa")
        let mine2   = VideoSegment(fileName: "m2.mov", durationSeconds: 1, facing: .back, capturedAt: t0.addingTimeInterval(20))
        let theirs2 = VideoSegment(fileName: "t2.mov", durationSeconds: 1, facing: .back, capturedAt: t0.addingTimeInterval(15), authorID: "ami", authorName: "Léa")

        // Ordre d'arrivée quelconque (les clips de Léa arrivent après coup).
        let merged = [mine1, mine2, theirs1, theirs2].sorted { $0.sortDate < $1.sortDate }
        XCTAssertEqual(merged.map(\.fileName), ["t1.mov", "m1.mov", "t2.mov", "m2.mov"])
    }

    /// Un segment sauvegardé avant la version collaborative (sans les nouvelles clés)
    /// se décode toujours — zéro perte de données à la mise à jour.
    func testVideoSegmentDecodesLegacyJSON() throws {
        let legacyJSON = """
        {
            "id": "\(UUID().uuidString)",
            "fileName": "old.mov",
            "durationSeconds": 3.2,
            "facing": "back",
            "createdAt": 700000000
        }
        """.data(using: .utf8)!
        let segment = try JSONDecoder().decode(VideoSegment.self, from: legacyJSON)
        XCTAssertNil(segment.capturedAt)
        XCTAssertNil(segment.authorID)
        XCTAssertTrue(segment.isMine)
    }

    /// Un brouillon encodé sans les clés de partage se décode en vlog local classique.
    func testVlogDraftDecodesWithoutCollabKeys() throws {
        var draft = VlogDraft(name: "Test")
        draft.isShared = true
        draft.collabZoneName = "vlog-x"
        draft.maxParticipants = 3

        var json = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(draft)
        ) as! [String: Any]
        json.removeValue(forKey: "isShared")
        json.removeValue(forKey: "collabZoneName")
        json.removeValue(forKey: "collabOwnerName")
        json.removeValue(forKey: "maxParticipants")

        let data = try JSONSerialization.data(withJSONObject: json)
        let decoded = try JSONDecoder().decode(VlogDraft.self, from: data)
        XCTAssertFalse(decoded.isShared)
        XCTAssertNil(decoded.collabZoneName)
        XCTAssertEqual(decoded.maxParticipants, 4)
    }
}
