//
//  ExchangeRateServiceTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// ExchangeRateService 요청 경로와 서버 `tts` 응답 매핑을 URLProtocol 스텁으로 검증한다.
@Suite(.serialized)
@MainActor
struct ExchangeRateServiceTests {
    @Test("fetchRates는 /api/v1/exchange-rates path와 date query를 사용한다")
    func fetchRatesUsesV1PathAndDateQuery() async throws {
        let recorder = ExchangeRateRequestRecorder()
        ExchangeRateURLProtocol.handler = { request in
            recorder.record(request)
            return try makeExchangeRateResponse(
                for: request,
                data: Data(
                    """
                    {
                        "success": true,
                        "data": [{
                            "currencyCode": "USD",
                            "currencyName": "미국 달러",
                            "tts": 1387.50,
                            "baseDate": "2026-06-12",
                            "stale": false
                        }]
                    }
                    """.utf8
                )
            )
        }
        defer { ExchangeRateURLProtocol.handler = nil }

        let service = ExchangeRateService(client: makeExchangeRateClient())

        let rates = try await service.fetchRates(on: seoulDate(year: 2026, month: 6, day: 12))

        let request = try #require(recorder.snapshot())
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try #require(components.queryItems)
        #expect(request.method == "GET")
        #expect(url.path == "/api/v1/exchange-rates")
        #expect(queryItems.contains { $0.name == "date" && $0.value == "2026-06-12" })
        #expect(rates.count == 1)
        #expect(rates.first?.currency == .usd)
        #expect(rates.first?.tts == Decimal(string: "1387.50"))
    }

    @Test("fetchRate는 /api/v1/exchange-rates/{currencyCode} path와 date query를 사용한다")
    func fetchRateUsesV1CurrencyPathAndDateQuery() async throws {
        let recorder = ExchangeRateRequestRecorder()
        ExchangeRateURLProtocol.handler = { request in
            recorder.record(request)
            return try makeExchangeRateResponse(
                for: request,
                data: Data(
                    """
                    {
                        "success": true,
                        "data": {
                            "currencyCode": "USD",
                            "currencyName": "미국 달러",
                            "tts": 1387.50,
                            "baseDate": "2026-06-12",
                            "stale": false
                        }
                    }
                    """.utf8
                )
            )
        }
        defer { ExchangeRateURLProtocol.handler = nil }

        let service = ExchangeRateService(client: makeExchangeRateClient())

        let rate = try await service.fetchRate(
            for: .usd,
            on: seoulDate(year: 2026, month: 6, day: 12)
        )

        let request = try #require(recorder.snapshot())
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try #require(components.queryItems)
        #expect(request.method == "GET")
        #expect(url.path == "/api/v1/exchange-rates/USD")
        #expect(queryItems.contains { $0.name == "date" && $0.value == "2026-06-12" })
        #expect(rate.currency == .usd)
        #expect(rate.tts == Decimal(string: "1387.50"))
        #expect(rate.isStale == false)
    }
}

private struct ExchangeRateRecordedRequest {
    let url: URL?
    let method: String?
}

private final class ExchangeRateRequestRecorder {
    private let lock = NSLock()
    private var request: ExchangeRateRecordedRequest?

    func record(_ request: URLRequest) {
        let recordedRequest = ExchangeRateRecordedRequest(
            url: request.url,
            method: request.httpMethod
        )

        lock.lock()
        self.request = recordedRequest
        lock.unlock()
    }

    func snapshot() -> ExchangeRateRecordedRequest? {
        lock.lock()
        defer { lock.unlock() }
        return request
    }
}

private final class ExchangeRateURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: ExchangeRateURLProtocolError.missingHandler)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private enum ExchangeRateURLProtocolError: Error {
    case missingHandler
    case invalidResponse
}

private func makeExchangeRateClient() -> APIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ExchangeRateURLProtocol.self]
    return APIClient(session: URLSession(configuration: configuration))
}

private func makeExchangeRateResponse(
    for request: URLRequest,
    statusCode: Int = 200,
    data: Data
) throws -> (HTTPURLResponse, Data) {
    guard
        let url = request.url,
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )
    else {
        throw ExchangeRateURLProtocolError.invalidResponse
    }
    return (response, data)
}

private func seoulDate(year: Int, month: Int, day: Int) throws -> Date {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = try #require(TimeZone(identifier: "Asia/Seoul"))
    return try #require(calendar.date(from: DateComponents(year: year, month: month, day: day)))
}
