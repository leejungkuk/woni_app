//
//  BaseRatePreview.swift
//  woni_app
//

import Foundation

/// AddExpense 프리뷰 행이 소비하는 완성 라벨. View는 문자열만 표시한다.
struct BaseRatePreview: Equatable {
    /// 예: "USD 1 = JPY 163.69", "JPY 100 = KRW 874.78"
    let rateLabel: String
    /// 예: "JPY 1,636"
    let convertedLabel: String
    /// 예: "기준일 5월 22일". stale이 아니면 nil이다.
    let staleDateLabel: String?
}
