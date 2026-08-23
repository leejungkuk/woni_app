//
//  MainViewModel+Display.swift
//  woni_app
//
//  displaySnapshot에 담길 표시 산출물(요약·캘린더·내역 행)과 base 환산 포매터.
//  스냅샷 커밋·generation 가드는 MainViewModel.swift의 load 파이프라인에 있다.
//

import Foundation

extension MainViewModel {
    func makeDisplaySnapshot(
        baseCurrency: SelectableCurrency,
        baseTTSByDate: [String: Decimal],
        transactions: [LocalTransaction],
        outOfMonthTransactions: [LocalTransaction]
    ) -> MainDisplaySnapshot {
        let dailyResult = dailySummaries(
            from: transactions,
            baseCurrency: baseCurrency,
            baseTTSByDate: baseTTSByDate
        )
        return MainDisplaySnapshot(
            baseCurrency: baseCurrency,
            baseTTSByDate: baseTTSByDate,
            transactions: transactions,
            outOfMonthTransactions: outOfMonthTransactions,
            summary: monthlySummary(from: dailyResult.summaries.values),
            calendarDays: makeCalendarDays(dailySummaries: dailyResult.summaries),
            historyRows: makeHistoryRows(
                transactions: transactions + outOfMonthTransactions,
                baseCurrency: baseCurrency,
                baseTTSByDate: baseTTSByDate
            ),
            hasUnconvertedTransactions: dailyResult.hasUnconvertedTransactions
        )
    }

    static func dateString(from date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return dateString(
            year: components.year ?? 1970,
            month: components.month ?? 1,
            day: components.day ?? 1
        )
    }

    static func date(from dateString: String, calendar: Calendar) -> Date? {
        let parts = dateString.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            return nil
        }

        return calendar.date(from: DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: parts[0],
            month: parts[1],
            day: parts[2]
        ))
    }

    /// 월 변경 시 `applyMonthChange`가 로드 전에 골격만 먼저 커밋하는 데도 쓰므로 internal 이다.
    /// 그때는 빈 `dailySummaries`를 넘겨 금액 없는 달력을 만든다.
    func makeCalendarDays(dailySummaries: [String: MainDailySummary]) -> [MainCalendarDay] {
        makeCalendarDays(for: selectedMonth, dailySummaries: dailySummaries)
    }

    /// 페이저의 이웃 슬롯은 표시 월이 아닌 달의 그리드를 그려야 해서 월을 인자로 받는다.
    func makeCalendarDays(
        for month: MainMonth,
        dailySummaries: [String: MainDailySummary]
    ) -> [MainCalendarDay] {
        guard let firstDay = month.date(day: 1, calendar: calendar),
              let dayRange = calendar.range(of: .day, in: .month, for: firstDay)
        else {
            return []
        }

        let firstWeekday = calendar.component(.weekday, from: firstDay)
        let leadingBlankCount = (firstWeekday - calendar.firstWeekday + 7) % 7

        var days: [MainCalendarDay] = (0 ..< leadingBlankCount).map { index in
            MainCalendarDay(
                id: "blank-leading-\(index)",
                day: nil,
                dateString: nil,
                isSelected: false,
                isToday: false,
                income: nil,
                expense: nil
            )
        }

        let todayDateString = Self.dateString(from: currentDate, calendar: calendar)
        for day in dayRange {
            let dateString = Self.dateString(year: month.year, month: month.month, day: day)
            let dailySummary = dailySummaries[dateString]
            days.append(MainCalendarDay(
                id: dateString,
                day: day,
                dateString: dateString,
                isSelected: dateString == selectedDateString,
                isToday: dateString == todayDateString,
                income: dailySummary?.income.nilIfZero,
                expense: dailySummary?.expense.nilIfZero
            ))
        }

        while !days.count.isMultiple(of: 7) {
            days.append(MainCalendarDay(
                id: "blank-trailing-\(days.count)",
                day: nil,
                dateString: nil,
                isSelected: false,
                isToday: false,
                income: nil,
                expense: nil
            ))
        }

        return days
    }

    /// 페이저 이웃 슬롯의 내용. 직전에 밀려난 달이면 금액을 유지한 보존본을, 미리 읽어 둔 달이면
    /// 그 금액을 그린다 — 골격으로 그리면 미는 동안 비어 있다가 정착 순간 금액이 한꺼번에 떠서
    /// 화면이 깜빡인 것처럼 보인다. 둘 다 없을 때만 골격이고, 그때는 정착 뒤 로드가 채운다.
    func neighborCalendarDays(offset: Int) -> [MainCalendarDay] {
        let month = selectedMonth.addingMonths(offset, calendar: calendar)
        if let outgoingCalendarDays, outgoingCalendarDays.month == month {
            return outgoingCalendarDays.days
        }

        guard let data = prefetchedMonths[month] else {
            return makeCalendarDays(for: month, dailySummaries: [:])
        }

        let summaries = dailySummaries(
            from: data.transactions,
            baseCurrency: baseCurrency,
            baseTTSByDate: data.baseTTSByDate
        ).summaries
        return makeCalendarDays(for: month, dailySummaries: summaries)
    }
}

