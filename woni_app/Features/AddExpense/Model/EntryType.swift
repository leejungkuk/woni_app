enum EntryType: Hashable {
    case expense
    case income
}

/// 입력 화면 NavigationStack 라우트. 목적지 화면 본체는 관리·추가 화면 구현에서 채운다.
enum EntryRoute: Hashable {
    case manage(EntryType)
    case add(EntryType)
}
