//
//  SyncEngineTestSupport.swift
//  woni_appTests
//

import Foundation

struct SyncPushRecordedRequest {
    let method: String
    let path: String
    let queryItems: [String: String]
    let body: Data?
}

final class SyncPushRequestRecorder {
    private let lock = NSLock()
    private var requests: [SyncPushRecordedRequest] = []

    func record(_ request: URLRequest) {
        let recorded = SyncPushRecordedRequest(
            method: request.httpMethod ?? "",
            path: request.url?.path ?? "",
            queryItems: Dictionary(
                uniqueKeysWithValues: (URLComponents(
                    url: request.url ?? URL(fileURLWithPath: "/"),
                    resolvingAgainstBaseURL: false
                )?
                    .queryItems ?? [])
                    .compactMap { item in item.value.map { (item.name, $0) } }
            ),
            body: syncRequestBodyData(from: request)
        )
        lock.lock()
        requests.append(recorded)
        lock.unlock()
    }

    func snapshot() -> [SyncPushRecordedRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}

actor SyncPushImportGate {
    private var didStart = false
    private var didJoin = false
    private var isReleased = false
    private var startWaiters: [CheckedContinuation<Void, Never>] = []
    private var joinWaiters: [CheckedContinuation<Void, Never>] = []
    private var releaseWaiters: [CheckedContinuation<Void, Never>] = []

    func signalStartedAndWaitForRelease() async {
        if !didStart {
            didStart = true
            let waiters = startWaiters
            startWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }

        guard !isReleased else {
            return
        }
        await withCheckedContinuation { continuation in
            releaseWaiters.append(continuation)
        }
    }

    func waitUntilStarted() async {
        guard !didStart else {
            return
        }
        await withCheckedContinuation { continuation in
            startWaiters.append(continuation)
        }
    }

    func signalJoined() {
        guard !didJoin else {
            return
        }
        didJoin = true
        let waiters = joinWaiters
        joinWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }

    func waitUntilJoined() async {
        guard !didJoin else {
            return
        }
        await withCheckedContinuation { continuation in
            joinWaiters.append(continuation)
        }
    }

    func release() {
        guard !isReleased else {
            return
        }
        isReleased = true
        let waiters = releaseWaiters
        releaseWaiters.removeAll()
        waiters.forEach { $0.resume() }
    }
}

final class SyncPushFailOnce {
    private let lock = NSLock()
    private let failingAttempt: Int
    private var attempt = 0

    init(attempt: Int) {
        failingAttempt = attempt
    }

    func shouldFail() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        attempt += 1
        return attempt == failingAttempt
    }
}

final class SyncPushURLProtocol: URLProtocol {
    static var handler: ((URLRequest) async throws -> (HTTPURLResponse, Data))?

    private var loadingTask: Task<Void, Never>?

    override static func canInit(with _: URLRequest) -> Bool {
        true
    }

    override static func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: SyncPushURLProtocolError.missingHandler)
            return
        }

        loadingTask = Task { [weak self, request] in
            guard let self else {
                return
            }
            do {
                let (response, data) = try await handler(request)
                guard !Task.isCancelled else {
                    return
                }
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
    }

    override func stopLoading() {
        loadingTask?.cancel()
        loadingTask = nil
    }
}

enum SyncPushURLProtocolError: Error {
    case missingHandler
    case invalidResponse
    case invalidRequestBody
}

func successResponse(
    for request: URLRequest,
    krwAmount: String = "140000",
    appliedRate: String = "1400",
    rateBaseDate: String? = "2026-07-19"
) throws -> (HTTPURLResponse, Data) {
    guard let requestBody = syncRequestBodyData(from: request) else {
        throw SyncPushURLProtocolError.invalidRequestBody
    }
    let body = try bodyObject(from: requestBody)
    if request.url?.path == "/api/v1/ledgers/import" {
        guard let items = body["entries"] as? [[String: Any]] else {
            throw SyncPushURLProtocolError.invalidRequestBody
        }
        let responseEntries = try items.map { item in
            guard let clientEntryID = item["clientEntryId"] as? String else {
                throw SyncPushURLProtocolError.invalidRequestBody
            }
            return confirmedEntryJSON(
                clientEntryID: clientEntryID,
                krwAmount: krwAmount,
                appliedRate: appliedRate,
                rateBaseDate: rateBaseDate
            )
        }
        return try response(
            for: request,
            data: successEnvelope(
                dataJSON: #"{"entries":[\#(responseEntries.joined(separator: ","))]}"#
            )
        )
    }

    guard let clientEntryID = body["clientEntryId"] as? String else {
        throw SyncPushURLProtocolError.invalidRequestBody
    }
    return try response(
        for: request,
        data: successEnvelope(
            dataJSON: confirmedEntryJSON(
                clientEntryID: clientEntryID,
                krwAmount: krwAmount,
                appliedRate: appliedRate,
                rateBaseDate: rateBaseDate
            )
        )
    )
}

func successVoidResponse(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
    try response(for: request, data: successEnvelope(dataJSON: "null"))
}

private func confirmedEntryJSON(
    clientEntryID: String,
    krwAmount: String,
    appliedRate: String,
    rateBaseDate: String?
) -> String {
    let entry = ledgerEntryJSON(
        krwAmount: krwAmount,
        appliedRate: appliedRate,
        rateBaseDate: rateBaseDate
    )
    return #"{"clientEntryId":"\#(clientEntryID)","ledgerEntry":\#(entry)}"#
}

