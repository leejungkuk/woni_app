//
//  AddExpenseViewModel+Rate.swift
//  woni_app
//
//  환율 프리뷰(표시 트랙)와 KRW 저장 필드(저장 트랙) 파생 로직.
//  quote 조회와 generation 가드(fetchRate)는 AddExpenseViewModel.swift에 있다.
//

import Foundation

extension AddExpenseViewModel {
    func baseRatePreview(language: AppLanguage) -> BaseRatePreview? {
        guard let selectedToBaseRate, let convertedBaseAmount else {
            return nil
        }

        let baseCode = baseCurrency.rawValue
        let convertedText = CurrencyFormat.string(
            convertedBaseAmount,
            currencyCode: baseCode
        )
        return BaseRatePreview(
            rateLabel: CurrencyFormat.rateLabel(
                quoteCurrencyCode: selectedCurrency.rawValue,
                baseCurrencyCode: baseCode,
                basePerQuoteUnit: selectedToBaseRate
            ),
            convertedLabel: "\(baseCode) \(convertedText)",
            staleDateLabel: staleDateLabel(language: language)
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

    var selectedToBaseRate: Decimal? {
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
            numeratorKrwPerUnit: selectedKRWPerUnit,
            denominatorKrwPerUnit: baseKRWPerUnit
        )
    }

    var isCurrentRateStale: Bool {
        currentStaleQuote != nil
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

    var currentStaleQuote: RateQuote? {
        if isStale(currentQuote) {
            return currentQuote
        }
        if baseCurrency != .krw, isStale(currentBaseQuote) {
            return currentBaseQuote
        }
        return nil
    }

    func staleDateLabel(language: AppLanguage) -> String? {
        guard let currentStaleQuote else {
            return nil
        }

        guard let baseDate = currentStaleQuote.baseDate else {
            return WoniStrings.ratePreviewStale(language)
        }
        return WoniStrings.ratePreviewStale(
            language,
            baseDate: WoniDateFormat.monthDay(baseDate, language: language)
        )
    }
}
