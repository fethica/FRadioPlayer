//
//  MetadataExtractorTests.swift
//  FRadioPlayerTests
//
//  Characterization tests: these pin the CURRENT behavior of the default
//  metadata extractor, quirks included. If one of these fails after a change,
//  existing users would notice the difference. Change them consciously,
//  not accidentally.
//

import XCTest
import AVFoundation
import FRadioPlayer

final class MetadataExtractorTests: XCTestCase {

    // The default extractor, reached through the public API
    private var extractor: FRadioMetadataExtractor { FRadioPlayer.shared.metadataExtractor }

    private func group(_ value: String) -> AVTimedMetadataGroup {
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierTitle
        item.value = value as NSString
        let range = CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1))
        return AVTimedMetadataGroup(items: [item], timeRange: range)
    }

    func testEmptyGroupsReturnNil() {
        XCTAssertNil(extractor.extract(from: []))
    }

    func testArtistDashTitleSplits() {
        let metadata = extractor.extract(from: [group("Toby Keith - Bullets In The Gun")])
        XCTAssertEqual(metadata?.artistName, "Toby Keith")
        XCTAssertEqual(metadata?.trackName, "Bullets In The Gun")
        XCTAssertEqual(metadata?.rawValue, "Toby Keith - Bullets In The Gun")
        XCTAssertEqual(metadata?.isEmpty, false)
    }

    func testNoSeparatorUsesWholeStringForBoth() {
        // Quirk: without " - ", the whole string becomes artist AND track
        let metadata = extractor.extract(from: [group("StationJingle")])
        XCTAssertEqual(metadata?.artistName, "StationJingle")
        XCTAssertEqual(metadata?.trackName, "StationJingle")
    }

    func testMultipleSeparatorsKeepFirstAndLast() {
        // Quirk: "A - B - C" keeps the first and last parts, drops the middle
        let metadata = extractor.extract(from: [group("A - B - C")])
        XCTAssertEqual(metadata?.artistName, "A")
        XCTAssertEqual(metadata?.trackName, "C")
    }

    func testShoutcastBracketsAreStripped() {
        // Cleaning strips [tags] but leaves the trailing space in front of them
        let metadata = extractor.extract(from: [group("Artist - Song [SC123]")])
        XCTAssertEqual(metadata?.rawValue, "Artist - Song ")
        XCTAssertEqual(metadata?.artistName, "Artist")
        XCTAssertEqual(metadata?.trackName, "Song ")
    }

    func testParenthesesAreStripped() {
        // Quirk: legitimate parentheses like "(Live)" are removed too
        let metadata = extractor.extract(from: [group("Artist - Song (Live)")])
        XCTAssertEqual(metadata?.rawValue, "Artist - Song ")
    }

    func testNonStringValueYieldsEmptyMetadata() {
        // Quirk: a non-string metadata value returns non-nil but empty Metadata
        let item = AVMutableMetadataItem()
        item.identifier = .commonIdentifierTitle
        item.value = NSNumber(value: 42)
        let range = CMTimeRange(start: .zero, duration: CMTime(value: 1, timescale: 1))
        let nonString = AVTimedMetadataGroup(items: [item], timeRange: range)

        let metadata = extractor.extract(from: [nonString])
        XCTAssertNotNil(metadata)
        XCTAssertNil(metadata?.rawValue)
        XCTAssertEqual(metadata?.isEmpty, true)
    }
}