private extension MainViewModel {
    func monthlySummary(from dailySummaries: Dictionary<String, MainDailySummary>.Values) -> MainMonthlySummary {
        let income = dailySummaries.reduce(Decimal(0)) { $0 + $1.income }
        let expense = dailySummaries.reduce(Decimal(0)) { $0 + $1.expense }
        return MainMonthlySummary(income: income, expense: expense, total: income - expense)
    }

    func dailySummaries(
        from transactions: [LocalTransaction],
        baseCurrency: SelectableCurrency,
        baseTTSByDate: [String: Decimal]
    ) -> (summaries: [String: MainDailySummary], hasUnconvertedTransactions: Bool) {
        var summaries: [String: MainDailySummary] = [:]
        var hasUnconvertedTransactions = false
        for transaction in transactions {
            guard let amount = baseAmount(
                for: transaction,
                baseCurrency: baseCurrency,
                baseTTSByDate: baseTTSByDate
            ) else {
                hasUnconvertedTransactions = true
                continue
            }

            var dailySummary = summaries[transaction.transactionDate] ?? MainDailySummary()
            switch transaction.transactionType {
            case .expense:
                dailySummary.expense += amount
            case .income:
                dailySummary.income += amount
            }
            summaries[transaction.transactionDate] = dailySummary
        }
        return (summaries, hasUnconvertedTransactions)
    }

    func makeHistoryRows(
        transactions: [LocalTransaction],
        baseCurrency: SelectableCurrency,
        baseTTSByDate: [String: Decimal]
    ) -> [MainHistoryRow] {
        guard let selectedDateString else {
            return []
        }

        return transactions
            .filter { $0.transactionDate == selectedDateString }
            .map { transaction in
                let tone = amountTone(for: transaction)
                let baseAmount = baseAmount(
                    for: transaction,
                    baseCurrency: baseCurrency,
                    baseTTSByDate: baseTTSByDate
                )
                let categoryName = categoryDisplayName(for: transaction)
                let assetName = assetDisplayName(id: transaction.assetID)
                let title = memoTitle(for: transaction)
                let isForeignCurrency = transaction.currencyCode != baseCurrency.rawValue
                let secondaryAmount = baseAmount != nil && isForeignCurrency
                    ? originalAmountText(for: transaction)
                    : nil

                return MainHistoryRow(
                    id: transaction.clientEntryID,
                    title: title,
                    categoryAssetText: "\(categoryName) · \(assetName)",
                    exchangeInfoText: exchangeInfo(
                        for: transaction,
                        baseCurrency: baseCurrency,
                        baseTTSByDate: baseTTSByDate
                    ),
                    amountText: historyAmountText(
                        for: transaction,
                        baseAmount: baseAmount,
                        baseCurrency: baseCurrency
                    ),
                    secondaryAmountText: secondaryAmount,
                    tone: tone
                )
            }
    }

