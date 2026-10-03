//
//  BudgetEditForm.swift
//  woni_app
//

import SwiftUI

/// 예산 편집 화면에서 입력 중인 칸. 결제수단 "최대 N" 과 밑줄 색이 이것을 본다.
enum BudgetEditField: Hashable {
    case total
    case category(Int)
    case payment(PaymentGroup)
}

/// 예산 편집 화면의 입력 부분 — 전체 → 지난 달 불러오기 → 카테고리 → 결제수단 → 이 달 예산 삭제(UI_GUIDE "편집 화면").
/// 금액·버튼 표시·확인 여부는 `BudgetEditViewModel`·`BudgetEditDraft` 가 정하고 여기서는 그리기와 입력 전달만 한다.
struct BudgetEditForm: View {
    let viewModel: BudgetEditViewModel
    /// 칩·금액 줄 이름을 찾는 지금의 카테고리 목록(내 카테고리 → 기본).
    let categories: [Category]
    let language: AppLanguage
    @Binding var focusedField: BudgetEditField?
    /// 칸 값을 바꿀 수 있는 동작 앞에서 부른다 — 포커스 중인 칸은 바깥 값으로 다시 그리지 않는다(`BudgetAmountTextField`).
    let dismissKeyboard: () -> Void
    let onTapCurrency: () -> Void
    /// 칸 하나가 상한을 넘었다.
    let onLimitExceeded: () -> Void

    private static let paymentGroups: [PaymentGroup] = [.creditCard, .cashAndDebit, .accountAndOther]

    private var draft: BudgetEditDraft {
        viewModel.draft
    }

    private var decimalPlaces: Int {
        CurrencyFormat.decimalPlaces(for: draft.currency.rawValue)
    }

    var body: some View {
        VStack(spacing: 0) {
            totalSection
            if viewModel.showsLoadPrevious {
                loadPreviousChip
            }
            categorySection
            paymentSection
            if viewModel.showsDeleteButton {
                deleteButton
            }
        }
    }
}

// MARK: 전체 · 불러오기 · 삭제

