//
//  ServerMonthProbeTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// 편집할 달을 서버 시각으로 정하는 확인 검증. 봉투 `timestamp` 앞 7자리만 읽고,
/// 읽지 못하거나 요청이 실패하면 달을 돌려주지 않는다 — 기기 달로 대신하지 않는다.
@MainActor
struct ServerMonthProbeTests {
    @Test("봉투 timestamp 의 앞 7자리로 해·달을 읽고, 자산 목록을 기기 캐시 없이 GET 한다")
    func readsYearAndMonthFromTimestamp() async throws {
        let (client, log) = makeStubbedClient { request in
            try URLProtocolStub.response(for: request, body: assetsEnvelope(timestamp: "2026-09-30T21:45:00.123456"))
        }

        let month = try await ServerMonthProbe(client: client).currentMonth()

        #expect(month == ServerMonth(year: 2026, month: 9))
        let request = try #require(log.requests.first)
        #expect(log.requests.count == 1)
        #expect(request.method == "GET")
        #expect(request.url?.path == "/api/v1/assets")
        #expect(request.cachePolicy == .reloadIgnoringLocalCacheData)
        #expect(request.headers["Cache-Control"] == "no-cache")
    }

    @Test("해가 바뀌는 경계에서도 서버가 보낸 해·달 그대로다")
    func readsMonthAtYearBoundary() async throws {
        let cases: [(timestamp: String, expected: ServerMonth)] = [
            ("2026-12-31T23:59:59.999999", ServerMonth(year: 2026, month: 12)),
            ("2027-01-01T00:00:00", ServerMonth(year: 2027, month: 1))
        ]

        for item in cases {
            let month = try await currentMonth(timestamp: item.timestamp)
            #expect(month == item.expected, "\(item.timestamp)")
        }
    }

    @Test("봉투에 timestamp 가 없으면 missingTimestamp 로 실패한다")
    func failsWhenTimestampIsMissing() async {
        await #expect(throws: ServerMonthProbeError.missingTimestamp) {
            try await currentMonth(timestamp: nil)
        }
    }

    @Test("앞 7자리가 ASCII 숫자 yyyy-MM(월 1~12)이 아니면 받은 값을 담아 unreadableTimestamp 로 실패한다")
    func failsOnUnreadableTimestamp() async {
        let timestamps = [
            "",
            "2026-9-30T00:00:00",
            "26-09-30T00:00:00",
            "2026/09/30T00:00:00",
            "2026-13-01T00:00:00",
            "2026-00-10T00:00:00",
            // 부호는 숫자가 아니다 — `Int("+9")` 는 9 로 읽는다.
            "2026-+9-30T00:00:00",
            "２０２６-09-30T00:00:00",
            "٢٠٢٦-09-30T00:00:00"
        ]

        for timestamp in timestamps {
            await #expect(throws: ServerMonthProbeError.unreadableTimestamp(timestamp), "\(timestamp)") {
                try await currentMonth(timestamp: timestamp)
            }
        }
    }

    @Test("전송 실패면 달을 돌려주지 않고 APIClient 의 전송 오류를 그대로 던진다")
    func failsOnTransportError() async {
        let (client, _) = makeStubbedClient { _ in
            throw URLError(.notConnectedToInternet)
        }

        do {
            let month = try await ServerMonthProbe(client: client).currentMonth()
            Issue.record("실패를 기대했지만 \(month) 를 돌려받았다")
        } catch APIError.transport {
            // 기대한 실패
        } catch {
            Issue.record("APIError.transport 를 기대했지만 \(error)")
        }
    }

    @Test("실패 봉투와 봉투 없는 HTTP 500 은 timestamp 가 있어도 달을 돌려주지 않는다")
    func failsOnFailureEnvelope() async {
        let envelopeFailure = await failure(status: 500, body: failureEnvelope("INTERNAL_ERROR"))
        if case let APIError.server(code, _)? = envelopeFailure {
            #expect(code == "INTERNAL_ERROR")
        } else {
            Issue.record("APIError.server 를 기대했지만 \(String(describing: envelopeFailure))")
        }

        let httpFailure = await failure(status: 500, body: "<html>Internal Server Error</html>")
        if case let APIError.httpStatus(code, _)? = httpFailure {
            #expect(code == 500)
        } else {
            Issue.record("APIError.httpStatus 를 기대했지만 \(String(describing: httpFailure))")
        }
    }
}

// MARK: - Helpers

private extension ServerMonthProbeTests {
    func currentMonth(timestamp: String?) async throws -> ServerMonth {
        let (client, _) = makeStubbedClient { request in
            try URLProtocolStub.response(for: request, body: assetsEnvelope(timestamp: timestamp))
        }
        return try await ServerMonthProbe(client: client).currentMonth()
    }

    /// 확인이 실패하면 그 오류를, 달을 돌려받으면 이슈를 남기고 nil.
    func failure(status: Int, body: String) async -> (any Error)? {
        let (client, _) = makeStubbedClient { request in
            try URLProtocolStub.response(for: request, statusCode: status, body: body)
        }
        do {
            let month = try await ServerMonthProbe(client: client).currentMonth()
            Issue.record("실패를 기대했지만 \(month) 를 돌려받았다")
        } catch {
            return error
        }
        return nil
    }
}

// MARK: - Fixtures (백엔드 ApiResponse 봉투 + AssetResponse 배열 모양)

/// 자산 목록 성공 봉투. `timestamp` 가 nil 이면 키를 뺀다.
private func assetsEnvelope(timestamp: String?) -> String {
    let timestampField = timestamp.map { #", "timestamp": "\#($0)""# } ?? ""
    return """
    {"success": true, "code": null, "message": null,
     "data": [{"id": 1, "code": "CASH", "displayNameKo": "현금", "displayNameEn": "Cash", "sortOrder": 1}]\
    \(timestampField)}
    """
}

/// 실패 봉투에도 서버는 timestamp 를 채운다 — 그래서 실패를 달로 읽지 않는지 볼 수 있다.
private func failureEnvelope(_ code: String) -> String {
    """
    {"success": false, "code": "\(code)", "message": "서버 메시지",
     "timestamp": "2026-09-30T21:45:00.123456"}
    """
}
