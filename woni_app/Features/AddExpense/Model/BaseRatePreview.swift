//
//  BaseRatePreview.swift
//  woni_app
//

import Foundation

/// AddExpense 프리뷰 행이 소비하는 완성 라벨. View는 문자열만 표시한다.
struct BaseRatePreview: Equatable {
    /// 예: "JPY 1.00 = USD 0.006109"
    let rateLabel: String
    /// 예: "JPY 1,636"
    let convertedLabel: String
}
