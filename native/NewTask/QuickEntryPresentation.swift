import SwiftUI

struct QuickEntryPresentation: ViewModifier {
    let model: AppModel
    var git: GitStore?

    func body(content: Content) -> some View {
        content
            .modifier(
                QuickEntryScrim(
                    isPresented: model.quickEntry.isEnabled && model.quickEntry.isPresented,
                    dismiss: model.quickEntry.dismiss)
            )
            .overlay(alignment: .top) {
                if model.quickEntry.isEnabled, model.quickEntry.isPresented {
                    ScrollView {
                        QuickEntryPanel(model: model, entry: model.quickEntry, branch: sourceBranch)
                            .padding(.horizontal, DS.Space.lg)
                            .padding(.top, DS.QuickEntry.toolbarGap)
                            .padding(.bottom, DS.Space.xxl)
                    }
                    .scrollBounceBehavior(.basedOnSize)
                    .onChange(of: model.projects.all.map(\.id)) {
                        if model.quickEntry.project == nil, let project = model.currentProject {
                            model.chooseQuickEntryProject(project.id)
                        }
                    }
                    .onChange(of: model.quickEntryRuntimes.map(\.agent.id)) {
                        model.reconcileQuickEntryAgent()
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if model.quickEntry.isEnabled, !model.quickEntry.isPresented,
                    let task = model.quickEntry.lastStartedTask
                {
                    QuickEntryStartedToast(
                        task: task, project: model.projects.project(task.project)?.name ?? "the project",
                        open: model.openQuickEntryTask, dismiss: { model.quickEntry.lastStartedTask = nil }
                    )
                    .padding(.horizontal, DS.Space.lg)
                    .padding(.bottom, DS.QuickEntry.toastBottom)
                }
            }
    }

    private var sourceBranch: String? {
        guard model.quickEntry.device == .thisMac,
            let project = model.quickEntry.project.flatMap(model.projects.project)
        else { return nil }
        return git?.model(for: project.url).branch?.name
    }
}

#if DEBUG
#Preview("Quick Entry - Over a task") {
    DSPreviewPair {
        let model = QuickEntryPreviewFixtures.model(.selection)
        Text("Queue follow-ups while a turn runs")
            .font(.dsTitle2)
            .frame(width: DS.QuickEntry.width + DS.Space.xxl, height: 440)
            .background(.dsBackground)
            .modifier(QuickEntryScrim(isPresented: true))
            .overlay(alignment: .top) {
                QuickEntryPanel(model: model, entry: model.quickEntry)
                    .padding(.top, DS.QuickEntry.toolbarGap)
            }
    }
}
#endif
