//
//  SettingsManager.swift
//  Notchly
//
//  Created by n0xbyte on 16.03.2026.
//

import Foundation
import Combine
import ServiceManagement

enum DisplayTarget: String, CaseIterable {
    case main
    case builtIn

    var title: String {
        switch self {
        case .main:
            return "Main display"
        case .builtIn:
            return "Built in display"
        }
    }

    var subtitle: String {
        switch self {
        case .main:
            return "Follow the active main screen."
        case .builtIn:
            return "Prefer the MacBook display."
        }
    }

    var symbolName: String {
        switch self {
        case .main:
            return "display"
        case .builtIn:
            return "laptopcomputer"
        }
    }
}

enum StatusDisplayStyle: String, CaseIterable, Identifiable {
    case line
    case percent

    var id: String { rawValue }

    var title: String {
        switch self {
        case .line:
            return "Line"
        case .percent:
            return "Percent"
        }
    }
}

@MainActor
final class SettingsManager: ObservableObject {
    private enum Defaults {
        static let showBattery = true
        static let showMusic = true
        static let islandWidth = 318.0
        static let cameraSpacingAdjustment = 0.0
        static let displayTarget = DisplayTarget.builtIn
        static let lowBatteryThreshold = 20
        static let musicPreviewDuration = 2.0
        static let enableSpotifyAppleScriptControl = false
        static let enableAppleMusicAppleScriptControl = false
        static let launchAtLogin = false
        static let enableLockSound = true
        static let hideNotchWhenFullscreen = false
        static let showFocusAnimations = true
        static let focusAnimationDuration = 2.0
        static let hideFocusLabel = false
        static let showBrightnessStatus = true
        static let showBrightnessLine = true
        static let brightnessLineWidth = 36.0
        static let showBrightnessPercent = false
        static let showSoundStatus = true
        static let showSoundLine = true
        static let soundLineWidth = 36.0
        static let showSoundPercent = false
        static let showNetworkStatus = true
        static let enableCodexApprovalAlertSound = false
        static let enableCodexCompletedAlertSound = false
        static let codexCompletedAlertDuration = 2.2
        static let approveFromNotch = true
        static let approvalWaitSeconds = 45.0
        static let showCompletionSummary = true
        static let showDownloadGlance = true
        static let showCalendarGlance = true
        static let calendarLeadMinutes = 5.0
        static let showAirPodsGlance = true
        static let showAccessoryBatteryWarning = true
        static let showDriveGlance = true
        static let showLowDiskWarning = true
        static let showDownloadProgress = true
        static let showPortsPanel = true
        static let showAgentSessions = true
        static let showMeetingCountdown = true
        static let showUsageTab = true
        static let usageBarStyle = UsageBarStyle.colorHangs
        static let showSystemTab = true
        static let showFileShelf = true
        static let showMicMute = true
        static let openOnHover = true
        static let showQuickNote = true
        static let showOutputPicker = true
        static let showAudioOutputGlance = true
    }

    @Published var showBattery: Bool {
        didSet { UserDefaults.standard.set(showBattery, forKey: "showBattery") }
    }

    @Published var showMusic: Bool {
        didSet { UserDefaults.standard.set(showMusic, forKey: "showMusic") }
    }

    /// Extra space between the closed notch's glyphs and the camera, in points. Negative
    /// moves them closer.
    @Published var cameraSpacingAdjustment: Double {
        didSet { UserDefaults.standard.set(cameraSpacingAdjustment, forKey: "cameraSpacingAdjustment") }
    }

    static let cameraSpacingRange: ClosedRange<Double> = -4...4

    var isCameraSpacingDefault: Bool { cameraSpacingAdjustment == Defaults.cameraSpacingAdjustment }

    func resetCameraSpacing() { cameraSpacingAdjustment = Defaults.cameraSpacingAdjustment }

    @Published var islandWidth: Double {
        didSet { UserDefaults.standard.set(islandWidth, forKey: "islandWidth") }
    }

    @Published var displayTarget: DisplayTarget {
        didSet { UserDefaults.standard.set(displayTarget.rawValue, forKey: "displayTarget") }
    }