func syncRequestBodyData(from request: URLRequest) -> Data? {
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else {
        return nil
    }

    stream.open()
    defer { stream.close() }

    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while true {
        let bytesRead = stream.read(&buffer, maxLength: buffer.count)
        guard bytesRead > 0 else {
            break
        }
        data.append(contentsOf: buffer.prefix(bytesRead))
    }
    return data
}

func successEnvelope(dataJSON: String) -> Data {
    Data(#"{"success":true,"data":\#(dataJSON)}"#.utf8)
}

func ledgerEntryJSON(
    krwAmount: String = "140000",
    appliedRate: String = "1400",
    rateBaseDate: String? = "2026-07-19"
) -> String {
    let rateBaseDateJSON = rateBaseDate.map { "\"\($0)\"" } ?? "null"
    return #"""
    {
        "id": 501,
        "transactionType": "EXPENSE",
        "currencyCode": "USD",
        "originalAmount": 100,
        "krwAmount": \#(krwAmount),
        "appliedRate": \#(appliedRate),
        "rateBaseDate": \#(rateBaseDateJSON),
        "transactionDate": "2026-07-20",
        "memo": null,
        "category": {
            "id": 10,
            "code": "FOOD",
            "displayNameKo": "식비",
            "displayNameEn": "Food",
            "icon": null,
            "sortOrder": 1
        },
        "asset": {
            "id": 20,
            "code": "CASH",
            "displayNameKo": "현금",
            "displayNameEn": "Cash",
            "sortOrder": 1
        }
    }
    """#
}

func restoredLedgerEntryJSON(
    id: Int64,
    clientEntryID: UUID?,
    transactionDate: String,
    memo: String? = nil
) -> String {
    let clientEntryIDJSON = clientEntryID.map { "\"\($0.uuidString)\"" } ?? "null"
    let memoJSON = memo.map { "\"\($0)\"" } ?? "null"
    return #"""
    {
        "id": \#(id),
        "clientEntryId": \#(clientEntryIDJSON),
        "transactionType": "EXPENSE",
        "category": {
            "id": 10, "code": "FOOD", "displayNameKo": "식비",
            "displayNameEn": "Food", "icon": null, "sortOrder": 1
        },
        "asset": {
            "id": 20, "code": "CASH", "displayNameKo": "현금",
            "displayNameEn": "Cash", "sortOrder": 1
        },
        "originalAmount": 100,
        "currencyCode": "USD",
        "appliedRate": 1400,
        "krwAmount": 140000,
        "rateBaseDate": "2026-07-19",
        "transactionDate": "\#(transactionDate)",
        "memo": \#(memoJSON)
    }
    """#
}

func changedLedgerEntryJSON(
    id: Int64,
    clientEntryID: UUID?,
    updatedAt: String,
    originalAmount: String = "100",
    appliedRate: String = "1400",
    krwAmount: String = "140000",
    transactionDate: String = "2026-07-20",
    memo: String? = nil
) -> String {
    let clientEntryIDJSON = clientEntryID.map { "\"\($0.uuidString)\"" } ?? "null"
    let memoJSON = memo.map { "\"\($0)\"" } ?? "null"
    return #"""
    {
        "id": \#(id),
        "clientEntryId": \#(clientEntryIDJSON),
        "updatedAt": "\#(updatedAt)",
        "transactionType": "EXPENSE",
        "category": {
            "id": 10, "code": "FOOD", "displayNameKo": "식비",
            "displayNameEn": "Food", "icon": null, "sortOrder": 1
        },
        "asset": {
            "id": 20, "code": "CASH", "displayNameKo": "현금",
            "displayNameEn": "Cash", "sortOrder": 1
        },
        "originalAmount": \#(originalAmount),
        "currencyCode": "USD",
        "appliedRate": \#(appliedRate),
        "krwAmount": \#(krwAmount),
        "rateBaseDate": "2026-07-19",
        "transactionDate": "\#(transactionDate)",
        "memo": \#(memoJSON)
    }
    """#
}

func restorePageJSON(
    entries: [String],
    nextCursor: (transactionDate: String, id: Int64)?,
    hasNext: Bool
) -> String {
    let cursorJSON = nextCursor.map {
        #"{"transactionDate":"\#($0.transactionDate)","id":\#($0.id)}"#
    } ?? "null"
    return #"{"entries":[\#(entries.joined(separator: ","))],"nextCursor":\#(cursorJSON),"hasNext":\#(hasNext)}"#
}

func changesPageJSON(
    entries: [String],
    nextCursor: (updatedAt: String, id: Int64)?,
    hasMore: Bool
) -> String {
    let cursorJSON = nextCursor.map {
        #"{"updatedAt":"\#($0.updatedAt)","id":\#($0.id)}"#
    } ?? "null"
    return #"{"entries":[\#(entries.joined(separator: ","))],"nextCursor":\#(cursorJSON),"hasMore":\#(hasMore)}"#
}

func response(
    for request: URLRequest,
    statusCode: Int = 200,
    data: Data
) throws -> (HTTPURLResponse, Data) {
    guard let url = request.url,
          let response = HTTPURLResponse(
              url: url,
              statusCode: statusCode,
              httpVersion: nil,
              headerFields: nil
          )
    else {
        throw SyncPushURLProtocolError.invalidResponse
    }
    return (response, data)
}

func bodyObject(from data: Data) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        throw SyncPushURLProtocolError.invalidRequestBody
    }
    return object
}
