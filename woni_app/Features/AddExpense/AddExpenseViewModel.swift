import Foundation
import Observation
import SwiftUI

@Observable
final class AddExpenseViewModel {
    var selectedTab: WoniSegmentTabs.Tab = .expense {
        didSet {
            if selectedTab == .expense {
                selectedMethod = .creditCard
            } else {
                selectedMethod = .cash
            }
        }
    }

    var amount: Decimal = 0
    var selectedCurrency: SelectableCurrency = .krw
    var selectedExpenseCategory: ExpenseCategory? = .travel
    var selectedIncomeCategory: IncomeCategory? = .salary
    var selectedMethod: PaymentMethod? = .creditCard
    var memo: String = ""
    var date: Date = .init()

    var currentRate: Decimal?

    private let exchangeRateService = ExchangeRateService()

    var palette: AccentPalette {
        selectedTab == .expense ? .terracotta : .olive
    }

    init() {
        Task {
            await fetchRate()
        }
    }

    func fetchRate() async {
        guard let exchangeCode = selectedCurrency.exchangeCode else {
            await MainActor.run {
                self.currentRate = nil
            }
            return
        }

        do {
            let rateData = try await exchangeRateService.fetchRate(for: exchangeCode, on: date)
            await MainActor.run {
                self.currentRate = rateData.dealBasRate
            }
        } catch {
            await MainActor.run {
                self.currentRate = nil
            }
        }
    }

    func updateCurrency(_ newCurrency: SelectableCurrency) {
        selectedCurrency = newCurrency
        Task {
            await fetchRate()
        }
    }

    var convertedBaseAmount: Decimal? {
        guard let rate = currentRate else { return nil }
        // TODO: Backend dealBasRate 단위 의미 확인 전까지 1:1로 처리. JPY 등 100단위 통화 오차 가능 (환율 스케일 per-100 보정 필요)
        return amount * rate
    }

    var krwToForeignRate: Decimal? {
        guard let rate = currentRate, rate > 0 else { return nil }
        let krwDecimal = NSDecimalNumber(decimal: 1)
        let rateDecimal = NSDecimalNumber(decimal: rate)
        let result = krwDecimal.dividing(by: rateDecimal)
        return result.decimalValue
    }

    func save(onSave: (ExpenseDraft) -> Void) {
        let draft = ExpenseDraft(
            amount: amount,
            currencyCode: selectedCurrency.rawValue,
            date: date,
            category: selectedTab == .expense ? selectedExpenseCategory : nil,
            paymentMethod: selectedMethod,
            memo: memo
        )
        onSave(draft)
    }
}
