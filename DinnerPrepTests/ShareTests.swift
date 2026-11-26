import CoreImage
import UIKit
import XCTest

final class ShareTests: XCTestCase {
    func testCodeAndMultiBatchBackupRoundTrip() throws {
        let source = (1...45).map { PrepTransferItem(name: "切菜 " + String($0), minutes: $0) }
        let codes = try PrepCode.codes(for: source)
        XCTAssertEqual(codes.count, 2)
        XCTAssertEqual(try PrepCode.decodeFile(Data(codes.joined(separator: "\r\n").utf8)), source)
        XCTAssertTrue(codes[0].hasPrefix("DP1:"))
        XCTAssertFalse(codes[0].contains("="))
        XCTAssertThrowsError(try PrepCode.encode(source))
    }

    func testDecodesCodeEmbeddedInShareText() throws {
        let source = [PrepTransferItem(name: "切肉", minutes: 15)]
        let code = try PrepCode.encode(source)
        XCTAssertEqual(try PrepCode.decode("试试我的备料 " + code + " #开饭倒推"), source)
        XCTAssertThrowsError(try PrepCode.decode("没有口令的一段话"))
    }

    func testRejectsUnknownVersionsMalformedAndUnexpectedFields() throws {
        let payloads = [
            #"[{"name":"Meat","minutes":true}]"#,
            #"[{"name":"Meat","minutes":1.5}]"#,
            #"[{"name":"Meat","minutes":"15"}]"#,
            #"[{"name":"Meat","minutes":15,"date":"today"}]"#,
            #"[{"name":" ","minutes":15}]"#,
            #"[{"name":"Meat","minutes":2881}]"#,
            #"[{"name":"Meat"}]"#,
            "null"
        ]
        for payload in payloads {
            let code = "DP1:" + Data(payload.utf8).base64EncodedString()
                .replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_")
                .replacingOccurrences(of: "=", with: "")
            XCTAssertThrowsError(try PrepCode.decode(code), payload)
        }
        for broken in ["DP2:AAAA", "DP1:ABC=", "DP1:!", "DP1:A", "DP1:" + String(repeating: "a", count: 12_000)] {
            XCTAssertThrowsError(try PrepCode.decode(broken))
        }
    }

    func testPreviewDeduplicatesAndMarksDifferentMinutesAndPartialImport() {
        let existing = [PrepItem(name: "Slice onions", minutes: 8),
                        PrepItem(name: "Cook beans", minutes: 25)]
        let incoming = [PrepTransferItem(name: "slice onions", minutes: 8),
                        PrepTransferItem(name: "Slice onions", minutes: 10),
                        PrepTransferItem(name: "Radishes", minutes: 5)]
        let freePreview = PrepImport(incoming: incoming, existing: existing, hasPro: false)
        XCTAssertEqual(freePreview.rows.map(\.status), [.duplicate, .sameName, .overLimit])
        XCTAssertEqual(freePreview.accepted, [incoming[1]])
        XCTAssertEqual(freePreview.skippedDuplicates, 1)
        XCTAssertEqual(freePreview.skippedLimit, 1)
        XCTAssertEqual(PrepImport(incoming: incoming, existing: existing, hasPro: true).accepted, Array(incoming.dropFirst()))
    }

    func testActualSharePNGsDecodeTheirDownloadCodes() throws {
        let zone = TimeZone(secondsFromGMT: 0)!
        let dinner = Date(timeIntervalSince1970: 1_800_000_000)
        let result = try DinnerMath.calculate(dinner: dinner, recipe: 35, prep: [15], buffer: 5)
        let plan = ShareCard.Content.plan(result, showTimes: false, zone: zone)
        for (content, storeID, expected) in [(plan, "12345678", "https://apps.apple.com/app/id12345678"),
                                              (.milestone, "", ShareCard.previewURL)] {
            let data = try XCTUnwrap(ShareCard.png(for: content, storeID: storeID))
            let image = try XCTUnwrap(CIImage(data: data))
            XCTAssertEqual(image.extent.size, CGSize(width: 1080, height: 1350))
            let detector = try XCTUnwrap(CIDetector(ofType: CIDetectorTypeQRCode, context: nil,
                options: [CIDetectorAccuracy: CIDetectorAccuracyHigh]))
            let messages = detector.features(in: image).compactMap { ($0 as? CIQRCodeFeature)?.messageString }
            XCTAssertEqual(messages, [expected])
        }
    }

    func testTestBundleCanReadLocalizedStrings() {
        XCTAssertNotEqual(L.t("app.name"), "app.name")
        XCTAssertTrue(L.minutes(35).contains("35"))
    }
}