private extension BudgetEditForm {
    var totalSection: some View {
        VStack(spacing: 16) {
            currencyButton

            VStack(spacing: 4) {
                BudgetAmountField(
                    onAmountChange: { amount in
                        viewModel.setDirectTotal(amount)
                        return true
                    },
                    isFocused: focusBinding(.total),
                    displayAmount: draft.total,
                    decimalPlaces: decimalPlaces,
                    style: .total,
                    isEnabled: !viewModel.isWriting,
                    accessibilityIdentifier: "budgetEdit.total",
                    emptyAccessibilityValue: WoniStrings.budgetNoBudget(language),
                    onLimitExceeded: onLimitExceeded,
                    onEditingEnded: { viewModel.endTotalEditing() }
                )
                if draft.total == nil {
                    note(WoniStrings.budgetEditTotalHint(language))
                } else if draft.isTotalAutomatic {
                    note(WoniStrings.budgetEditCategorySum(language))
                }
                if let spent = draft.spentTotal {
                    note(spentText(spent))
                }
            }
            .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
    }

    /// 입력 화면 통화 캡슐(`AmountInputSection`)과 같은 모양. 지출만이라 terracotta 다.
    var currencyButton: some View {
        Button {
            dismissKeyboard()
            onTapCurrency()
        } label: {
            HStack(spacing: 4) {
                Text(draft.currency.rawValue)
                    .woniFont(.body1)
                    .foregroundStyle(WoniColor.terracotta110)
                Image(systemName: "chevron.down")
                    .font(.system(size: 14))
                    .foregroundStyle(WoniColor.terracotta110)
                    .frame(width: 24, height: 24)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(WoniColor.terracotta20)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("budgetEdit.currency")
    }

    var loadPreviousChip: some View {
        BudgetEditCapsuleButton(
            title: WoniStrings.budgetEditLoadPrevious(language),
            isSelected: viewModel.isPreviousApplied,
            isEnabled: viewModel.canLoadPrevious
        ) {
            dismissKeyboard()
            Task { await viewModel.loadPrevious() }
        }
        .disabled(viewModel.isWriting)
        .accessibilityIdentifier("budgetEdit.loadPrevious")
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// 입력 화면 삭제 버튼과 같은 외곽선 캡슐.
    var deleteButton: some View {
        Button {
            dismissKeyboard()
            viewModel.requestDelete()
        } label: {
            Text(WoniStrings.budgetEditDeleteMonth(language))
                .woniFont(.body3)
                .foregroundStyle(WoniColor.terracotta100)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(WoniColor.base10)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(WoniColor.terracotta100, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("budgetEdit.delete")
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

// MARK: 카테고리

private extension BudgetEditForm {
    var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(WoniStrings.budgetCategoryCardTitle(language))

            ForEach(draft.categoryLines, id: \.categoryID) { line in
                categoryRow(line)
            }

            if let other = draft.otherCategoriesAmount {
                HStack {
                    Text(WoniStrings.budgetOtherCategories(language))
                    Spacer(minLength: 12)
                    Text(amountText(other))
                }
                .woniFont(.body3)
                .foregroundStyle(WoniColor.gray60)
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("budgetEdit.otherCategories")
            }

            chips

            note(WoniStrings.budgetEditCategoryHint(language))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func categoryRow(_ line: BudgetEditCategoryLine) -> some View {
        let field = BudgetEditField.category(line.categoryID)
        return BudgetEditAmountRow(
            name: lineName(line),
            isFocused: focusedField == field,
            notes: [draft.spent(forCategory: line.categoryID).map(spentText)].compactMap(\.self)
        ) {
            BudgetAmountField(
                onAmountChange: { viewModel.setCategoryAmount($0, for: line.categoryID) },
                isFocused: focusBinding(field),
                displayAmount: line.amount,
                decimalPlaces: decimalPlaces,
                style: .line,
                isEnabled: !viewModel.isWriting,
                accessibilityIdentifier: "budgetEdit.category.\(line.categoryID)",
                emptyAccessibilityValue: WoniStrings.budgetNoBudget(language),
                onLimitExceeded: onLimitExceeded,
                onEditingEnded: {}
            )
        }
    }

    /// 입력 화면 카테고리 칩(`ChipSection`)과 같은 칩·간격. `ChipSection` 은 제목 줄을 뺄 수 없어 칩만 같은 부품으로 그린다.
    /// 모두 꺼진 모양이고 `+ 추가` 칩은 없다(새 카테고리는 카테고리 관리에서). 누르면 금액 줄이 생긴다 — 포커스는 주지 않는다.
    var chips: some View {
        let items = viewModel.chipCategoryIDs.compactMap { id in categories.first { $0.id == id } }
        return FlowLayout(spacing: 8) {
            ForEach(items) { category in
                ChipButton(
                    label: CategoryDisplayNameResolver.localizedDisplayName(for: category, language: language),
                    isSelected: false
                ) {
                    dismissKeyboard()
                    viewModel.addCategory(category.id)
                }
                .accessibilityIdentifier("budgetEdit.chip.\(category.id)")
            }
        }
        .disabled(viewModel.isWriting)
    }

    func lineName(_ line: BudgetEditCategoryLine) -> String {
        switch viewModel.lineLabel(line, in: categories) {
        case .deleted:
            WoniStrings.budgetDeletedCategory(language)
        case let .category(category):
            CategoryDisplayNameResolver.localizedDisplayName(for: category, language: language)
        }
    }
}

// MARK: 결제수단

private extension BudgetEditForm {
    var paymentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(WoniStrings.budgetPaymentCardTitle(language))

            if draft.isPaymentExpanded {
                ForEach(Self.paymentGroups, id: \.self) { group in
                    paymentRow(group)
                }
                if let excess = draft.paymentExcess {
                    Text(WoniStrings.budgetEditPaymentExcess(amountText(excess), language: language))
                        .woniFont(.body3)
                        .foregroundStyle(WoniColor.terracotta100)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(WoniColor.terracotta10)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .accessibilityIdentifier("budgetEdit.paymentWarning")
                } else if let remaining = draft.paymentRemaining {
                    let remainingText = WoniStrings.budgetEditPaymentRemaining(
                        amountText(remaining),
                        language: language
                    )
                    HStack {
                        Text(remainingText.label)
                        if let amount = remainingText.amount {
                            Spacer(minLength: 12)
                            Text(amount)
                        }
                    }
                    .woniFont(.body3)
                    .foregroundStyle(WoniColor.gray60)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("budgetEdit.paymentRemaining")
                }
            } else {
                BudgetEditCapsuleButton(
                    title: WoniStrings.budgetEditSplitByPayment(language),
                    isSelected: false,
                    isEnabled: draft.isPaymentInputEnabled
                ) {
                    viewModel.togglePaymentSection()
                }
                .disabled(viewModel.isWriting)
                .accessibilityIdentifier("budgetEdit.paymentExpand")
                note(WoniStrings.budgetEditPaymentHint(language))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func paymentRow(_ group: PaymentGroup) -> some View {
        let field = BudgetEditField.payment(group)
        let isFocused = focusedField == field
        let maximum = isFocused ? draft.paymentMaximum(for: group) : nil
        return BudgetEditAmountRow(
            name: WoniStrings.budgetPaymentGroupName(group, language: language),
            isFocused: isFocused,
            notes: [
                maximum.map { WoniStrings.budgetEditPaymentMaximum(amountText($0), language: language) },
                draft.spent(forPayment: group).map(spentText)
            ].compactMap(\.self)
        ) {
            BudgetAmountField(
                onAmountChange: { amount in
                    viewModel.setPaymentAmount(amount, for: group)
                    return true
                },
                isFocused: focusBinding(field),
                displayAmount: draft.paymentAmounts[group],
                decimalPlaces: decimalPlaces,
                style: .line,
                isEnabled: draft.isPaymentInputEnabled && !viewModel.isWriting,
                accessibilityIdentifier: "budgetEdit.payment.\(Self.identifierSuffix(group))",
                emptyAccessibilityValue: WoniStrings.budgetNoBudget(language),
                onLimitExceeded: onLimitExceeded,
                onEditingEnded: {}
            )
        }
    }

    static func identifierSuffix(_ group: PaymentGroup) -> String {
        switch group {
        case .creditCard: "creditCard"
        case .cashAndDebit: "cashAndDebit"
        case .accountAndOther: "accountAndOther"
        }
    }
}

// MARK: 공통

private extension BudgetEditForm {
    /// 칸의 편집 상태를 받는다. 전체 칸에 들어올 때마다 이번에 쳤는지를 새로 센다(`beginTotalEditing`).
    func focusBinding(_ field: BudgetEditField) -> Binding<Bool> {
        Binding(
            get: { focusedField == field },
            set: { isFocused in
                if isFocused {
                    if field == .total {
                        viewModel.beginTotalEditing()
                    }
                    focusedField = field
                } else if focusedField == field {
                    focusedField = nil
                }
            }
        )
    }

    func sectionTitle(_ title: String) -> some View {
        Text(title)
            .woniFont(.body3)
            .foregroundStyle(WoniColor.gray100)
    }

    func note(_ text: String) -> some View {
        Text(text)
            .woniFont(.small1)
            .foregroundStyle(WoniColor.gray60)
    }

    func amountText(_ amount: Decimal) -> String {
        CurrencyFormat.string(amount, currencyCode: draft.currency.rawValue)
    }

    func spentText(_ amount: Decimal) -> String {
        WoniStrings.budgetEditSpent(month: viewModel.month.month, amountText: amountText(amount), language: language)
    }
}

/// 금액 줄 한 줄 — 왼쪽 이름, 오른쪽 금액 칸과 밑줄(입력 중이면 terracotta), 칸 아래 작은 줄들(오른쪽 정렬).
struct BudgetEditAmountRow<Field: View>: View {
    let name: String
    let isFocused: Bool
    let notes: [String]
    @ViewBuilder let field: Field

    var body: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(spacing: 12) {
                Text(name)
                    .woniFont(.body2)
                    .foregroundStyle(WoniColor.gray100)
                    .lineLimit(1)
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                    field
                    Rectangle()
                        .fill(isFocused ? WoniColor.terracotta100 : WoniColor.base20)
                        .frame(height: 1)
                }
                .frame(width: 140)
            }
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .woniFont(.small1)
                    .foregroundStyle(WoniColor.gray60)
            }
        }
    }
}

/// 칩 모양 캡슐(`ChipButton` 과 같은 규격)에 비활성(회색)을 더했다 — 지난 달 불러오기 칩·결제수단 나누기 캡슐.
struct BudgetEditCapsuleButton: View {
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    private var foreground: Color {
        guard isEnabled else {
            return WoniColor.gray40
        }
        return isSelected ? WoniColor.terracotta100 : WoniColor.gray80
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .woniFont(.body3)
                .foregroundStyle(foreground)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(isSelected ? WoniColor.terracotta10 : WoniColor.base10)
                .overlay {
                    Capsule().stroke(isSelected ? WoniColor.terracotta70 : WoniColor.gray20, lineWidth: 1)
                }
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
