// QingpingMenuBarApp.swift
// App entry point. Configures a menu bar-only app (no dock icon) using MenuBarExtra.
// Runs Keychain migration on launch, then creates the shared view model that drives
// all polling, API calls, and UI state.

import SwiftUI

@main
struct QingpingMenuBarApp: App {
    @State private var viewModel: AirQualityViewModel

    init() {
        // Migrate credentials from legacy Keychain service name before anything reads them
        CredentialsStore.migrateIfNeeded()
        _viewModel = State(initialValue: AirQualityViewModel())
    }

    var body: some Scene {
        MenuBarExtra {
            MenuBarPopoverView(viewModel: viewModel)
        } label: {
            MenuBarLabel(viewModel: viewModel)
        }
        .menuBarExtraStyle(.window)
    }
}
