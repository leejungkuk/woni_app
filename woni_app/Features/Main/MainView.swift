import SwiftUI

struct MainView: View {
    @State private var viewModel: MainViewModel
    let onAdd: () -> Void

    init(viewModel: MainViewModel, onAdd: @escaping () -> Void) {
        _viewModel = State(initialValue: viewModel)
        self.onAdd = onAdd
    }

    var body: some View {
        VStack(spacing: 0) {
            fixedTopArea

            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    VStack(spacing: 8) {
                        if let conversionWarningText = viewModel.conversionWarningText {
                            MainConversionWarningView(text: conversionWarningText)
                        }

                        MainHistoryListView(rows: viewModel.historyRows)
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 16)
                    .padding(.bottom, 92)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color.Woni.base10)

                MainFloatingAddButton(action: onAdd)
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
        }
        .background(Color.Woni.gray00)
        .ignoresSafeArea(.container, edges: .bottom)
        .task {
            await viewModel.load()
        }
    }

    private var fixedTopArea: some View {
        VStack(spacing: 0) {
            MainHeaderView(monthTitle: viewModel.monthTitle)

            MainSummaryStripView(items: viewModel.summaryItems)

            if viewModel.isLoading {
                ProgressView()
                    .tint(Color.Woni.olive100)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.woni(.body3))
                    .foregroundColor(Color.Woni.terracotta100)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
            } else {
                MainCalendarGridView(
                    days: viewModel.calendarDays,
                    formatAmount: viewModel.formatMoney,
                    onSelect: { day in
                        viewModel.selectDay(day)
                    }
                )
            }
        }
        .background(Color.Woni.gray00)
        .contentShape(Rectangle())
        .gesture(monthSwipeGesture)
    }

    private var monthSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 24)
            .onEnded { value in
                Task {
                    await viewModel.handleSwipe(
                        horizontal: value.translation.width,
                        vertical: value.translation.height
                    )
                }
            }
    }
}

#Preview {
    if let dependencies = try? AppDependencyFactory.makeMainDependencies(inMemory: true) {
        MainView(
            viewModel: MainViewModel(
                transactionRepository: dependencies.transactionRepository,
                catalogProvider: dependencies.catalogProvider,
                rateProvider: dependencies.rateProvider
            ),
            onAdd: {}
        )
    } else {
        Text("Preview unavailable")
    }
}
