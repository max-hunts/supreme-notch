//
//  CalendarSourcesPicker.swift
//  Notchly
//
//  Lets you choose which calendars the meeting reminder reads, grouped by account.
//  Google, Exchange and iCloud calendars appear here once their account is added in
//  System Settings > Internet Accounts with Calendars turned on.
//

import AppKit
import EventKit
import SwiftUI

struct CalendarSourcesPicker: View {
    @ObservedObject var settingsManager: SettingsManager
    @State private var groups: [(account: String, calendars: [EKCalendar])] = []
    @State private var hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
    private let store = EKEventStore()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Calendars")
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Button("Add Google Account…") {
                    if let url = URL(string: "x-apple.systempreferences:com.apple.Internet-Accounts-Settings.extension") {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }

            if !hasAccess {
                Text("Turn on Upcoming Meeting to allow calendar access.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else if groups.isEmpty {
                Text("No calendars found.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            } else {
                ForEach(groups, id: \.account) { group in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(group.account)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                            Toggle(isOn: binding(for: calendar)) {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color(nsColor: calendar.color ?? .gray))
                                        .frame(width: 8, height: 8)
                                    Text(calendar.title)
                                        .font(.system(size: 12.5))
                                }
                            }
                            .toggleStyle(.checkbox)
                        }
                    }
                }
            }

            Text("To use Google Calendar, add your Google account in Internet Accounts with Calendars on. It then shows up here; BetterNotch never signs in to Google itself.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onAppear(perform: reload)
        .onReceive(NotificationCenter.default.publisher(for: .EKEventStoreChanged)) { _ in reload() }
    }

    private func reload() {
        hasAccess = EKEventStore.authorizationStatus(for: .event) == .fullAccess
        guard hasAccess else { groups = []; return }
        store.refreshSourcesIfNecessary()
        let byAccount = Dictionary(grouping: store.calendars(for: .event)) { $0.source?.title ?? "Other" }
        groups = byAccount
            .map { (account: $0.key, calendars: $0.value.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }) }
            .sorted { $0.account.localizedCaseInsensitiveCompare($1.account) == .orderedAscending }
    }

    private func binding(for calendar: EKCalendar) -> Binding<Bool> {
        Binding(
            get: { !settingsManager.calendarExcludedIDs.contains(calendar.calendarIdentifier) },
            set: { included in
                var excluded = settingsManager.calendarExcludedIDs
                excluded.removeAll { $0 == calendar.calendarIdentifier }
                if !included { excluded.append(calendar.calendarIdentifier) }
                settingsManager.calendarExcludedIDs = excluded
            }
        )
    }
}
