@testable import NestlyCore
import XCTest

private actor Counter {
    var value = 0
    func next() -> Int {
        value += 1
        return value
    }
}

private struct Offline: Error {}

final class RefetchTests: XCTestCase {
    private func nextValue<T: Sendable>(_ iterator: inout AsyncStream<T>.Iterator) async -> T? {
        await iterator.next()
    }

    func testFailedRefetchKeepsLastGoodValueInsteadOfEmittingEmpty() async {
        let bus = RefreshBus()
        let errors = await DataErrors()
        let counter = Counter()
        let stream = refetch([.profile], bus: bus, errors: errors) { () async throws -> [String] in
            let attempt = await counter.next()
            if attempt == 2 { throw Offline() }
            return ["child-\(attempt)"]
        }
        var it = stream.makeAsyncIterator()
        let first = await it.next()
        XCTAssertEqual(first, ["child-1"])
        bus.bump(.profile)
        let second = await it.next()
        XCTAssertEqual(second, ["child-1"])
        let message = await errors.message
        let expected = await DataErrors.defaultMessage
        XCTAssertEqual(message, expected)
        bus.bump(.profile)
        let third = await it.next()
        XCTAssertEqual(third, ["child-3"])
        let cleared = await errors.message
        XCTAssertNil(cleared)
    }

    func testTimeoutDoesNotBlameTheDeviceConnection() async {
        let errors = await DataErrors()
        await errors.report(URLError(.timedOut))
        let message = await errors.message
        let offline = await errors.offline
        let expected = await DataErrors.defaultMessage
        XCTAssertEqual(message, expected)
        XCTAssertFalse(offline)
    }

    func testMissingDeviceConnectionIsCalledOffline() async {
        let errors = await DataErrors()
        await errors.report(URLError(.notConnectedToInternet))
        let message = await errors.message
        let offline = await errors.offline
        let expected = await DataErrors.offlineMessage
        XCTAssertEqual(message, expected)
        XCTAssertTrue(offline)
    }

    func testFailedFirstFetchEmitsNothingUntilARefetchSucceeds() async throws {
        let bus = RefreshBus()
        let errors = await DataErrors()
        let counter = Counter()
        let stream = refetch([.profile], bus: bus, errors: errors) { () async throws -> [String] in
            let attempt = await counter.next()
            if attempt == 1 { throw Offline() }
            return ["child-\(attempt)"]
        }
        let received = ValueBox<[String]>()
        let consumer = Task {
            for await value in stream { await received.append(value) }
        }
        try await Task.sleep(nanoseconds: 200_000_000)
        let early = await received.values
        XCTAssertTrue(early.isEmpty)

        bus.bump(.profile)
        for _ in 0..<50 where await received.values.isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        let values = await received.values
        XCTAssertEqual(values, [["child-2"]])
        consumer.cancel()
    }

    func testTickDuringFetchDoesNotCancelTheRequest() async {
        let bus = RefreshBus()
        let errors = await DataErrors()
        let counter = Counter()
        let stream = refetch([.activity], bus: bus, errors: errors) { () async throws -> String in
            let calls = await counter.next()
            if calls == 1 { bus.bump(.activity) }
            return "v\(calls)"
        }
        var it = stream.makeAsyncIterator()
        let a = await it.next()
        let b = await it.next()
        XCTAssertEqual([a, b], ["v1", "v2"])
        let calls = await counter.value
        XCTAssertEqual(calls, 2)
    }

    func testOtherTablesDoNotTrigger() async throws {
        let bus = RefreshBus()
        let errors = await DataErrors()
        let counter = Counter()
        let stream = refetch([.note], bus: bus, errors: errors) { await counter.next() }
        let consumer = Task { for await _ in stream {} }
        try await Task.sleep(nanoseconds: 100_000_000)
        bus.bump(.activity)
        try await Task.sleep(nanoseconds: 100_000_000)
        let calls = await counter.value
        XCTAssertEqual(calls, 1)
        consumer.cancel()
    }
}

private actor ValueBox<T: Sendable> {
    var values: [T] = []
    func append(_ v: T) { values.append(v) }
}
