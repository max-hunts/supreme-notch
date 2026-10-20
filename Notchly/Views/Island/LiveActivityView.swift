//
//  LiveActivityView.swift
//  Notchly
//
//  A live activity in the closed notch wings, like the iPhone Dynamic Island. Today
//  that is the countdown to a meeting after its reminder is dismissed.
//

import Combine
import SwiftUI
import AppKit

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
    private var digitTask: Task<Void, Never>?

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
        digitTask?.cancel()
        digitTask = nil
        guard let meeting, meeting.start > now else { return }

        // The countdown draws itself, so the island never hears it go from 10:00 to 9:59.
        // Tell it then, so the countdown's wing narrows by a digit.
        let digitDrop = meeting.start.addingTimeInterval(-600)
        if digitDrop > now {
            digitTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: .seconds(digitDrop.timeIntervalSince(Date()) + 0.1))
                guard !Task.isCancelled else { return }
                self?.objectWillChange.send()
            }
        }

        tickTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(max(0.5, meeting.start.timeIntervalSince(Date()) + 0.2)))
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }
}

/// The closed-notch content for a live activity: an icon and title in the left wing, a
/// countdown in the right wing. The space over the camera notch stays empty. Each wing is
/// only as wide as its content, and the title is capped so the island fits its window.
struct LiveActivityWingsView: View {
    let activity: LiveActivity
    let size: CGSize
    var horizontalOffset: CGFloat = 0
    let hoverOffsetY: CGFloat

    static let titleFont = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let countdownFont = NSFont.monospacedDigitSystemFont(ofSize: 12.5, weight: .semibold)
    static let iconSize: CGFloat = 16
    static let iconSpacing: CGFloat = 6
    static let maxTitleWidth: CGFloat = 90

    static func inset(closedHeight: CGFloat) -> CGFloat {
        ClosedWings.inset(closedHeight: closedHeight, contentHeight: countdownFont.pointSize)
    }

    static func titleWidth(_ activity: LiveActivity) -> CGFloat {
        min(ClosedWings.textWidth(activity.title, font: titleFont), maxTitleWidth)
    }

    static func wingWidths(
        for activity: LiveActivity,
        closedHeight: CGFloat,
        cameraHousingInset: CGFloat
    ) -> (left: CGFloat, right: CGFloat) {
        let inset = inset(closedHeight: closedHeight)
        let left = iconSize + iconSpacing + titleWidth(activity)
        let right = ClosedWings.countdownWidth(until: activity.date, font: countdownFont)
        return (
            ClosedWings.width(content: left, inset: inset, cameraHousingInset: cameraHousingInset),
            ClosedWings.width(content: right, inset: inset, cameraHousingInset: cameraHousingInset)
        )
    }

    var body: some View {
        let inset = Self.inset(closedHeight: size.height)
        ClosedWingsView(
            size: size,
            leadingInset: inset,
            trailingInset: inset,
            horizontalOffset: horizontalOffset,
            hoverOffsetY: hoverOffsetY
        ) {
            HStack(spacing: Self.iconSpacing) {
                Self.leadingIcon
                    .frame(width: Self.iconSize, height: Self.iconSize)
                Text(verbatim: activity.title)
                    .font(Font(Self.titleFont))
                    .foregroundStyle(.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(width: Self.titleWidth(activity), alignment: .leading)
            }
        } trailing: {
            Self.countdown(until: activity.date)
        }
    }

    fileprivate static var leadingIcon: some View {
        Image(systemName: "calendar")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(tint)
    }

    fileprivate static func countdown(until date: Date) -> some View {
        Text(timerInterval: Date()...max(Date(), date), countsDown: true, showsHours: false)
            .font(Font(countdownFont))
            .foregroundStyle(tint)
            .lineLimit(1)
            .fixedSize()
    }

    private static var tint: Color {
        Color(red: 1.0, green: 0.42, blue: 0.4)
    }
}

/// The compact form for the music player's right wing: icon and countdown only, in place
/// of the status ring. The album art keeps the left wing.
struct LiveActivityBadge: View {
    let activity: LiveActivity

    static let iconSize: CGFloat = 14
    static let spacing: CGFloat = 5

    static func wingWidth(for activity: LiveActivity, closedHeight: CGFloat, cameraHousingInset: CGFloat) -> CGFloat {
        let content = iconSize + spacing
            + ClosedWings.countdownWidth(until: activity.date, font: LiveActivityWingsView.countdownFont)
        return ClosedWings.width(
            content: content,
            inset: LiveActivityWingsView.inset(closedHeight: closedHeight),
            cameraHousingInset: cameraHousingInset
        )
    }

    var body: some View {
        HStack(spacing: Self.spacing) {
            LiveActivityWingsView.leadingIcon
                .frame(width: Self.iconSize, height: Self.iconSize)
            LiveActivityWingsView.countdown(until: activity.date)
        }
        .fixedSize()
    }
}
