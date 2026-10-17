import SwiftUI

/// Factory's update button in the window's toolbar row, beside the sidebar toggle. It appears only
/// when there's something to do: an update ready to restart into, or one waiting to download when
/// automatic downloads are off. After a click it shows progress in place until Native restarts.
struct UpdateToolbarButton: View {
    let controller: UpdateController

    @State private var isConfirmingRestart = false

    var body: some View {
        Group {
            switch controller.state {
            case .available(let release), .ready(let release):
                UpdateButton(version: release.version, action: requestInstall)
                    .help(help(for: release))
            case .downloading(let release, _), .preparing(let release, _):
                progress("Updating", help: "Downloading Native \(release.version). Native restarts when it's ready.")
            case .installing(let release):
                progress("Restarting", help: "Installing Native \(release.version).")
            case .idle, .checking, .upToDate, .failed, .unavailable:
                EmptyView()
            }
        }
        .transition(.opacity)
        .animation(.dsStandard, value: controller.state)
        .updateRestartConfirmation(controller, isPresented: $isConfirmingRestart)
    }

    private func progress(_ title: String, help: String) -> some View {
        HStack(spacing: DS.Space.sm) {
            DotGridLoader(pattern: .waiting)
                .frame(width: 12, height: 12)
            Text(title)
                .font(.dsBody)
                .foregroundStyle(.dsTextSecondary)
        }
        .padding(.horizontal, DS.Space.md)
        .help(help)
        .accessibilityElement(children: .combine)
    }

    private func help(for release: UpdateRelease) -> String {
        let action =
            if case .ready = controller.state {
                "Restart to update to Native \(release.version)."
            } else {
                "Update to Native \(release.version). Native downloads it, then restarts."
            }
        return [action, controller.restartContext().summary].compactMap(\.self).joined(separator: " ")
    }

    private func requestInstall() {
        if controller.restartContext().needsConfirmation {
            isConfirmingRestart = true
        } else {
            controller.installUpdate(.now)
        }
    }
}

#if DEBUG
#Preview("Update button") {
    DSPreviewPair {
        HStack(spacing: DS.Space.lg) {
            UpdateToolbarButton(controller: .preview("ready"))
            UpdateToolbarButton(controller: .preview("downloading"))
            UpdateToolbarButton(controller: .preview("installing"))
        }
    }
}
#endif
