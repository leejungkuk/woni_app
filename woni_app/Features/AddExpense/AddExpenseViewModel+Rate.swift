//
//  AddExpenseViewModel+Rate.swift
//  woni_app
//
//  환율 프리뷰(표시 트랙)와 KRW 저장 필드(저장 트랙) 파생 로직.
//  quote 조회와 generation 가드(fetchRate)는 AddExpenseViewModel.swift에 있다.
//

import Foundation

extension AddExpenseViewModel {
    var baseRatePreview: BaseRatePreview? {
        guard let krwToForeignRate, let convertedBaseAmount else {
            return nil
        }

        let baseCode = baseCurrency.rawValue
        let convertedText = CurrencyFormat.string(
            convertedBaseAmount,
            currencyCode: baseCode
        )
        return BaseRatePreview(
            rateLabel: "\(baseCode) 1.00 = \(selectedCurrency.rawValue) "
                + CurrencyFormat.rateString(krwToForeignRate),
            convertedLabel: "\(baseCode) \(convertedText)"
        )
    }

    var convertedBaseAmount: Decimal? {
        guard let currentQuote,
              let rawKRWAmount = makeRawConvertedKRWAmount(rate: currentQuote.tts),
              let baseKRWPerUnit
        else {
            return nil
        }

        return BaseRateMath.baseDisplayValue(
            krwValue: rawKRWAmount,
            baseKrwPerUnit: baseKRWPerUnit
        )
    }

    var krwToForeignRate: Decimal? {
        guard selectedCurrency != baseCurrency,
              let currentQuote,
              let baseKRWPerUnit,
              let selectedKRWPerUnit = BaseRateMath.krwPerUnit(
                  tts: currentQuote.tts,
                  unit: selectedCurrency.exchangeUnit
              )
        else {
            return nil
        }

        return BaseRateMath.counterRate(
            baseKrwPerUnit: baseKRWPerUnit,
            counterKrwPerUnit: selectedKRWPerUnit
        )
    }

    var isCurrentRateStale: Bool {
        isStale(currentQuote) || (baseCurrency != .krw && isStale(currentBaseQuote))
    }

    var isCurrentRateEstimated: Bool {
        currentQuote?.source == .seed
            || (baseCurrency != .krw && currentBaseQuote?.source == .seed)
    }

    struct PersistedRateFields {
        let appliedRate: Decimal?
        let rateBaseDate: String?
        let krwAmount: Decimal?
    }

    func makePersistedRateFields() -> PersistedRateFields {
        guard selectedCurrency != .krw else {
            return PersistedRateFields(
                appliedRate: nil,
                rateBaseDate: nil,
                krwAmount: amount
            )
        }

        guard let currentQuote else {
            return PersistedRateFields(
                appliedRate: nil,
                rateBaseDate: nil,
                krwAmount: nil
            )
        }

        let krwAmount = makeConvertedBaseAmount(rate: currentQuote.tts)
        let rateBaseDate = currentQuote.baseDate.map {
            ServerDateFormatter.localDate.string(from: $0)
        }

        return PersistedRateFields(
            appliedRate: currentQuote.tts,
            rateBaseDate: rateBaseDate,
            krwAmount: krwAmount
        )
    }
}

private extension AddExpenseViewModel {
    var baseKRWPerUnit: Decimal? {
        guard baseCurrency != .krw else {
            return Decimal(1)
        }
        guard let currentBaseQuote else {
            return nil
        }

        return BaseRateMath.krwPerUnit(
            tts: currentBaseQuote.tts,
            unit: baseCurrency.exchangeUnit
        )
    }

    func makeRawConvertedKRWAmount(rate: Decimal) -> Decimal? {
        guard BaseRateMath.krwPerUnit(
            tts: rate,
            unit: selectedCurrency.exchangeUnit
        ) != nil else {
            return nil
        }

        return NSDecimalNumber(decimal: amount)
            .dividing(by: NSDecimalNumber(decimal: selectedCurrency.exchangeUnit))
            .multiplying(by: NSDecimalNumber(decimal: rate))
            .decimalValue
    }

    func makeConvertedBaseAmount(rate: Decimal) -> Decimal {
        NSDecimalNumber(decimal: amount)
            .dividing(by: NSDecimalNumber(decimal: selectedCurrency.exchangeUnit))
            .multiplying(by: NSDecimalNumber(decimal: rate))
            .decimalValue
            .roundedToTwoFractionDigits
    }

    func isStale(_ quote: RateQuote?) -> Bool {
        quote?.source != .seed && quote?.isStale == true
    }
}
