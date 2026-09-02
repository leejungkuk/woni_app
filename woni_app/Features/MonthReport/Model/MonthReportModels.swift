//
//  MonthReportModels.swift
//  woni_app
//

import Foundation

enum ReportSortField: Equatable {
    case date
    case amount
}

struct ReportCategoryItem: Identifiable, Equatable {
    let categoryID: Int
    /// 표시명 해석은 ViewModel 책임 — Aggregator는 대표 스냅샷까지만 만든다.
    let categorySnapshot: String?
    let amount: Decimal
    /// 단순 반올림 정수 퍼센트. 총합 0이면 0. 0 초과 1% 미만은 1.
    let percent: Int
    /// 금액 내림차순 rank(0부터). 색 팔레트 인덱스로 쓰인다 — 순환은 View에서 % 10.
    let colorRank: Int

    var id: Int {
        categoryID
    }
}

struct ReportDonutSlice: Equatable {
    let categoryID: Int
    let start: Double
    let end: Double

    var midAngleFraction: Double {
        (start + end) / 2
    }
}

struct ReportEntryRow: Identifiable, Equatable {
    let id: UUID
    let transactionDate: String
    let amount: Decimal
    let memo: String?
}
