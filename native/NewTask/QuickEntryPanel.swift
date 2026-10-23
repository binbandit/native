import SwiftUI

struct QuickEntryPanel: View {
    let model: AppModel
    @Bindable var entry: QuickEntryModel
    var branch: String?
    @State private var selection: TextSelection?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            editor
            if let context = entry.context { clip(context) }
            readiness
            SeparatorLine()
            controls
            if entry.picker != nil {
                SeparatorLine()
                QuickEntryPicker(model: model, entry: entry)
            }
        }
        .frame(maxWidth: DS.QuickEntry.width)
        .dsGlassEffect(in: .rect(cornerRadius: DS.Radius.panel))
        .clipShape(.rect(cornerRadius: DS.Radius.panel))
        .overlay {
            RoundedRectangle(cornerRadius: DS.Radius.panel).strokeBorder(
                .dsBorder, lineWidth: DS.Composer.separatorWidth)
        }
        .dsShadow(.modal)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Quick Entry")
        .onAppear { isFocused = true }
        .onChange(of: entry.picker) { _, picker in
            if picker == nil { isFocused = true }
        }
        .onKeyPress(.escape) {
            if entry.picker != nil { entry.picker = nil } else { entry.dismiss() }
            return .handled
        }
    }

    private var editor: some View {
        ComposerEditor(
            text: $entry.draft, selection: $selection, placeholder: "What would you like to do?",
            isFocused: $isFocused, font: DS.QuickEntry.editorFont,
            lineSpacing: DS.QuickEntry.editorLineSpacing, insets: DS.QuickEntry.textInsets
        ) { press in
            guard !PlatformTextInput.isComposing else { return .ignored }
            if press.key == .tab, press.modifiers.isSubset(of: [.shift]) {
                return ComposerPlatform.moveKeyFocus(forward: !press.modifiers.contains(.shift)) ? .handled : .ignored
            }
            guard press.key == .return, press.modifiers.isDisjoint(with: [.shift, .option, .control]) else {
                return .ignored
            }
            guard press.phase != .repeat else { return .handled }
            model.startQuickEntry(open: press.modifiers.contains(.command))
            return .handled
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: DS.Space.xs) {
                if DS.isTouchPlatform {
                    Button {
                        entry.dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.ds(.ghost))
                    .dsHitTarget(DS.Size.controlSM)
                    .accessibilityLabel("Close Quick Entry")
                }
                Button {
                    model.expandQuickEntry()
                } label: {
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.dsCallout)
                }
                .buttonStyle(.ds(.ghost))
                .dsHitTarget(DS.Size.controlSM)
                .help("Expand into New Task (⇧⌘N)")
                .accessibilityLabel("Expand into New Task")
            }
            .padding(DS.Space.lg)
        }
    }

    private func clip(_ context: QuickEntryModel.Context) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            HStack(spacing: DS.Space.sm) {
                Image(systemName: "text.quote")
                Text("From \(context.source)")
                    .lineLimit(1)
                Spacer(minLength: DS.Space.md)
                Button {
                    entry.context = nil
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .dsHitTarget(DS.Size.controlXS)
                .accessibilityLabel("Remove context")
            }
            .font(.dsCaption)
            .foregroundStyle(.dsTextTertiary)
            ScrollView {
                Text(context.text)
                    .font(.dsMonoCaption)
                    .foregroundStyle(.dsTextSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, DS.Space.md)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(.dsBorderHover).frame(width: DS.Space.xxs)
                    }
            }
            .frame(maxHeight: DS.QuickEntry.clipMaxHeight)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DS.Space.md)
        .background(.dsFill, in: .rect(cornerRadius: DS.Radius.row))
        .padding(.horizontal, DS.QuickEntry.clipInset)
        .padding(.bottom, DS.Space.xl)
    }

    private var readiness: some View {
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            Text(entry.failure ?? model.quickEntryReadiness)
                .font(.dsCaption)
                .foregroundStyle(entry.failure == nil ? .dsTextTertiary : .dsAttention)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("quick-entry-readiness")
            if model.quickEntryDeviceUnavailable {
                Button("Run on This Mac") { model.chooseQuickEntryDevice(.thisMac) }
                    .buttonStyle(.ds(.secondary))
            }
        }
        .padding(.horizontal, DS.QuickEntry.clipInset)
        .padding(.bottom, DS.Space.lg)
    }

    private var controls: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: DS.Space.md) {
                address
                Spacer(minLength: DS.Space.md)
                startButton
            }
            VStack(alignment: .trailing, spacing: DS.Space.sm) {
                ScrollView(.horizontal) { address }
                    .scrollIndicators(.never)
                startButton
            }
        }
        .padding(.horizontal, DS.Space.lg)
        .padding(.vertical, DS.Space.md)
        .frame(minHeight: DS.QuickEntry.barHeight)
    }

    private var address: some View {
        TaskAddressLine(
            agent: model.quickEntryRuntime?.agent.displayName ?? "Choose agent",
            model: model.quickEntryModelName,
            device: model.deviceName(entry.device),
            deviceLook: HostLookStore.shared.look(for: entry.device, named: model.deviceName(entry.device)),
            project: entry.project.flatMap(model.projects.project)?.name ?? "Choose project",
            branch: branch,
            picker: entry.picker, choose: entry.toggle)
    }

    private var startButton: some View {
        Button {
            model.startQuickEntry(open: false)
        } label: {
            HStack(spacing: DS.Space.sm) {
                Text("Start")
                Image(systemName: "return")
            }
        }
        .buttonStyle(.ds(.primary, size: .medium))
        .fixedSize()
        .disabled(!entry.hasMessage || model.quickEntryDeviceUnavailable)
        .help("Start and stay here (Return). Start and open with ⌘Return.")
        .accessibilityLabel("Start task")
    }
}

#if DEBUG
#Preview("Quick Entry - Selection") {
    QuickEntryPreviewFixture(state: .selection)
}
#Preview("Quick Entry - Empty") {
    QuickEntryPreviewFixture(state: .empty)
}
#Preview("Quick Entry - First launch") {
    QuickEntryPreviewFixture(state: .firstLaunch)
}
#Preview("Quick Entry - Missing folder") {
    QuickEntryPreviewFixture(state: .failure)
}
#Preview("Quick Entry - Unavailable device") {
    QuickEntryPreviewFixture(state: .offline)
}
#Preview("Quick Entry - Narrow and long text") {
    QuickEntryPreviewFixture(state: .narrow)
}
#endif
