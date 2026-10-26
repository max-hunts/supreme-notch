//
//  UsageCredentialsView.swift
//  SupremeNotch
//
//  Settings section for the Claude and Codex usage keys. Values go straight into the
//  Keychain; saved secrets are never shown again, only whether one is set.
//

import SwiftUI

struct UsageCredentialsView: View {
    var onSaved: () -> Void = {}
    /// Folded behind a header row, or always open as on the AI Usage settings page.
    var collapsible = false

    @State private var isExpanded = false
    @State private var drafts: [UsageCredentialField: String] = [:]
    @State private var saved: Set<UsageCredentialField> = []
    @State private var savedNotice = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if collapsible {
                Button {
                    withAnimation(.smooth(duration: 0.25)) { isExpanded.toggle() }
                } label: {
                    HStack {
                        Text("Usage Keys")
                            .font(.system(size: 13, weight: .semibold))
                        Text(saved.isEmpty ? "Using claude-usage-monitor's config" : "\(saved.count) saved in Keychain")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .semibold))
                            .rotationEffect(.degrees(isExpanded ? 90 : 0))
                            .foregroundStyle(.secondary)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                HStack {
                    Text("Usage Keys")
                        .font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Text(saved.isEmpty ? "Using claude-usage-monitor's config" : "\(saved.count) saved in Keychain")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            if isExpanded || !collapsible {
                section("Claude", fields: UsageCredentialField.allCases.filter(\.isClaude),
                        help: "From claude.ai/settings/usage in Chrome: DevTools > Application > Cookies. The Org ID is the UUID in the usage request.")
                section("Codex", fields: UsageCredentialField.allCases.filter { !$0.isClaude },
                        help: "From the Codex usage page: DevTools > Network > wham/usage > Request Headers.")

                HStack {
                    Text("Saved in your Keychain on this Mac only. Empty fields fall back to claude-usage-monitor's config. The tool itself is still needed to fetch usage.")
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 12)
                    if savedNotice {
                        Text("Saved").font(.system(size: 12, weight: .medium)).foregroundStyle(.green)
                    }
                    Button("Save") { save() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(drafts.values.allSatisfy { $0.trimmingCharacters(in: .whitespaces).isEmpty })
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .onAppear(perform: reload)
    }

    private func section(_ title: String, fields: [UsageCredentialField], help: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            ForEach(fields) { field in
                HStack(spacing: 8) {
                    Text(field.title)
                        .font(.system(size: 12))
                        .frame(width: 170, alignment: .leading)
                    Group {
                        if field.isSecret {
                            SecureField(saved.contains(field) ? "Saved, paste to replace" : "Paste value", text: binding(field))
                        } else {
                            TextField(saved.contains(field) ? (UsageCredentialStore.value(field) ?? "") : "Paste value", text: binding(field))
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12, design: .monospaced))
                    if saved.contains(field) {
                        Button {
                            UsageCredentialStore.set("", for: field)
                            reload()
                            onSaved()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless)
                        .help(Text("Remove the saved value"))
                    }
                }
            }
            Text(help)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func binding(_ field: UsageCredentialField) -> Binding<String> {
        Binding(get: { drafts[field] ?? "" }, set: { drafts[field] = $0 })
    }

    private func save() {
        for (field, value) in drafts where !value.trimmingCharacters(in: .whitespaces).isEmpty {
            UsageCredentialStore.set(value, for: field)
        }
        drafts.removeAll()
        reload()
        onSaved()
        savedNotice = true
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            savedNotice = false
        }
    }

    private func reload() {
        saved = Set(UsageCredentialField.allCases.filter(UsageCredentialStore.hasValue))
    }
}
