//
//  AIHelperApp.swift
//  AIHelper
//
//  Dynamic Island for monitoring AI coding sessions
//

import SwiftUI

@main
struct AIHelperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var settings = AppSettings.shared

    var body: some Scene {
        Settings {
            SettingsWindowView()
                .environment(\.locale, settings.locale)
        }
        .defaultSize(
            width: SettingsWindowDefaults.defaultContentSize.width,
            height: SettingsWindowDefaults.defaultContentSize.height
        )
    }
}