    func historyAmountText(
        for transaction: LocalTransaction,
        baseAmount: Decimal?,
        baseCurrency: SelectableCurrency
    ) -> String {
        if let baseAmount {
            return CurrencyFormat.string(baseAmount, currencyCode: baseCurrency.rawValue)
        }

        if transaction.currencyCode != baseCurrency.rawValue {
            return originalAmountText(for: transaction)
        }

        return CurrencyFormat.string(transaction.amount, currencyCode: baseCurrency.rawValue)
    }

    func originalAmountText(for transaction: LocalTransaction) -> String {
        let amountText = formatOriginalAmount(
            transaction.amount,
            currencyCode: transaction.currencyCode
        )
        return "\(transaction.currencyCode) \(amountText)"
    }

    func formatOriginalAmount(_ amount: Decimal, currencyCode: String) -> String {
        CurrencyFormat.string(amount, currencyCode: currencyCode)
    }

    func baseAmount(
        for transaction: LocalTransaction,
        baseCurrency: SelectableCurrency,
        baseTTSByDate: [String: Decimal]
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

    func displayValue(
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

    func exchangeInfo(
        for transaction: LocalTransaction,
        baseCurrency: SelectableCurrency,
        baseTTSByDate: [String: Decimal]
    ) -> String? {
        guard transaction.currencyCode != baseCurrency.rawValue,
              let currency = SelectableCurrency(rawValue: transaction.currencyCode),
              let baseKrwPerUnit = baseKrwPerUnit(
                  baseCurrency: baseCurrency,
                  transactionDate: transaction.transactionDate,
                  baseTTSByDate: baseTTSByDate
              )
        else {
            return nil
        }

        let counterKrwPerUnit: Decimal?
        if currency == .krw {
            counterKrwPerUnit = Decimal(1)
        } else {
            let rate = transaction.appliedRate
                ?? rateProvider.rate(for: currency, on: transaction.transactionDate)
            counterKrwPerUnit = rate.flatMap {
                BaseRateMath.krwPerUnit(tts: $0, unit: currency.exchangeUnit)
            }
        }
        guard let counterKrwPerUnit else {
            return nil
        }

        let counterRate = BaseRateMath.counterRate(
            baseKrwPerUnit: baseKrwPerUnit,
            counterKrwPerUnit: counterKrwPerUnit
        )
        return "\(baseCurrency.rawValue) 1.00 = \(transaction.currencyCode) "
            + CurrencyFormat.rateString(counterRate)
    }

    func baseKrwPerUnit(
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

    func memoTitle(for transaction: LocalTransaction) -> String? {
        let trimmed = transaction.memo?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    func categoryDisplayName(for transaction: LocalTransaction) -> String {
        if let category = categoriesByID[transaction.categoryID] {
            return localizedDisplayName(for: category)
        }

        let type: CatalogTransactionType = transaction.transactionType == .expense ? .expense : .income
        // SwiftFormat의 wrapMultilineStatementBraces와 SwiftLint opening_brace가 충돌하는 다중행 조건이다.
        // swiftlint:disable opening_brace
        if let category = customCategoryStore.categories(for: type)
            .first(where: { $0.id == transaction.categoryID })
        {
            return localizedDisplayName(for: category)
        }
        // swiftlint:enable opening_brace

        return transaction.categorySnapshot ?? WoniStrings.uncategorized(language)
    }

    func localizedDisplayName(for category: Category) -> String {
        let name = language == .ko ? category.displayNameKo : category.displayNameEn
        return category.icon.map { "\($0) \(name)" } ?? name
    }

    func assetDisplayName(id: Int) -> String {
        guard let asset = assetsByID[id] else {
            return WoniStrings.unassigned(language)
        }

        return language == .ko ? asset.displayNameKo : asset.displayNameEn
    }

    func amountTone(for transaction: LocalTransaction) -> MainAmountTone {
        switch transaction.transactionType {
        case .expense:
            .expense
        case .income:
            .income
        }
    }

    static func dateString(year: Int, month: Int, day: Int) -> String {
        String(format: "%04d-%02d-%02d", year, month, day)
    }
}

private extension Decimal {
    var nilIfZero: Decimal? {
        self == 0 ? nil : self
    }
}
