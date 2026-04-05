//
//  WelcomeWindow.swift
//  Spectr
//
//  Created by Andrés Campos on 3/23/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct WelcomeView: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.openDocument) private var openDocument
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.newDocument) private var newDocument
    @State private var recentFiles: [URL] = []
    @State private var isDefaultApp = false

    private let trimColor = Color("TrimColor", bundle: nil)

    var body: some View {
        ZStack {
            WelcomeBackground(colorScheme: colorScheme)

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.bottom, 28)

                actionCards
                    .padding(.bottom, 16)

                defaultAppStatus
                    .padding(.bottom, 20)

                recentFilesList
            }
            .padding(40)
        }
        .frame(width: 600, height: 520)
        .onAppear {
            recentFiles = loadRecentFiles()
            isDefaultApp = checkIsDefaultApp()
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 16) {
            if let icon = NSApp.applicationIconImage {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 64, height: 64)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Spectr")
                    .font(.system(size: 36, weight: .bold, design: .default))
                    .foregroundStyle(Color.primary)

                Text("Markdown Editor")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.secondary)
            }
        }
    }

    // MARK: - Action Cards

    private var actionCards: some View {
        HStack(spacing: 12) {
            ActionCard(
                icon: "doc.badge.plus",
                label: "New Document"
            ) {
                newDocument(SpectrDocument())
                dismissWindow(id: "welcome")
            }

            ActionCard(
                icon: "folder",
                label: "Open File"
            ) {
                openExistingFile()
            }
        }
    }

    // MARK: - Default App Status

    private var defaultAppStatus: some View {
        DefaultAppStatusRow(isDefault: isDefaultApp) {
            setAsDefaultApp()
        }
    }

    // MARK: - Recent Files

    private var recentFilesList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if !recentFiles.isEmpty {
                HStack {
                    Text("Recent")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Color.secondary)
                        .textCase(.uppercase)
                        .tracking(0.5)

                    Spacer()

                    Text("\(recentFiles.count)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(Color.secondary.opacity(0.6))
                }
                .padding(.bottom, 10)

                ScrollView {
                    VStack(spacing: 1) {
                        ForEach(recentFiles, id: \.self) { url in
                            RecentFileRow(url: url) {
                                Task {
                                    try? await openDocument(at: url)
                                    dismissWindow(id: "welcome")
                                }
                            }
                        }
                    }
                }
            } else {
                Text("No recent documents")
                    .font(.system(size: 13))
                    .foregroundStyle(Color.secondary.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 20)
            }
        }
    }

    // MARK: - Helpers

    private func openExistingFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = SpectrDocument.readableContentTypes.compactMap { $0 }
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false

        guard panel.runModal() == .OK, let url = panel.url else { return }

        Task {
            try? await openDocument(at: url)
            dismissWindow(id: "welcome")
        }
    }

    private func loadRecentFiles() -> [URL] {
        NSDocumentController.shared.recentDocumentURLs
    }

    private func checkIsDefaultApp() -> Bool {
        guard let markdownType = UTType(filenameExtension: "md"),
              let defaultAppURL = NSWorkspace.shared.urlForApplication(toOpen: markdownType),
              let appBundleID = Bundle(url: defaultAppURL)?.bundleIdentifier,
              let myBundleID = Bundle.main.bundleIdentifier
        else { return false }
        return appBundleID == myBundleID
    }

    private func setAsDefaultApp() {
        guard let markdownType = UTType(filenameExtension: "md"),
              let appURL = Bundle.main.bundleURL as URL?
        else { return }

        NSWorkspace.shared.setDefaultApplication(at: appURL, toOpen: markdownType) { error in
            if error == nil {
                DispatchQueue.main.async {
                    isDefaultApp = true
                }
            }
        }
    }
}

// MARK: - Default App Status Row

private struct DefaultAppStatusRow: View {
    var isDefault: Bool
    var onSetDefault: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Group {
            if isDefault {
                HStack(spacing: 6) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.green)

                    Text("Default app for Markdown files")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Color.secondary)
                }
            } else {
                Button(action: onSetDefault) {
                    HStack(spacing: 6) {
                        Image(systemName: "circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.secondary.opacity(0.5))

                        Text("Set as default app for Markdown files")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.secondary)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(Color.secondary.opacity(0.5))
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(
                                colorScheme == .dark
                                    ? Color.white.opacity(isHovered ? 0.06 : 0)
                                    : Color.black.opacity(isHovered ? 0.04 : 0)
                            )
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHovered = hovering
                }
                .animation(.easeOut(duration: 0.12), value: isHovered)
            }
        }
    }
}

// MARK: - Action Card

private struct ActionCard: View {
    var icon: String
    var label: String
    var action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.7))

                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color.primary.opacity(0.85))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(isHovered ? 0.15 : 0.08),
                        lineWidth: 0.5
                    )
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.12), value: isHovered)
    }

    private var cardBackground: some ShapeStyle {
        colorScheme == .dark
            ? AnyShapeStyle(Color.white.opacity(isHovered ? 0.08 : 0.05))
            : AnyShapeStyle(Color.black.opacity(isHovered ? 0.05 : 0.03))
    }
}

// MARK: - Recent File Row

private struct RecentFileRow: View {
    var url: URL
    var action: () -> Void

    @State private var isHovered = false
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                Text(url.deletingPathExtension().lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.primary.opacity(0.85))
                    .lineLimit(1)

                Spacer(minLength: 12)

                Text(abbreviatedPath)
                    .font(.system(size: 12))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(
                        colorScheme == .dark
                            ? Color.white.opacity(isHovered ? 0.06 : 0)
                            : Color.black.opacity(isHovered ? 0.04 : 0)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            isHovered = hovering
        }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }

    private var abbreviatedPath: String {
        let path = url.deletingLastPathComponent().path(percentEncoded: false)
        if let home = FileManager.default.homeDirectoryForCurrentUser.path(percentEncoded: false) as String?,
           path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}

// MARK: - Background

private struct WelcomeBackground: View {
    var colorScheme: ColorScheme

    var body: some View {
        ZStack {
            Rectangle()
                .fill(baseTint)

            LinearGradient(
                colors: [
                    Color.white.opacity(colorScheme == .dark ? 0.04 : 0.16),
                    .clear,
                    Color.black.opacity(colorScheme == .dark ? 0.08 : 0.03),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
        .ignoresSafeArea()
    }

    private var baseTint: Color {
        colorScheme == .dark
            ? Color(red: 0.14, green: 0.11, blue: 0.10).opacity(0.56)
            : Color(red: 0.96, green: 0.94, blue: 0.92).opacity(0.62)
    }
}
