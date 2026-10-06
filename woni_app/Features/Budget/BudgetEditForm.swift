//
//  BudgetEditForm.swift
//  woni_app
//

import SwiftUI

/// 예산 편집 화면에서 입력 중인 칸. 결제수단·카테고리 "최대 N" 과 밑줄 색이 이것을 본다.
enum BudgetEditField: Hashable {
    case total
    case category(Int)
    case payment(PaymentGroup)
}

/// 예산 편집 화면의 입력 부분 — 전체 → 지난 달 불러오기 → 카테고리 → 결제수단 → 입력 모두 지우기 · 이 달 예산 삭제
/// (UI_GUIDE "편집 화면").
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
    /// 결제수단·카테고리 줄과 범위 끝의 편집 본문 기준 프레임 — 입력 중 스크롤 맞춤(`BudgetEditKeyboardScroll`)이 쓴다.
    let onScrollFrame: (BudgetEditKeyboardScroll.ScrollID, CGRect) -> Void

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
            bottomButtons
        }
    }
}

// MARK: 전체 · 불러오기 · 지우기 · 삭제

private extension BudgetEditForm {
    var totalSection: some View {
        VStack(spacing: 16) {
            currencyButton

            VStack(spacing: 4) {
                BudgetAmountField(
                    onAmountChange: { viewModel.setDirectTotal($0) },
                    isFocused: focusBinding(.total),
                    displayAmount: draft.total,
                    decimalPlaces: decimalPlaces,
                    style: .total,
                    isEnabled: !viewModel.isWriting,
                    accessibilityIdentifier: "budgetEdit.total",
                    emptyAccessibilityValue: WoniStrings.budgetNoBudget(language),
                    onLimitExceeded: onLimitExceeded,
                    onEditingEnded: { viewModel.endTotalEditing() },
                    onLockedTap: lockedTotalTap
                )
                if let hint = viewModel.totalHint(language) {
                    note(hint)
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

    /// 잠긴 전체 칸(갈래 B)을 누름 — 손가락 누름·VoiceOver 활성화에서만 온다(`BudgetAmountUITextField`). 잠기지 않았으면 nil.
    /// 칸이 포커스를 받지 않아 다른 칸의 키보드가 저절로 내려가지 않으므로 먼저 내린다(빈 곳을 누른 것과 같다).
    var lockedTotalTap: (() -> Void)? {
        guard draft.isTotalAutomatic else {
            return nil
        }
        return {
            dismissKeyboard()
            viewModel.tapLockedTotal()
        }
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

    /// `입력 모두 지우기` · `이 달 예산 삭제` 한 묶음(사이 12). 지우기는 편집 중이면 늘 보이고, 삭제는 그 달에 예산이 있을 때만.
    var bottomButtons: some View {
        VStack(spacing: 12) {
            clearAllButton
            if viewModel.showsDeleteButton {
                deleteButton
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    /// DS `element_btn` Default S — 피커·확인 창 `취소` 와 같은 중립 외곽선(되돌릴 수 없는 삭제의 terracotta 와 구분).
    /// 꺼지면 글자만 `gray40` 이다.
    var clearAllButton: some View {
        Button {
            dismissKeyboard()
            viewModel.requestClearAll()
        } label: {
            Text(WoniStrings.budgetEditClearAll(language))
                .woniFont(.body3)
                .foregroundStyle(viewModel.canClearAll ? WoniColor.gray80 : WoniColor.gray40)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(WoniColor.gray00)
                .clipShape(Capsule())
                .overlay {
                    Capsule().stroke(WoniColor.base20, lineWidth: 1)
                }
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canClearAll)
        .accessibilityIdentifier("budgetEdit.clearAll")
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
    }
}

// MARK: 카테고리

private extension BudgetEditForm {
    var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionTitle(WoniStrings.budgetCategoryCardTitle(language))

            // 키보드 맞춤 범위 끝 = 자리의 아래 끝, 자리가 없으면 마지막 줄의 아래 끝.
            ForEach(draft.categoryLines, id: \.categoryID) { line in
                categoryRow(line)
                    .budgetEditCategorySlotEnd(
                        viewModel.categorySlot == .none && line.categoryID == draft.categoryLines.last?.categoryID,
                        onFrame: onScrollFrame
                    )
            }

            categorySlotLine
                .budgetEditCategorySlotEnd(viewModel.categorySlot != .none, onFrame: onScrollFrame)

            chips

            if let hint = viewModel.categoryHint(language) {
                note(hint)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 금액 줄 아래 한 자리 — 합 초과 경고 · 넘는 입력 경고 · "그 외 카테고리" 중 하나(`BudgetEditCategorySlot`).
    /// 경고 줄은 결제수단 경고 줄과 같은 부품이다. 합 초과는 전체 칸에 치는 키마다 바로 바뀐다.
    @ViewBuilder
    var categorySlotLine: some View {
        switch viewModel.categorySlot {
        case let .excess(excess):
            BudgetEditWarningLine(
                text: WoniStrings.budgetEditCategoryExcess(amountText(excess), language: language),
                identifier: "budgetEdit.categoryExcess"
            )
        case .overTotal:
            BudgetEditWarningLine(
                text: WoniStrings.budgetEditCategoryOverTotal(language),
                identifier: "budgetEdit.categoryOverTotal"
            )
        case let .otherCategories(other):
            HStack {
                Text(WoniStrings.budgetOtherCategories(language))
                Spacer(minLength: 12)
                Text(amountText(other))
            }
            .woniFont(.body3)
            .foregroundStyle(WoniColor.gray60)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("budgetEdit.otherCategories")
        case .none:
            EmptyView()
        }
    }

    /// 줄 끝 X 는 확인 없이 줄을 뺀다. 키보드를 먼저 내린다 — 내리지 않으면 포커스가 빠진 칸을 가리킨 채 남는다.
    /// 입력 중인 줄 아래 "최대 N" 은 갈래 A 에서만 있다(결제수단 줄과 같은 자리·모양).
    func categoryRow(_ line: BudgetEditCategoryLine) -> some View {
        let field = BudgetEditField.category(line.categoryID)
        let isFocused = focusedField == field
        let maximum = isFocused ? draft.categoryMaximum(for: line.categoryID) : nil
        let name = lineName(line)
        return BudgetEditAmountRow(
            name: name,
            isFocused: isFocused,
            notes: [
                maximum.map { WoniStrings.budgetEditMaximum(amountText($0), language: language) },
                draft.spent(forCategory: line.categoryID).map(spentText)
            ].compactMap(\.self),
            removal: BudgetEditLineRemoval(
                label: WoniStrings.budgetEditRemoveLine(
                    viewModel.lineLabel(line, in: categories).bareName(language),
                    language: language
                ),
                identifier: "budgetEdit.category.\(line.categoryID).remove",
                isEnabled: !viewModel.isWriting
            ) {
                dismissKeyboard()
                viewModel.removeCategory(line.categoryID)
            }
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
                onEditingEnded: { viewModel.endCategoryEditing() }
            )
        }
        .budgetEditScrollTarget(.categoryRow(line.categoryID), onFrame: onScrollFrame)
    }

    /// 입력 화면 카테고리 칩(`ChipSection`)과 같은 칩·간격. `ChipSection` 은 제목 줄을 뺄 수 없어 칩만 같은 부품으로 그린다.
    /// 모두 꺼진 모양이고 `+ 추가` 칩은 없다(새 카테고리는 카테고리 관리에서). 누르면 금액 줄이 생긴다 — 포커스는 주지 않는다.
    /// 맨 뒤에 "삭제된 카테고리" 칩(아이콘 없음) — 누르면 삭제된 줄 그대로 돌아온다.
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
            ForEach(viewModel.deletedChipCategoryIDs, id: \.self) { categoryID in
                ChipButton(label: WoniStrings.budgetDeletedCategory(language), isSelected: false) {
                    dismissKeyboard()
                    viewModel.addDeletedCategory(categoryID)
                }
                .accessibilityIdentifier("budgetEdit.deletedChip.\(categoryID)")
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
                    BudgetEditWarningLine(
                        text: WoniStrings.budgetEditPaymentExcess(amountText(excess), language: language),
                        identifier: "budgetEdit.paymentWarning"
                    )
                } else if let remaining = draft.paymentRemaining {
                    let remainingText = WoniStrings.budgetEditPaymentRemaining(
                        amountText(remaining),
                        language: language
                    )
                    HStack {
                        Text(remainingText.label)
                        Spacer(minLength: 12)
                        Text(remainingText.amount)
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
        .budgetEditScrollTarget(.paymentSectionEnd, onFrame: onScrollFrame)
    }

    func paymentRow(_ group: PaymentGroup) -> some View {
        let field = BudgetEditField.payment(group)
        let isFocused = focusedField == field
        let maximum = isFocused ? draft.paymentMaximum(for: group) : nil
        return BudgetEditAmountRow(
            name: WoniStrings.budgetPaymentGroupName(group, language: language),
            isFocused: isFocused,
            notes: [
                maximum.map { WoniStrings.budgetEditMaximum(amountText($0), language: language) },
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
        .budgetEditScrollTarget(.paymentRow(group), onFrame: onScrollFrame)
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
    /// 칸의 편집 상태를 받는다.
    func focusBinding(_ field: BudgetEditField) -> Binding<Bool> {
        Binding(
            get: { focusedField == field },
            set: { isFocused in
                if isFocused {
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

/// 섹션 맨 아래 경고 줄 — 결제수단 합 초과 · 카테고리 합 초과 · 넘는 카테고리 입력(UI_GUIDE "경고는 결제수단처럼").
/// terracotta10 바탕, radius 8.
struct BudgetEditWarningLine: View {
    let text: String
    let identifier: String

    var body: some View {
        Text(text)
            .woniFont(.body3)
            .foregroundStyle(WoniColor.terracotta100)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(WoniColor.terracotta10)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .accessibilityIdentifier(identifier)
    }
}

/// 카테고리 금액 줄 끝 X(UI_GUIDE "금액 줄 끝 X"). 결제수단 줄에는 없다.
struct BudgetEditLineRemoval {
    /// VoiceOver 라벨 — 아이콘 없는 줄 이름 + "빼기".
    let label: String
    let identifier: String
    let isEnabled: Bool
    let action: () -> Void
}

/// 금액 줄 한 줄 — 왼쪽 이름, 오른쪽 금액 칸과 밑줄(입력 중이면 terracotta), 칸 아래 작은 줄들(칸 오른쪽 끝에 맞춤).
/// X 는 칸 오른쪽에 8 띄운 28×28 로 보인다(카테고리 관리 줄 X 와 같은 모양). 칸 폭 140 은 그대로라 칸이 X 몫(36)만큼 왼쪽으로
/// 간다. X 의 누름 영역 44×44 는 칸 오른쪽 끝에서 시작해 오른쪽 여백으로 8 나간다 — 칸의 누름 영역과 겹치지 않고, 줄 높이도
/// 바꾸지 않는다.
struct BudgetEditAmountRow<Field: View>: View {
    let name: String
    let isFocused: Bool
    let notes: [String]
    var removal: BudgetEditLineRemoval?
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
            .overlay(alignment: .trailing) {
                if let removal {
                    removeButton(removal)
                        // 폭 0 자리를 칸 오른쪽 끝에 두고 누름 영역을 거기서 오른쪽으로 뻗는다.
                        .padding(.trailing, -44)
                }
            }
            ForEach(notes, id: \.self) { note in
                Text(note)
                    .woniFont(.small1)
                    .foregroundStyle(WoniColor.gray60)
            }
        }
        .padding(.trailing, removal == nil ? 0 : 36)
    }

    private func removeButton(_ removal: BudgetEditLineRemoval) -> some View {
        Button(action: removal.action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WoniColor.gray60)
                .frame(width: 28, height: 28)
                .padding(.leading, 8)
                .frame(width: 44, height: 44, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!removal.isEnabled)
        .accessibilityLabel(removal.label)
        .accessibilityIdentifier(removal.identifier)
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
