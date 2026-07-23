//
//  ExchangeRateService.swift
//  woni_app
//

import Foundation

/// 환율 조회 API. 백엔드 `/api/v1/exchange-rates` 계약에 대응한다.
struct ExchangeRateService {
    private let client: APIClient

    init(client: APIClient = APIClient()) {
        self.client = client
    }

    /// 특정 날짜의 전체 통화 환율. `GET /api/v1/exchange-rates?date=yyyy-MM-dd`
    func fetchRates(on date: Date) async throws -> [ExchangeRate] {
        let query = [URLQueryItem(name: "date", value: ServerDateFormatter.localDate.string(from: date))]
        let dtos: [ExchangeRateDTO] = try await client.get("/api/v1/exchange-rates", query: query)
        return dtos.map { $0.toDomain() }
    }

    /// 특정 날짜 기준 as-of 전 통화 환율.
    /// `GET /api/v1/exchange-rates/snapshot?date=yyyy-MM-dd`
    func fetchSnapshot(on date: Date) async throws -> [ExchangeRate] {
        let query = [URLQueryItem(name: "date", value: ServerDateFormatter.localDate.string(from: date))]
        let dtos: [ExchangeRateDTO] = try await client.get(
            "/api/v1/exchange-rates/snapshot",
            query: query
        )
        return dtos.map { $0.toDomain() }
    }

    /// 특정 통화 환율. `date` 생략 시 최신, 지정 시 해당일(주말/공휴일은 직전 영업일 fallback).
    /// `GET /api/v1/exchange-rates/{currencyCode}`
    func fetchRate(for currency: CurrencyCode, on date: Date? = nil) async throws -> ExchangeRate {
        let query = date.map {
            [URLQueryItem(name: "date", value: ServerDateFormatter.localDate.string(from: $0))]
        } ?? []
        let dto: ExchangeRateDTO = try await client.get(
            "/api/v1/exchange-rates/\(currency.rawValue)",
            query: query
        )
        return dto.toDomain()
    }
}
