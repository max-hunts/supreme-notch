//
//  LiveActivityView.swift
//  Notchly
//
//  A live activity in the closed notch wings, like the iPhone Dynamic Island. Today
//  that is the countdown to a meeting after its reminder is dismissed.
//

import Combine
import SwiftUI

nonisolated struct LiveActivity: Equatable {
    enum Kind: Equatable {
        case meeting
    }

    let kind: Kind
    let title: String
    /// When the meeting starts.
    let date: Date
}

@MainActor
final class LiveActivityModel: ObservableObject {
    @Published private(set) var activity: LiveActivity?

    private let settingsManager: SettingsManager
    private let calendar: CalendarGlanceManager
    /// The meeting whose countdown you closed; it stays hidden until the next meeting.
    private var dismissedMeeting: UpcomingMeeting?
    private var cancellables = Set<AnyCancellable>()
    private var tickTask: Task<Void, Never>?

    init(settingsManager: SettingsManager, calendar: CalendarGlanceManager) {
        self.settingsManager = settingsManager
        self.calendar = calendar

        // Published values emit before they change, so read them on the next main-queue turn.
        Publishers.MergeMany(
            calendar.$upcomingMeeting.map { _ in () }.eraseToAnyPublisher(),
            settingsManager.$showMeetingCountdown.map { _ in () }.eraseToAnyPublisher(),
            settingsManager.$showCalendarGlance.map { _ in () }.eraseToAnyPublisher()
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] in self?.refresh() }
        .store(in: &cancellables)
    }

    func refresh() {
        let now = Date()
        var meeting = settingsManager.showCalendarGlance && settingsManager.showMeetingCountdown ? calendar.upcomingMeeting : nil
        if meeting != nil, meeting == dismissedMeeting { meeting = nil }
        let next = Self.resolve(meeting: meeting, now: now)
        if next != activity {
            activity = next
        }
        scheduleTick(for: meeting, now: now)
    }

    /// Hides the countdown for the current meeting only.
    func dismissMeeting() {
        dismissedMeeting = calendar.upcomingMeeting
        refresh()
    }

    nonisolated static func resolve(meeting: UpcomingMeeting?, now: Date) -> LiveActivity? {
        guard let meeting, meeting.start > now else { return nil }
        return LiveActivity(kind: .meeting, title: meeting.title, date: meeting.start)
    }

    /// Clears the countdown the moment the meeting starts.
    private func scheduleTick(for meeting: UpcomingMeeting?, now: Date) {
        tickTask?.cancel()
        tickTask = nil
        guard let meeting, meeting.start > now else { return }

        tickTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0.5, meeting.start.timeIntervalSince(Date()) + 0.2)))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}

/// The closed-notch content for a live activity: an icon and title in the left wing, a
/// countdown in the right wing. The space over the camera notch stays empty.
struct LiveActivityWingsView: View {
    let activity: LiveActivity
    let size: CGSize
    let notchWidth: CGFloat
    let hoverOffsetY: CGFloat

    private static let padding: CGFloat = 12

    var body: some View {
        let wingWidth = max(24, (size.width - notchWidth) / 2 - Self.padding - 6)

        HStack(spacing: 0) {
            HStack(spacing: 6) {
                leadingIcon
                    .frame(width: 16, height: 16)
                Text(verbatim: activity.title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .frame(width: wingWidth, alignment: .leading)
            .clipped()

            Spacer(minLength: 0)

            trailing
                .frame(width: wingWidth, alignment: .trailing)
        }
        .padding(.horizontal, Self.padding)
        .frame(width: size.width, height: size.height)
        .offset(y: hoverOffsetY)
    }

    fileprivate var leadingIcon: some View {
        Image(systemName: "calendar")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
    }

    fileprivate var trailing: some View {
        Text(timerInterval: Date()...max(Date(), activity.date), countsDown: true, showsHours: false)
            .font(.system(size: 12.5, weight: .semibold).monospacedDigit())
            .foregroundStyle(tint)
            .lineLimit(1)
    }

    private var tint: Color {
        Color(red: 1.0, green: 0.42, blue: 0.4)
    }
}

/// The compact form for the music player's closed wings: icon and countdown only, in
/// place of the waveform. The album art stays in the left wing.
struct LiveActivityBadge: View {
    let activity: LiveActivity

    var body: some View {
        let wings = LiveActivityWingsView(activity: activity, size: .zero, notchWidth: 0, hoverOffsetY: 0)
        HStack(spacing: 5) {
            wings.leadingIcon
                .frame(width: 14, height: 14)
            wings.trailing
        }
        .fixedSize()
    }
}
