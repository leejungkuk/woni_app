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

    static func withdrawConfirmTitleMember(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "정말 탈퇴하시겠습니까?"
        case .en: "Delete your account?"
        }
    }

    static func withdrawConfirmTitleGuest(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "정말 삭제하시겠습니까?"
        case .en: "Delete all your data?"
        }
    }

    static func withdrawConfirmMessageMember(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "해당 계정에 저장된 모든 데이터가 삭제됩니다.\n삭제된 계정 및 데이터는 복구할 수 없습니다."
        case .en: "All data saved in this account will be deleted.\n"
            + "Deleted accounts and data cannot be recovered."
        }
    }

    static func withdrawConfirmMessageMemberApple(_ language: AppLanguage) -> String {
        switch language {
        case .ko: withdrawConfirmMessageMember(language)
            + "\n\nApple 연동 해제를 위해\nApple 로그인 창이 한 번 더 열립니다."
        case .en: withdrawConfirmMessageMember(language)
            + "\n\nSign in with Apple opens once more\nto disconnect your Apple ID."
        }
    }

    /// 비회원에게만 노출한다. 익명 식별자는 연락 수단이 없어 사전 통지를 보낼 방법이
    /// 없으므로, 방침 제3조 제2항의 365일 보유기간을 설정 화면에서 직접 알린다.
    /// 기기 데이터가 남는다는 뒷문장을 빼면 "내 기록이 사라진다"로 읽힌다.
    static func guestRetentionNotice(_ language: AppLanguage) -> String {
        switch language {
        case .ko:
            "서버에 보관된 백업은 마지막 이용일로부터 365일이 지나면 자동으로 삭제됩니다."
                + " 기기에 저장된 내역은 그대로 남습니다."
        case .en:
            "Your server backup is deleted automatically 365 days after your last use."
                + " Entries saved on this device are not affected."
        }
    }

    static func withdrawConfirmMessageGuest(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "이 앱에 저장된 모든 내역이 삭제됩니다.\n삭제된 데이터는 복구할 수 없습니다."
        case .en: "All entries saved in this app will be deleted.\nDeleted data cannot be recovered."
        }
    }

    static func purgeConfirmMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "저장된 모든 내역이 삭제됩니다.\n계정과 로그인은 그대로 유지됩니다.\n삭제된 내역은 복구할 수 없습니다."
        case .en: "All saved entries will be deleted.\nYour account and sign-in remain active.\n"
            + "Deleted entries cannot be recovered."
        }
    }

    static func withdrawActionMember(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "탈퇴"
        case .en: "Delete Account"
        }
    }

    static func withdrawActionGuest(_ language: AppLanguage) -> String {
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

    static func withdrawCompletedToastMember(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "계정 탈퇴가 완료되었습니다."
        case .en: "Your account has been deleted."
        }
    }

    static func withdrawCompletedToastGuest(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "모든 내역이 삭제되었습니다."
        case .en: "All entries have been deleted."
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

    static func purgePendingMessage(_ language: AppLanguage) -> String {
        switch language {
        case .ko: "삭제를 완료하지 못했습니다. 연결되면 자동으로 이어서 완료됩니다."
        case .en: "Deletion could not be completed. It will automatically continue when you reconnect."
        }
    }
}
