//
//  WoniStringsWithdrawal.swift
//  woni_app
//

/// 탈퇴·데이터 삭제 문구. `WoniStrings.swift`가 file_length 한계에 닿아 이 묶음만 분리했다.
extension WoniStrings {
    static func withdraw(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "탈퇴하기"
        case .en: "Delete Account"
        }
    }

    static func deleteMyData(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "내 데이터 삭제"
        case .en: "Delete My Data"
        }
    }

    static func withdrawConfirmMessageMember(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "계정과 저장된 모든 거래 내역이 삭제됩니다. 되돌릴 수 없습니다."
        case .en: "Your account and all saved entries will be deleted. This cannot be undone."
        }
    }

    static func withdrawConfirmMessageMemberApple(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "계정과 저장된 모든 거래 내역이 삭제됩니다. 되돌릴 수 없습니다.\n"
            + "삭제를 시작하면 Apple 연동 해제를 위해 Apple 로그인 창이 한 번 더 열립니다."
        case .en: "Your account and all saved entries will be deleted. This cannot be undone.\n"
            + "Sign in with Apple opens once more so we can disconnect your Apple ID."
        }
    }

    static func withdrawConfirmMessageGuest(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "이 앱에 저장된 모든 거래 내역이 삭제됩니다. 되돌릴 수 없습니다."
        case .en: "All entries saved in this app will be deleted. This cannot be undone."
        }
    }

    static func withdrawConfirmAction(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "삭제"
        case .en: "Delete"
        }
    }

    static func withdrawInProgress(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "삭제 중"
        case .en: "Deleting"
        }
    }

    static func withdrawCompletedMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "삭제가 완료되었습니다."
        case .en: "Deletion complete."
        }
    }

    static func withdrawCompletedAppleNote(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "Apple 연동은 해제되지 않았습니다. 설정 > Apple 계정 > 로그인 및 보안 > Apple로 로그인에서 직접 해제해 주세요."
        case .en: "Your Apple sign-in link was not removed. "
            + "Remove it in Settings > Apple Account > Sign-In & Security > Sign in with Apple."
        }
    }

    static func withdrawFailedMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "삭제하지 못했습니다. 데이터는 그대로 남아 있으니 잠시 후 다시 시도해 주세요."
        case .en: "Deletion failed. Your data is still here — please try again later."
        }
    }

    static func withdrawOfflineMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "네트워크에 연결되어 있지 않아 삭제할 수 없습니다. 연결 후 다시 시도해 주세요."
        case .en: "You are offline, so nothing was deleted. Reconnect and try again."
        }
    }
}
