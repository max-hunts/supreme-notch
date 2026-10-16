//
//  InteractionActivity.swift
//  BetterNotch
//
//  As a background menu bar app, BetterNotch is eligible for App Nap, which throttles
//  event handling once it has been idle; hover then lags behind the pointer. While the
//  pointer is over the notch or the notch is open, this tells macOS the app is
//  latency-critical. It is released as soon as the pointer leaves, so idle power use
//  is unchanged, and it never keeps the Mac awake.
//

import Foundation

@MainActor
final class InteractionActivity {
    static let shared = InteractionActivity()

    private var token: NSObjectProtocol?

    func setActive(_ active: Bool) {
        if active, token == nil {
            token = ProcessInfo.processInfo.beginActivity(
                options: [.userInitiatedAllowingIdleSystemSleep, .latencyCritical],
                reason: "The notch is responding to the pointer"
            )
        } else if !active, let token {
            ProcessInfo.processInfo.endActivity(token)
            self.token = nil
        }
    }
}
