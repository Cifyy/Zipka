//
//  TransitDataTests.swift
//  ZipkaTests
//

import Foundation
import Testing
@testable import Zipka

struct CSVParserTests {
    private func parse(_ text: String, chunkSize: Int = 3) throws -> [[String]] {
        let parser = CSVParser()
        var rows: [[String]] = []
        let onRecord: (CSVRecord) throws -> Void = { record in
            rows.append((0..<record.count).map { record.string($0) })
        }
        let bytes = Array(text.utf8)
        // Feed in small chunks so records and quoted fields get split across chunk boundaries.
        var offset = 0
        while offset < bytes.count {
            let end = min(offset + chunkSize, bytes.count)
            try bytes[offset..<end].withUnsafeBytes { try parser.consume($0, onRecord) }
            offset = end
        }
        try parser.finish(onRecord)
        return rows
    }

    @Test func parsesQuotedFieldsAcrossChunks() throws {
        let rows = try parse("\u{FEFF}stop_id,stop_name\r\n1,\"AKF / PK\"\r\n2,\"Say \"\"hi\"\", ok\"\n\n3,plain")
        #expect(rows == [
            ["stop_id", "stop_name"],
            ["1", "AKF / PK"],
            ["2", "Say \"hi\", ok"],
            ["3", "plain"],
        ])
    }

    @Test func parsesNumbersAndTimes() throws {
        let parser = CSVParser()
        var checked = false
        let bytes = Array("50.08829,-19.9,25:07:30,42,7.1234567\n".utf8)
        try bytes.withUnsafeBytes { buffer in
            try parser.consume(buffer) { record in
                #expect(record.microdegrees(0) == 50_088_290)
                #expect(record.microdegrees(1) == -19_900_000)
                #expect(record.gtfsTime(2) == 25 * 3600 + 7 * 60 + 30)
                #expect(record.int(3) == 42)
                #expect(record.microdegrees(4) == 7_123_457)
                #expect(record.int(9) == nil)
                checked = true
            }
        }
        #expect(checked)
    }

    @Test func fillsMissingStopTimes() {
        #expect(GTFSDatabase.fillMissingTimes([nil, 100, nil, nil, 400, nil]) == [100, 100, 200, 300, 400, 400])
    }
}

struct TripTimetableTests {
    private let zone = TimeZone(identifier: "Europe/Warsaw")!

    private func date(_ hour: Int, _ minute: Int, day: Int = 17) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        return calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    private func stop(_ sequence: Int, _ id: String, _ seconds: Int) -> TripStop {
        TripStop(sequence: sequence, stopID: id, name: id, latitude: 0, longitude: 0, arrival: seconds, departure: seconds)
    }

    private var detail: TripDetail {
        let summary = TripSummary(tripID: "t", routeID: "r", lineNumber: "52", headsign: "End", directionID: 0, shapeID: nil)
        return TripDetail(summary: summary, stops: [
            stop(1, "a", 11 * 3600),
            stop(2, "b", 11 * 3600 + 120),
            stop(3, "c", 11 * 3600 + 300),
        ], shape: [])
    }

    @Test func usesScheduleWithoutRealtime() {
        let now = date(11, 1)
        let timed = TripTimetable.timedStops(for: detail, realtime: nil, now: now)
        #expect(timed.map(\.expected) == [date(11, 0), date(11, 2), date(11, 5)])
        #expect(timed.allSatisfy { !$0.isRealtime })

        let upcoming = TripTimetable.upcomingStops(timed, currentStopSequence: nil, now: now)
        #expect(upcoming.map(\.stop.sequence) == [2, 3])
    }

    @Test func propagatesRealtimeDelayToLaterStops() {
        let realtime = TripRealtimeUpdate(tripID: "t", stopTimes: [
            .init(stopSequence: nil, stopID: "b", arrival: nil, departure: date(11, 4), delay: 120, isSkipped: false),
        ], delay: nil)
        let timed = TripTimetable.timedStops(for: detail, realtime: realtime, now: date(11, 3))
        #expect(timed[1].expected == date(11, 4))
        #expect(timed[2].expected == date(11, 7))
        #expect(timed[2].delay == 120)
        #expect(timed[2].isRealtime)
    }

    @Test func followsVehicleReportedStop() {
        let timed = TripTimetable.timedStops(for: detail, realtime: nil, now: date(10, 50))
        let upcoming = TripTimetable.upcomingStops(timed, currentStopSequence: 3, now: date(10, 50))
        #expect(upcoming.map(\.stop.sequence) == [3])
    }

    @Test func picksPreviousServiceDayForTripsAfterMidnight() {
        // A trip scheduled at 24:30 on the 16th runs at 00:30 on the 17th.
        let stops = [stop(1, "a", 24 * 3600 + 30 * 60)]
        let start = TripTimetable.serviceDayStart(for: stops, now: date(0, 25))
        #expect(start == date(0, 0, day: 16))
    }
}
