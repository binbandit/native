import Foundation

extension AppModel {
    func beginFolderDrop() -> UUID {
        let request = UUID()
        sidebarFolders.dropRequest = request
        sidebarFolders.acceptsDrop = false
        sidebarFolders.hovered = []
        return request
    }

    func previewFolderDrop(_ urls: [URL], request: UUID) async {
        let resolved = await PlatformFolderAccess.inspect(urls, policy: folderPolicy)
        defer {
            for item in resolved where item.hasSecurityScope { item.original.stopAccessingSecurityScopedResource() }
        }
        guard sidebarFolders.dropRequest == request else { return }
        sidebarFolders.hovered = resolved.filter { $0.failure == nil }.map(\.url.lastPathComponent)
        sidebarFolders.acceptsDrop = !sidebarFolders.hovered.isEmpty
    }

    func endFolderDrop() {
        sidebarFolders.dropRequest = nil
        sidebarFolders.acceptsDrop = false
        sidebarFolders.hovered = []
    }
}
