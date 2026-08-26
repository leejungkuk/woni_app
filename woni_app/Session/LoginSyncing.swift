//
//  LoginSyncing.swift
//  woni_app
//

import Foundation

protocol LoginSyncing {
    func beginAccountSwitch() async throws
    func finishAccountSwitch(expectedMemberID: UUID) async -> Bool
    func resumeAccountSwitch(expectedMemberID: UUID?) -> Bool
    func pushPending() async
    func restoreAll() async throws
    func resetSyncStateForAccountSwitch() async throws
    func hasPendingPush() async throws -> Bool
}
