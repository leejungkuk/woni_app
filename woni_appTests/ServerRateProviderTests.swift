//
//  ServerRateProviderTests.swift
//  woni_appTests
//

import Foundation
import Testing
@testable import woni_app

/// ServerRateProvider의 서버 우선 조회·시드 폴백·nil 정책과 RateQuote 매핑을 URLProtocol 스텁으로 검증한다.
@Suite(.serialized)
@MainActor
struct ServerRateProviderTests {
    @Test("RateQuote는 화면용 환율 필드를 Decimal과 Optional Date로 보존한다")
    func rateQuoteCarriesDisplayFields() throws {
        let tts = try #require(Decimal(string: "1411.23"))
        let baseDate = try seoulDate(year: 2026, month: 7, day: 15)

        let quote = RateQuote(
            tts: tts,
            baseDate: baseDate,
            isStale: true,
            source: .server
        )

        #expect(quote.tts == tts)
        #expect(quote.baseDate == baseDate)
        #expect(quote.isStale)
        #expect(quote.source == .server)
    }

    @Test("ServerRateProvider는 서버 성공 시 server quote 필드를 그대로 매핑한다")
    func serverRateProviderReturnsServerQuoteWhenServerSucceeds() async throws {
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
                            "tts": 1411.23,
                            "baseDate": "2026-07-15",
                            "stale": true
                        }
                    }
                    """.utf8
                )
            )
        }
        defer { ExchangeRateURLProtocol.handler = nil }

        let provider = ServerRateProvider(
            service: ExchangeRateService(client: makeExchangeRateClient()),
            seedRateProvider: RateProvider(seedData: emptyRateSeedData())
        )

        let quote = try #require(
            await provider.quote(for: .usd, on: seoulDate(year: 2026, month: 7, day: 16))
        )
        let request = try #require(recorder.snapshot())
        let url = try #require(request.url)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let queryItems = try #require(components.queryItems)

        #expect(request.method == "GET")
        #expect(url.path == "/api/v1/exchange-rates/USD")
        #expect(queryItems.contains { $0.name == "date" && $0.value == "2026-07-16" })
        #expect(quote.tts == Decimal(string: "1411.23"))
        #expect(try quote.baseDate == seoulDate(year: 2026, month: 7, day: 15))
        #expect(quote.isStale)
        #expect(quote.source == .server)
    }

    @Test("ServerRateProvider는 서버 오류 유형과 무관하게 시드 quote로 폴백한다")
    func serverRateProviderFallsBackToSeedQuoteForServerErrors() async throws {
        defer { ExchangeRateURLProtocol.handler = nil }

        for scenario in ExchangeRateFailureScenario.allCases {
            let fallbackRecorder = ServerRateProviderFallbackRecorder()
            ExchangeRateURLProtocol.handler = { request in
                try scenario.response(for: request)
            }

            let seedData = try seedDataWithUSDSeedRate()
            let provider = ServerRateProvider(
                service: ExchangeRateService(client: makeExchangeRateClient()),
                seedRateProvider: RateProvider(seedData: seedData),
                onFallback: fallbackRecorder.record
            )

            let date = try seoulDate(year: 2026, month: 7, day: 3)
            let quote = try #require(
                await provider.quote(for: .usd, on: date)
            )

            #expect(quote.tts == Decimal(string: "1400.00"))
            #expect(try quote.baseDate == seoulDate(year: 2026, month: 7, day: 2))
            #expect(quote.isStale == false)
            #expect(quote.source == .seed)
            #expect(
                fallbackRecorder.snapshot() == [
                    ServerRateProviderFallbackSnapshot(currency: .usd, localDate: "2026-07-03")
                ]
            )
        }
    }

    @Test("ServerRateProvider는 서버와 시드 모두 없으면 nil을 반환한다")
    func serverRateProviderReturnsNilWhenServerAndSeedHaveNoQuote() async throws {
        let fallbackRecorder = ServerRateProviderFallbackRecorder()
        ExchangeRateURLProtocol.handler = { request in
            try makeExchangeRateResponse(
                for: request,
                data: Data(
                    """
                    {
                        "success": false,
                        "code": "RATE_NOT_FOUND",
                        "data": null,
                        "message": "rate not found"
                    }
                    """.utf8
                )
            )
        }
        defer { ExchangeRateURLProtocol.handler = nil }

        let seedData = try seedDataWithUSDSeedRate()
        let provider = ServerRateProvider(
            service: ExchangeRateService(client: makeExchangeRateClient()),
            seedRateProvider: RateProvider(seedData: seedData),
            onFallback: fallbackRecorder.record
        )

        let quote = try await provider.quote(for: .cny, on: seoulDate(year: 2026, month: 7, day: 3))

        #expect(quote == nil)
        #expect(
            fallbackRecorder.snapshot() == [
                ServerRateProviderFallbackSnapshot(currency: .cny, localDate: "2026-07-03")
            ]
        )
    }

    @Test("ServerRateProvider는 base 통화를 서버 호출 없이 tts 1 quote로 반환한다")
    func serverRateProviderReturnsBaseCurrencyQuoteWithoutServerLookup() async throws {
        let requestRecorder = ExchangeRateRequestRecorder()
        let fallbackRecorder = ServerRateProviderFallbackRecorder()
        ExchangeRateURLProtocol.handler = { request in
            requestRecorder.record(request)
            throw ExchangeRateTransportFailure()
        }
        defer { ExchangeRateURLProtocol.handler = nil }

        let provider = ServerRateProvider(
            service: ExchangeRateService(client: makeExchangeRateClient()),
            seedRateProvider: RateProvider(seedData: emptyRateSeedData()),
            onFallback: fallbackRecorder.record
        )

        let quote = try #require(
            await provider.quote(for: .krw, on: seoulDate(year: 2026, month: 7, day: 3))
        )

        #expect(quote.tts == Decimal(1))
        #expect(quote.baseDate == nil)
        #expect(quote.isStale == false)
        #expect(quote.source == .server)
        #expect(requestRecorder.snapshot() == nil)
        #expect(fallbackRecorder.snapshot().isEmpty)
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

private enum ExchangeRateFailureScenario: CaseIterable {
    case transport
    case httpStatus
    case emptyResponse
    case decoding
    case server

    func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        switch self {
        case .transport:
            throw ExchangeRateTransportFailure()
        case .httpStatus:
            return try makeExchangeRateResponse(
                for: request,
                statusCode: 503,
                data: Data(
                    """
                    {
                        "success": true,
                        "data": {
                            "currencyCode": "USD",
                            "currencyName": "미국 달러",
                            "tts": 1411.23,
                            "baseDate": "2026-07-15",
                            "stale": false
                        }
                    }
                    """.utf8
                )
            )
        case .emptyResponse:
            return try makeExchangeRateResponse(for: request, data: Data())
        case .decoding:
            return try makeExchangeRateResponse(for: request, data: Data("not-json".utf8))
        case .server:
            return try makeExchangeRateResponse(
                for: request,
                data: Data(
                    """
                    {
                        "success": false,
                        "code": "RATE_UNAVAILABLE",
                        "data": null,
                        "message": "rate unavailable"
                    }
                    """.utf8
                )
            )
        }
    }
}

private struct ExchangeRateTransportFailure: Error {}

private struct ServerRateProviderFallbackSnapshot: Equatable {
    let currency: SelectableCurrency
    let localDate: String
}

private final class ServerRateProviderFallbackRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [ServerRateProviderFallbackSnapshot] = []

    func record(currency: SelectableCurrency, localDate: String) {
        lock.lock()
        snapshots.append(ServerRateProviderFallbackSnapshot(currency: currency, localDate: localDate))
        lock.unlock()
    }

    func snapshot() -> [ServerRateProviderFallbackSnapshot] {
        lock.lock()
        defer { lock.unlock() }
        return snapshots
    }
}

private func makeExchangeRateClient() -> APIClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ExchangeRateURLProtocol.self]
    return APIClient(session: URLSession(configuration: configuration), token: { nil })
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

private func emptyRateSeedData() -> SeedData {
    SeedData(exchangeRates: [], expenseCategories: [], incomeCategories: [], assets: [])
}

private func seedDataWithUSDSeedRate() throws -> SeedData {
    try SeedData(
        exchangeRates: [
            SeedExchangeRate(
                currencyCode: .usd,
                currencyName: "미국 달러",
                tts: #require(Decimal(string: "1400.00")),
                baseDate: "2026-07-02",
                stale: false
            )
        ],
        expenseCategories: [],
        incomeCategories: [],
        assets: []
    )
}
