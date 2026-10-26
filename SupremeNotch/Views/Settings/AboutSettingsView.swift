//
//  AboutSettingsView.swift
//  SupremeNotch
//
//  Created by n0xbyte on 29.04.2026.
//

//
//  AboutSettingsView.swift
//  SupremeNotch
//

import SwiftUI

struct AboutSettingsView: View {
    private var appVersionText: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String

        if let version, let build {
            return "Version \(version) (\(build))"
        }

        if let version {
            return "Version \(version)"
        }

        return "Version unknown"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            heroCard
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var heroCard: some View {
        VStack(spacing: 12) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(color: .black.opacity(0.18), radius: 12, y: 5)

            VStack(spacing: 4) {
                Text("SupremeNotch")
                    .font(.system(size: 22, weight: .bold))

                Text("Turn your MacBook notch into a useful, interactive space.")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Text(appVersionText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
        .background(
            LinearGradient(
                colors: [
                    Color.white.opacity(0.10),
                    Color.white.opacity(0.04)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(.white.opacity(0.08), lineWidth: 1)
        }
    }
}