    @Published var lowBatteryThreshold: Int {
        didSet { UserDefaults.standard.set(lowBatteryThreshold, forKey: "lowBatteryThreshold") }
    }
    
    @Published var musicPreviewDuration: Double {
        didSet { UserDefaults.standard.set(musicPreviewDuration, forKey: "musicPreviewDuration") }
    }

    @Published var enableSpotifyAppleScriptControl: Bool {
        didSet { UserDefaults.standard.set(enableSpotifyAppleScriptControl, forKey: "enableSpotifyAppleScriptControl") }
    }

    @Published var enableAppleMusicAppleScriptControl: Bool {
        didSet { UserDefaults.standard.set(enableAppleMusicAppleScriptControl, forKey: "enableAppleMusicAppleScriptControl") }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            applyLaunchAtLogin(launchAtLogin)
        }
    }
    
    @Published var enableLockSound: Bool {
        didSet { UserDefaults.standard.set(enableLockSound, forKey: "enableLockSound") }
    }

    @Published var hideNotchWhenFullscreen: Bool {
        didSet { UserDefaults.standard.set(hideNotchWhenFullscreen, forKey: "hideNotchWhenFullscreen") }
    }

    @Published var showFocusAnimations: Bool {
        didSet { UserDefaults.standard.set(showFocusAnimations, forKey: "showFocusAnimations") }
    }

    @Published var focusAnimationDuration: Double {
        didSet { UserDefaults.standard.set(focusAnimationDuration, forKey: "focusAnimationDuration") }
    }

    @Published var hideFocusLabel: Bool {
        didSet { UserDefaults.standard.set(hideFocusLabel, forKey: "hideFocusLabel") }
    }

    @Published var showBrightnessStatus: Bool {
        didSet { UserDefaults.standard.set(showBrightnessStatus, forKey: "showBrightnessStatus") }
    }

    @Published var showBrightnessLine: Bool {
        didSet { UserDefaults.standard.set(showBrightnessLine, forKey: "showBrightnessLine") }
    }

    @Published var brightnessLineWidth: Double {
        didSet { UserDefaults.standard.set(brightnessLineWidth, forKey: "brightnessLineWidth") }
    }

    @Published var showBrightnessPercent: Bool {
        didSet { UserDefaults.standard.set(showBrightnessPercent, forKey: "showBrightnessPercent") }
    }

    @Published var showSoundStatus: Bool {
        didSet { UserDefaults.standard.set(showSoundStatus, forKey: "showSoundStatus") }
    }

    @Published var showSoundLine: Bool {
        didSet { UserDefaults.standard.set(showSoundLine, forKey: "showSoundLine") }
    }

    @Published var soundLineWidth: Double {
        didSet { UserDefaults.standard.set(soundLineWidth, forKey: "soundLineWidth") }
    }

    @Published var showSoundPercent: Bool {
        didSet { UserDefaults.standard.set(showSoundPercent, forKey: "showSoundPercent") }
    }

    @Published var showNetworkStatus: Bool {
        didSet { UserDefaults.standard.set(showNetworkStatus, forKey: "showNetworkStatus") }
    }

    var brightnessDisplayStyle: StatusDisplayStyle {
        get { showBrightnessLine ? .line : .percent }
        set {
            switch newValue {
            case .line:
                showBrightnessLine = true
                showBrightnessPercent = false
            case .percent:
                showBrightnessLine = false
                showBrightnessPercent = true
            }
        }
    }

    var soundDisplayStyle: StatusDisplayStyle {
        get { showSoundLine ? .line : .percent }
        set {
            switch newValue {
            case .line:
                showSoundLine = true
                showSoundPercent = false
            case .percent:
                showSoundLine = false
                showSoundPercent = true
            }
        }
    }

    @Published var enableCodexApprovalAlertSound: Bool {
        didSet { UserDefaults.standard.set(enableCodexApprovalAlertSound, forKey: "enableCodexApprovalAlertSound") }
    }

    @Published var enableCodexCompletedAlertSound: Bool {
        didSet { UserDefaults.standard.set(enableCodexCompletedAlertSound, forKey: "enableCodexCompletedAlertSound") }
    }

    @Published var codexCompletedAlertDuration: Double {
        didSet { UserDefaults.standard.set(codexCompletedAlertDuration, forKey: "codexCompletedAlertDuration") }
    }

    @Published var approveFromNotch: Bool {
        didSet { UserDefaults.standard.set(approveFromNotch, forKey: "approveFromNotch") }
    }

    @Published var approvalWaitSeconds: Double {
        didSet { UserDefaults.standard.set(approvalWaitSeconds, forKey: "approvalWaitSeconds") }
    }

    @Published var showCompletionSummary: Bool {
        didSet { UserDefaults.standard.set(showCompletionSummary, forKey: "showCompletionSummary") }
    }

    @Published var showDownloadGlance: Bool {
        didSet { UserDefaults.standard.set(showDownloadGlance, forKey: "showDownloadGlance") }
    }

    @Published var showCalendarGlance: Bool {
        didSet { UserDefaults.standard.set(showCalendarGlance, forKey: "showCalendarGlance") }
    }

    /// Calendars the meeting reminder skips, by EventKit calendar identifier.
    @Published var calendarExcludedIDs: [String] {
        didSet { UserDefaults.standard.set(calendarExcludedIDs, forKey: "calendarExcludedIDs") }
    }

    @Published var calendarLeadMinutes: Double {
        didSet { UserDefaults.standard.set(calendarLeadMinutes, forKey: "calendarLeadMinutes") }
    }

    @Published var showAirPodsGlance: Bool {
        didSet { UserDefaults.standard.set(showAirPodsGlance, forKey: "showAirPodsGlance") }
    }

    @Published var showAccessoryBatteryWarning: Bool {
        didSet { UserDefaults.standard.set(showAccessoryBatteryWarning, forKey: "showAccessoryBatteryWarning") }
    }

    @Published var showDriveGlance: Bool {
        didSet { UserDefaults.standard.set(showDriveGlance, forKey: "showDriveGlance") }
    }

    @Published var showLowDiskWarning: Bool {
        didSet { UserDefaults.standard.set(showLowDiskWarning, forKey: "showLowDiskWarning") }
    }

    @Published var showDownloadProgress: Bool {
        didSet { UserDefaults.standard.set(showDownloadProgress, forKey: "showDownloadProgress") }
    }

    @Published var showPortsPanel: Bool {
        didSet { UserDefaults.standard.set(showPortsPanel, forKey: "showPortsPanel") }
    }

    @Published var showAgentSessions: Bool {
        didSet { UserDefaults.standard.set(showAgentSessions, forKey: "showAgentSessions") }
    }

    @Published var showMeetingCountdown: Bool {
        didSet { UserDefaults.standard.set(showMeetingCountdown, forKey: "showMeetingCountdown") }
    }

    @Published var showUsageTab: Bool {
        didSet { UserDefaults.standard.set(showUsageTab, forKey: "showUsageTab") }
    }

    @Published var usageBarStyle: UsageBarStyle {
        didSet { UserDefaults.standard.set(usageBarStyle.rawValue, forKey: "usageBarStyle") }
    }

    @Published var showSystemTab: Bool {
        didSet { UserDefaults.standard.set(showSystemTab, forKey: "showSystemTab") }
    }

    @Published var showFileShelf: Bool {
        didSet { UserDefaults.standard.set(showFileShelf, forKey: "showFileShelf") }
    }

    @Published var showMicMute: Bool {
        didSet { UserDefaults.standard.set(showMicMute, forKey: "showMicMute") }
    }

    @Published var openOnHover: Bool {
        didSet { UserDefaults.standard.set(openOnHover, forKey: "openOnHover") }
    }

    @Published var showQuickNote: Bool {
        didSet { UserDefaults.standard.set(showQuickNote, forKey: "showQuickNote") }
    }

    @Published var showOutputPicker: Bool {
        didSet { UserDefaults.standard.set(showOutputPicker, forKey: "showOutputPicker") }
    }

    @Published var showAudioOutputGlance: Bool {
        didSet { UserDefaults.standard.set(showAudioOutputGlance, forKey: "showAudioOutputGlance") }
    }

    init() {
        self.showBattery = UserDefaults.standard.object(forKey: "showBattery") as? Bool ?? Defaults.showBattery
        self.showMusic = UserDefaults.standard.object(forKey: "showMusic") as? Bool ?? Defaults.showMusic
        self.islandWidth = UserDefaults.standard.object(forKey: "islandWidth") as? Double ?? Defaults.islandWidth
        self.cameraSpacingAdjustment = (UserDefaults.standard.object(forKey: "cameraSpacingAdjustment") as? Double)
            .map { min(max($0, Self.cameraSpacingRange.lowerBound), Self.cameraSpacingRange.upperBound) }
            ?? Defaults.cameraSpacingAdjustment
        self.displayTarget = Self.loadDisplayTarget()
        self.lowBatteryThreshold = UserDefaults.standard.object(forKey: "lowBatteryThreshold") as? Int ?? Defaults.lowBatteryThreshold
        self.musicPreviewDuration = UserDefaults.standard.object(forKey: "musicPreviewDuration") as? Double ?? Defaults.musicPreviewDuration
        self.enableSpotifyAppleScriptControl = UserDefaults.standard.object(forKey: "enableSpotifyAppleScriptControl") as? Bool ?? Defaults.enableSpotifyAppleScriptControl
        self.enableAppleMusicAppleScriptControl = UserDefaults.standard.object(forKey: "enableAppleMusicAppleScriptControl") as? Bool ?? Defaults.enableAppleMusicAppleScriptControl

        let savedLaunchAtLogin = UserDefaults.standard.object(forKey: "launchAtLogin") as? Bool
        let systemLaunchAtLogin = SMAppService.mainApp.status == .enabled
        self.launchAtLogin = savedLaunchAtLogin ?? systemLaunchAtLogin
        self.enableLockSound = UserDefaults.standard.object(forKey: "enableLockSound") as? Bool ?? Defaults.enableLockSound
        self.hideNotchWhenFullscreen = UserDefaults.standard.object(forKey: "hideNotchWhenFullscreen") as? Bool ?? Defaults.hideNotchWhenFullscreen
        self.showFocusAnimations = UserDefaults.standard.object(forKey: "showFocusAnimations") as? Bool ?? Defaults.showFocusAnimations
        self.focusAnimationDuration = UserDefaults.standard.object(forKey: "focusAnimationDuration") as? Double ?? Defaults.focusAnimationDuration
        self.hideFocusLabel = UserDefaults.standard.object(forKey: "hideFocusLabel") as? Bool ?? Defaults.hideFocusLabel
        self.showBrightnessStatus = UserDefaults.standard.object(forKey: "showBrightnessStatus") as? Bool ?? Defaults.showBrightnessStatus
        self.showBrightnessLine = UserDefaults.standard.object(forKey: "showBrightnessLine") as? Bool ?? Defaults.showBrightnessLine
        self.brightnessLineWidth = UserDefaults.standard.object(forKey: "brightnessLineWidth") as? Double ?? Defaults.brightnessLineWidth
        self.showBrightnessPercent = UserDefaults.standard.object(forKey: "showBrightnessPercent") as? Bool ?? Defaults.showBrightnessPercent
        self.showSoundStatus = UserDefaults.standard.object(forKey: "showSoundStatus") as? Bool ?? Defaults.showSoundStatus
        self.showSoundLine = UserDefaults.standard.object(forKey: "showSoundLine") as? Bool ?? Defaults.showSoundLine
        self.soundLineWidth = UserDefaults.standard.object(forKey: "soundLineWidth") as? Double ?? Defaults.soundLineWidth
        self.showSoundPercent = UserDefaults.standard.object(forKey: "showSoundPercent") as? Bool ?? Defaults.showSoundPercent
        self.showNetworkStatus = UserDefaults.standard.object(forKey: "showNetworkStatus") as? Bool ?? Defaults.showNetworkStatus
        let legacyCodexAlertSound = UserDefaults.standard.object(forKey: "enableCodexAlertSound") as? Bool
        self.enableCodexApprovalAlertSound = UserDefaults.standard.object(forKey: "enableCodexApprovalAlertSound") as? Bool ?? legacyCodexAlertSound ?? Defaults.enableCodexApprovalAlertSound
        self.enableCodexCompletedAlertSound = UserDefaults.standard.object(forKey: "enableCodexCompletedAlertSound") as? Bool ?? legacyCodexAlertSound ?? Defaults.enableCodexCompletedAlertSound
        self.codexCompletedAlertDuration = UserDefaults.standard.object(forKey: "codexCompletedAlertDuration") as? Double ?? Defaults.codexCompletedAlertDuration

        self.approveFromNotch = UserDefaults.standard.object(forKey: "approveFromNotch") as? Bool ?? Defaults.approveFromNotch
        self.approvalWaitSeconds = UserDefaults.standard.object(forKey: "approvalWaitSeconds") as? Double ?? Defaults.approvalWaitSeconds
        self.showCompletionSummary = UserDefaults.standard.object(forKey: "showCompletionSummary") as? Bool ?? Defaults.showCompletionSummary
        self.showDownloadGlance = UserDefaults.standard.object(forKey: "showDownloadGlance") as? Bool ?? Defaults.showDownloadGlance
        self.showCalendarGlance = UserDefaults.standard.object(forKey: "showCalendarGlance") as? Bool ?? Defaults.showCalendarGlance
        self.calendarLeadMinutes = UserDefaults.standard.object(forKey: "calendarLeadMinutes") as? Double ?? Defaults.calendarLeadMinutes
        self.calendarExcludedIDs = UserDefaults.standard.stringArray(forKey: "calendarExcludedIDs") ?? []
        self.showAirPodsGlance = UserDefaults.standard.object(forKey: "showAirPodsGlance") as? Bool ?? Defaults.showAirPodsGlance

        self.showAccessoryBatteryWarning = UserDefaults.standard.object(forKey: "showAccessoryBatteryWarning") as? Bool ?? Defaults.showAccessoryBatteryWarning
        self.showDriveGlance = UserDefaults.standard.object(forKey: "showDriveGlance") as? Bool ?? Defaults.showDriveGlance
        self.showLowDiskWarning = UserDefaults.standard.object(forKey: "showLowDiskWarning") as? Bool ?? Defaults.showLowDiskWarning
        self.showDownloadProgress = UserDefaults.standard.object(forKey: "showDownloadProgress") as? Bool ?? Defaults.showDownloadProgress
        self.showPortsPanel = UserDefaults.standard.object(forKey: "showPortsPanel") as? Bool ?? Defaults.showPortsPanel
        self.showAgentSessions = UserDefaults.standard.object(forKey: "showAgentSessions") as? Bool ?? Defaults.showAgentSessions
        self.showMeetingCountdown = UserDefaults.standard.object(forKey: "showMeetingCountdown") as? Bool ?? Defaults.showMeetingCountdown
        self.showUsageTab = UserDefaults.standard.object(forKey: "showUsageTab") as? Bool ?? Defaults.showUsageTab
        self.usageBarStyle = UserDefaults.standard.string(forKey: "usageBarStyle").flatMap(UsageBarStyle.init(rawValue:))
            ?? Defaults.usageBarStyle
        self.showSystemTab = UserDefaults.standard.object(forKey: "showSystemTab") as? Bool ?? Defaults.showSystemTab
        self.showFileShelf = UserDefaults.standard.object(forKey: "showFileShelf") as? Bool ?? Defaults.showFileShelf
        self.showMicMute = UserDefaults.standard.object(forKey: "showMicMute") as? Bool ?? Defaults.showMicMute
        self.openOnHover = UserDefaults.standard.object(forKey: "openOnHover") as? Bool ?? Defaults.openOnHover
        self.showQuickNote = UserDefaults.standard.object(forKey: "showQuickNote") as? Bool ?? Defaults.showQuickNote
        self.showOutputPicker = UserDefaults.standard.object(forKey: "showOutputPicker") as? Bool ?? Defaults.showOutputPicker
        self.showAudioOutputGlance = UserDefaults.standard.object(forKey: "showAudioOutputGlance") as? Bool ?? Defaults.showAudioOutputGlance

        normalizeStatusDisplayModes()
    }

    func refreshLaunchAtLoginStatus() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func resetGeneralSettings() {
        islandWidth = Defaults.islandWidth
        cameraSpacingAdjustment = Defaults.cameraSpacingAdjustment
        displayTarget = Defaults.displayTarget
        launchAtLogin = Defaults.launchAtLogin
        enableLockSound = Defaults.enableLockSound
        hideNotchWhenFullscreen = Defaults.hideNotchWhenFullscreen
        showNetworkStatus = Defaults.showNetworkStatus
    }

    func resetFocusSettings() {
        showFocusAnimations = Defaults.showFocusAnimations
        focusAnimationDuration = Defaults.focusAnimationDuration
        hideFocusLabel = Defaults.hideFocusLabel
    }

    func resetBatterySettings() {
        showBattery = Defaults.showBattery
        lowBatteryThreshold = Defaults.lowBatteryThreshold
    }

    func resetBrightnessSettings() {
        showBrightnessStatus = Defaults.showBrightnessStatus
        showBrightnessLine = Defaults.showBrightnessLine
        brightnessLineWidth = Defaults.brightnessLineWidth
        showBrightnessPercent = Defaults.showBrightnessPercent
    }

    func resetSoundSettings() {
        showSoundStatus = Defaults.showSoundStatus
        showSoundLine = Defaults.showSoundLine
        soundLineWidth = Defaults.soundLineWidth
        showSoundPercent = Defaults.showSoundPercent
    }

    func resetMusicSettings() {
        showMusic = Defaults.showMusic
        musicPreviewDuration = Defaults.musicPreviewDuration
        enableSpotifyAppleScriptControl = Defaults.enableSpotifyAppleScriptControl
        enableAppleMusicAppleScriptControl = Defaults.enableAppleMusicAppleScriptControl
    }

    func resetCodexSettings() {
        enableCodexApprovalAlertSound = Defaults.enableCodexApprovalAlertSound
        enableCodexCompletedAlertSound = Defaults.enableCodexCompletedAlertSound
        codexCompletedAlertDuration = Defaults.codexCompletedAlertDuration
        approveFromNotch = Defaults.approveFromNotch
        approvalWaitSeconds = Defaults.approvalWaitSeconds
        showCompletionSummary = Defaults.showCompletionSummary
    }

    func resetGlanceSettings() {
        showDownloadGlance = Defaults.showDownloadGlance
        showCalendarGlance = Defaults.showCalendarGlance
        calendarLeadMinutes = Defaults.calendarLeadMinutes
        showAirPodsGlance = Defaults.showAirPodsGlance
        showAccessoryBatteryWarning = Defaults.showAccessoryBatteryWarning
        showDriveGlance = Defaults.showDriveGlance
        showLowDiskWarning = Defaults.showLowDiskWarning
        showDownloadProgress = Defaults.showDownloadProgress
        showPortsPanel = Defaults.showPortsPanel
        showAgentSessions = Defaults.showAgentSessions
        showMeetingCountdown = Defaults.showMeetingCountdown
        showUsageTab = Defaults.showUsageTab
        showSystemTab = Defaults.showSystemTab
        showFileShelf = Defaults.showFileShelf
        showMicMute = Defaults.showMicMute
        openOnHover = Defaults.openOnHover
        showQuickNote = Defaults.showQuickNote
        showOutputPicker = Defaults.showOutputPicker
        showAudioOutputGlance = Defaults.showAudioOutputGlance
    }

    private func normalizeStatusDisplayModes() {
        if showBrightnessLine == showBrightnessPercent {
            showBrightnessLine = Defaults.showBrightnessLine
            showBrightnessPercent = Defaults.showBrightnessPercent
        }

        if showSoundLine == showSoundPercent {
            showSoundLine = Defaults.showSoundLine
            showSoundPercent = Defaults.showSoundPercent
        }
    }

    private func applyLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let actual = SMAppService.mainApp.status == .enabled
            if launchAtLogin != actual {
                launchAtLogin = actual
            }
        }
    }

    private static func loadDisplayTarget() -> DisplayTarget {
        if let rawValue = UserDefaults.standard.string(forKey: "displayTarget"),
           let displayTarget = DisplayTarget(rawValue: rawValue) {
            return displayTarget
        }

        if let legacyPrimaryOnly = UserDefaults.standard.object(forKey: "showOnPrimaryDisplayOnly") as? Bool {
            return legacyPrimaryOnly ? .builtIn : .main
        }

        return Defaults.displayTarget
    }
}
