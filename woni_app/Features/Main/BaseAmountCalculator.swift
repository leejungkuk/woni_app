//
//  BaseAmountCalculator.swift
//  woni_app
//

import Foundation

enum BaseAmountCalculator {
    static func baseAmount(
        for transaction: LocalTransaction,
        baseCurrency: SelectableCurrency,
        baseTTSByDate: [String: Decimal],
        rateProvider: RateProvider
    ) -> Decimal? {
        if transaction.currencyCode == baseCurrency.rawValue {
            return transaction.amount
        }

        if let krwAmount = transaction.krwAmount {
            return displayValue(
                krwValue: krwAmount,
                baseCurrency: baseCurrency,
                transactionDate: transaction.transactionDate,
                baseTTSByDate: baseTTSByDate
            )
        }

        guard let currency = SelectableCurrency(rawValue: transaction.currencyCode),
              let rate = rateProvider.rate(for: currency, on: transaction.transactionDate),
              let transactionKrwPerUnit = BaseRateMath.krwPerUnit(
                  tts: rate,
                  unit: currency.exchangeUnit
              )
        else {
            return nil
        }

        let roundedKRWValue = NSDecimalNumber(decimal: transaction.amount)
            .multiplying(by: NSDecimalNumber(decimal: transactionKrwPerUnit))
            .decimalValue
            .roundedToTwoFractionDigits
        return displayValue(
            krwValue: roundedKRWValue,
            baseCurrency: baseCurrency,
            transactionDate: transaction.transactionDate,
            baseTTSByDate: baseTTSByDate
        )
    }

    static func displayValue(
        krwValue: Decimal,
        baseCurrency: SelectableCurrency,
        transactionDate: String,
        baseTTSByDate: [String: Decimal]
    ) -> Decimal? {
        guard baseCurrency != .krw else {
            return krwValue
        }
        guard let baseKrwPerUnit = baseKrwPerUnit(
            baseCurrency: baseCurrency,
            transactionDate: transactionDate,
            baseTTSByDate: baseTTSByDate
        ) else {
            return nil
        }
        return BaseRateMath.baseDisplayValue(
            krwValue: krwValue,
            baseKrwPerUnit: baseKrwPerUnit
        )
    }

    static func baseKrwPerUnit(
        baseCurrency: SelectableCurrency,
        transactionDate: String,
        baseTTSByDate: [String: Decimal]
    ) -> Decimal? {
        if baseCurrency == .krw {
            return Decimal(1)
        }
        guard let tts = baseTTSByDate[transactionDate] else {
            return nil
        }
        return BaseRateMath.krwPerUnit(tts: tts, unit: baseCurrency.exchangeUnit)
    }
}
