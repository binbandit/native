import SwiftUI

/// The What's New sheet: a few curated highlights from the releases since the last launch, newest
/// first, four to a page, with Try It links and the full release notes one click away.
struct WhatsNewSheet: View {
    let releases: [WhatsNewRelease]
    let releaseNotesURL: URL?
    let onTry: (WhatsNewDestination) -> Void
    let onDone: () -> Void

    @State private var page = 0
    @Environment(\.openURL) private var openURL

    static let pageSize = 4

    private struct Item: Identifiable {
        let highlight: WhatsNewHighlight
        let version: WhatsNewVersion
        var id: String { highlight.id }
    }

    private var items: [Item] {
        releases.flatMap { release in release.highlights.map { Item(highlight: $0, version: release.version) } }
    }

    private var pages: [[Item]] {
        stride(from: 0, to: items.count, by: Self.pageSize).map {
            Array(items[$0..<min($0 + Self.pageSize, items.count)])
        }
    }

    private var isLastPage: Bool { page >= pages.count - 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.xl) {
            header
            if pages.isEmpty {
                Text("There's nothing to showcase in this version yet. The release notes have every change.")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                VStack(alignment: .leading, spacing: DS.Space.lg) {
                    ForEach(pages[min(page, pages.count - 1)]) { item in
                        WhatsNewHighlightRow(
                            highlight: item.highlight,
                            version: releases.count > 1 ? item.version.description : nil,
                            onTry: item.highlight.destination.map { destination in { onTry(destination) } }
                        )
                    }
                }
                .id(page)
                .transition(.opacity)
            }
            footer
        }
        .padding(DS.Space.xxl)
        .frame(width: 520, alignment: .topLeading)
        .background(.dsBackground)
        .animation(.dsStandard, value: page)
        #if os(macOS)
        .onExitCommand(perform: onDone)
        #endif
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Space.xs) {
            Text(releases.first.map { "What's New in Native \($0.version)" } ?? "What's New in Native")
                .font(.dsTitle3)
                .foregroundStyle(.dsTextPrimary)
                .accessibilityAddTraits(.isHeader)
            if releases.count > 1, let oldest = releases.last {
                Text("Highlights from Native \(oldest.version) onward, in one place.")
                    .font(.dsBody)
                    .foregroundStyle(.dsTextSecondary)
            }
        }
    }

    private var footer: some View {
        HStack(spacing: DS.Space.md) {
            if let releaseNotesURL {
                Button("Release Notes") { openURL(releaseNotesURL) }
                    .buttonStyle(.ds(.ghost))
                    .help("Every change in this release, on GitHub")
            }
            Spacer(minLength: 0)
            if pages.count > 1 {
                Text("\(min(page, pages.count - 1) + 1) of \(pages.count)")
                    .font(.dsCaption)
                    .foregroundStyle(.dsTextTertiary)
                    .monospacedDigit()
                if page > 0 {
                    Button("Back") { page -= 1 }
                        .buttonStyle(.ds(.secondary))
                }
            }
            Button(isLastPage ? "Continue" : "Next") {
                if isLastPage { onDone() } else { page += 1 }
            }
            .buttonStyle(.ds(.primary))
            .keyboardShortcut(.defaultAction)
        }
    }
}

/// One highlight: its art, title and summary, and Try It when it leads somewhere.
private struct WhatsNewHighlightRow: View {
    let highlight: WhatsNewHighlight
    /// Shown when the sheet collects several releases.
    let version: String?
    let onTry: (() -> Void)?

    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Space.md) {
            if case .image(let name) = highlight.preview {
                Image(name)
                    .resizable()
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous))
                    .accessibilityHidden(true)
            }
            HStack(alignment: .top, spacing: DS.Space.lg) {
                if case .symbol(let name) = highlight.preview {
                    tile(name)
                }
                VStack(alignment: .leading, spacing: DS.Space.xxs) {
                    HStack(spacing: DS.Space.sm) {
                        Text(highlight.title)
                            .font(.dsCalloutMedium)
                            .foregroundStyle(.dsTextPrimary)
                        if let version {
                            Badge(version)
                        }
                    }
                    Text(highlight.summary)
                        .font(.dsBody)
                        .foregroundStyle(.dsTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                if let onTry {
                    Button("Try It", action: onTry)
                        .buttonStyle(.ds(.secondary))
                        .dsHitTarget(DS.Size.controlMD)
                        .accessibilityHint("Opens \(highlight.title)")
                }
            }
        }
        .onAppear { appeared = true }
    }

    private func tile(_ symbol: String) -> some View {
        let shape = RoundedRectangle(cornerRadius: DS.Radius.card, style: .continuous)
        return Image(systemName: symbol)
            .font(.system(size: DS.Size.statusGlyph + DS.Space.xs, weight: .light))
            .foregroundStyle(.dsTextPrimary)
            .symbolEffect(.bounce, value: appeared)
            .frame(width: DS.Size.controlMD + DS.Space.md, height: DS.Size.controlMD + DS.Space.md)
            .background(.dsSurfaceSunken, in: shape)
            .overlay { shape.strokeBorder(.dsSeparator, lineWidth: 1) }
            .accessibilityHidden(true)
    }
}

extension View {
    /// Presents What's New when `center` has something and nothing needs the user, and handles
    /// Try It: a Settings page opens in this window; a link opens in the browser.
    func whatsNewSheet(_ center: WhatsNewCenter, blocked: Bool) -> some View {
        modifier(WhatsNewSheetModifier(center: center, blocked: blocked))
    }
}

private struct WhatsNewSheetModifier: ViewModifier {
    let center: WhatsNewCenter
    let blocked: Bool

    @Environment(SettingsPresentation.self) private var settings
    @Environment(\.openURL) private var openURL

    func body(content: Content) -> some View {
        content
            .onAppear { center.presentIfReady(blocked: blocked) }
            .onChange(of: blocked) { center.presentIfReady(blocked: blocked) }
            // `start()` runs in the app's launch task, after this view first appears.
            .onChange(of: center.pending) { center.presentIfReady(blocked: blocked) }
            .sheet(isPresented: Binding(get: { center.presented != nil }, set: { if !$0 { center.dismiss() } })) {
                WhatsNewSheet(
                    releases: center.presented ?? [],
                    releaseNotesURL: AppVersion.current.releaseNotesURL ?? AppVersion.current.allReleasesURL,
                    onTry: { destination in
                        center.dismiss()
                        switch destination {
                        case .settings(let pane): settings.open(SettingsPane.ID(pane))
                        case .url(let url): openURL(url)
                        }
                    },
                    onDone: center.dismiss
                )
            }
    }
}
