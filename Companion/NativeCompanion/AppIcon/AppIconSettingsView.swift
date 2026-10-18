import AppAppearance
import SwiftUI

/// Settings › App Icon: the icon (which sets the accent too), celebrations, and the one switch
/// that keeps the icon from changing on its own.
struct AppIconSettingsView: View {
    @Environment(AppIconController.self) private var icons

    var body: some View {
        @Bindable var icons = icons
        let target = icons.target()
        List {
            Section {
                AppIconStatusRow(target: target)
            } footer: {
                if let problem = icons.problem {
                    Text(problem).foregroundStyle(.dsDanger)
                }
            }
            Section {
                ForEach(CompanionAppIcon.allCases) { theme in
                    Button {
                        icons.theme = theme
                    } label: {
                        HStack(spacing: DS.Space.lg) {
                            AppIconThumbnail(name: theme.iconName)
                            Text(theme.title).foregroundStyle(.dsTextPrimary)
                            Spacer()
                            if icons.theme == theme {
                                Image(systemName: "checkmark").foregroundStyle(.dsAccentText)
                            }
                        }
                    }
                    .accessibilityAddTraits(icons.theme == theme ? .isSelected : [])
                    .accessibilityIdentifier("icon-\(theme.rawValue)")
                }
            } header: {
                Text("Icon")
            } footer: {
                Text("The icon sets the accent too, as on the Mac.")
            }
            Section {
                NavigationLink {
                    CelebrationsView()
                } label: {
                    LabeledContent(
                        "Celebrations",
                        value: icons.celebrations.enabledCount == 0 ? "Off" : "\(icons.celebrations.enabledCount) on")
                }
                .accessibilityIdentifier("celebrations")
                Toggle("Keep Icon Fixed", isOn: $icons.keepsIconFixed)
                    .accessibilityIdentifier("keepIconFixed")
            } footer: {
                Text(
                    icons.keepsIconFixed
                        ? "Only the icon picked above shows. Celebrations and hosts leave it alone."
                        : "Celebrations you turn on show on their dates, and a host's own icon while it's the one you're looking at. iOS shows an alert each time the icon changes."
                )
            }
        }
        .font(CompanionType.body)
        .scrollContentBackground(.hidden)
        .background(.dsBackground)
        .navigationTitle("App Icon")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// The icon showing, and why: picked, a celebration until its last day, or the active host's.
private struct AppIconStatusRow: View {
    let target: AppIconController.Target

    var body: some View {
        HStack(spacing: DS.Space.lg) {
            AppIconThumbnail(name: target.name, size: CompanionMetrics.iconPreview)
            VStack(alignment: .leading, spacing: DS.Space.xxs) {
                Text(title).font(CompanionType.headline).foregroundStyle(.dsTextPrimary)
                Text(detail).font(CompanionType.subheadline).foregroundStyle(.dsTextSecondary)
            }
        }
        .padding(.vertical, DS.Space.xs)
        .accessibilityElement(children: .combine)
    }

    private var title: String {
        switch target.reason {
        case .picked: CompanionAppIcon.allCases.first { $0.iconName == target.name }?.title ?? "Native"
        case .celebration(let title, _): title
        case .host(let name): name
        }
    }

    private var detail: String {
        switch target.reason {
        case .picked: "The icon you picked."
        case .celebration(_, let through): "Showing through \(CelebrationDates.shortText(CivilDayRange(day: through)))."
        case .host(let name): "\(name)'s icon, while it's the host you're looking at."
        }
    }
}

/// An icon as the home screen draws it, at row size; a dashed outline if this build lacks it.
struct AppIconThumbnail: View {
    let name: String?
    var size = CompanionMetrics.iconThumbnail

    var body: some View {
        Group {
            if let preview = BundledAppIcons.previewName(name) {
                Image(preview).resizable().interpolation(.high)
            } else {
                Image(systemName: "app.dashed").font(.ds(size * 0.6)).foregroundStyle(.dsTextTertiary)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
