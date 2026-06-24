//
//  woni_appApp.swift
//  woni_app
//
//  Created by J on 6/2/26.
//

import SwiftUI

@main
struct WoniApp: App {
    init() {
        WoniFont.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            AddExpenseView(onClose: {})
        }
    }
}
