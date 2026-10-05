//
//  MonthReportView.swift
//  woni_app
//

import SwiftUI

struct MonthReportView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: MonthReportViewModel

    /// 원장 감시·포그라운드 재조회는 루트가 한다 — 통계 탭은 보이지 않을 때도 살아 있어야 최신이다.
    let onSelectCategory: (Int) -> Void
    /// 달 피커는 루트가 탭바보다 위에 그린다 — 이 화면은 무엇을 띄울지만 알린다.
    let overlays: RootOverlayModel

    init(
        viewModel: MonthReportViewModel,
        onSelectCategory: @escaping (Int) -> Void,
        overlays: RootOverlayModel
    ) {
        _viewModel = State(initialValue: viewModel)
        self.onSelectCategory = onSelectCategory
        self.overlays = overlays
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            // 제목 줄은 고정이고 그 아래 전부가 손가락을 따라 밀린다(UI_GUIDE "달 넘기기").
            ReportMonthPager(viewModel: viewModel, onSelectCategory: onSelectCategory)
        }
        .background(WoniColor.base10)
        .toolbar(.hidden, for: .navigationBar)
        // 피커가 떠 있는 동안 뒤 화면은 멈춘다 — 가장자리 스와이프로 리포트가 닫히면 안 된다.
        .interactivePopGestureEnabled(!overlays.isPresented(.reportMonthPicker))
    }
}

extension MonthReportView {
    /// 달 제목 피커의 저장 색은 보고 있는 탭을 따른다 — 수입 탭은 olive, 지출·합계 탭은 terracotta.
    static func pickerSaveColor(for kind: MainSummaryItem.Kind) -> Color {
        kind == .income ? WoniColor.olive100 : WoniColor.terracotta100
    }
}

private extension MonthReportView {
    var header: some View {
        ZStack {
            HStack {
                Button {
                    dismiss()
                } label: {
                    CircleIconButton {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(WoniColor.gray80)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(WoniStrings.back(viewModel.language))
                .accessibilityIdentifier("report.back")
                // 탭의 첫 화면이라 뒤로 갈 곳이 없다. 칸은 KR 머리 골격대로 남긴다.
                .opacity(0)
                .accessibilityHidden(true)
                .disabled(true)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)

            HStack(spacing: 0) {
                monthButton(
                    systemName: "chevron.left",
                    identifier: "report.month.prev",
                    label: WoniStrings.previousMonth(viewModel.language),
                    offset: -1
                )

                Button {
                    overlays.present(.reportMonthPicker, content: yearMonthPicker)
                } label: {
                    Text(viewModel.monthTitle)
                        .woniFont(.body1)
                        .foregroundStyle(WoniColor.gray100)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                        .frame(minHeight: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("report.monthTitle")

                monthButton(
                    systemName: "chevron.right",
                    identifier: "report.month.next",
                    label: WoniStrings.nextMonth(viewModel.language),
                    offset: 1
                )
            }
            .padding(.horizontal, 72)
        }
        .frame(height: 52)
        .background(WoniColor.gray00)
    }

    var yearMonthPicker: some View {
        YearMonthPickerOverlay(
            initialYear: viewModel.selectedMonth.year,
            initialMonth: viewModel.selectedMonth.month,
            years: YearMonthPickerOverlay.defaultYears(including: viewModel.selectedMonth.year),
            saveColor: Self.pickerSaveColor(for: viewModel.selectedKind),
            language: viewModel.language,
            onSave: { year, month in
                overlays.dismiss(.reportMonthPicker)
                viewModel.setMonth(MainMonth(year: year, month: month))
            },
            onCancel: {
                overlays.dismiss(.reportMonthPicker)
            }
        )
    }

    func monthButton(
        systemName: String,
        identifier: String,
        label: String,
        offset: Int
    ) -> some View {
        Button {
            changeMonth(by: offset)
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(WoniColor.gray80)
                .frame(width: 32, height: 44)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    func changeMonth(by offset: Int) {
        viewModel.setMonth(
            viewModel.selectedMonth.addingMonths(offset, calendar: viewModel.calendar)
        )
    }
}

#Preview("Month report 393pt") {
    if let dependencies = try? AppDependencyFactory.makeSeedDependencies(inMemory: true) {
        let viewModel = MonthReportViewModel(
            transactionRepository: dependencies.transactionRepository,
            catalogProvider: dependencies.catalogProvider,
            customCategoryStore: dependencies.customCategoryStore,
            rateProvider: dependencies.mainRateProvider,
            baseRateResolver: BaseRateResolver(
                cache: dependencies.exchangeRateCache,
                seedRateProvider: dependencies.mainRateProvider
            ),
            baseCurrency: .krw,
            language: .ko
        )
        MonthReportView(
            viewModel: viewModel,
            onSelectCategory: { _ in },
            overlays: RootOverlayModel()
        )
        .frame(width: 393, height: 852)
        .onAppear {
            viewModel.start(
                month: viewModel.selectedMonth,
                language: .ko,
                baseCurrency: .krw,
                revision: dependencies.syncEngine.ledgerRevision
            )
        }
    } else {
        Text("Preview unavailable")
    }
}
