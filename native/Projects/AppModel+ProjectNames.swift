import Foundation
import NativeHostProtocol

extension AppModel {
    /// Task labels belong to the machine running the task. A local rename must never leak into a
    /// paired host's task subtitle, even when its checkout is linked to this Mac's project.
    func projectName(for key: SessionKey, in projectID: Project.ID) -> String? {
        let project = projects.project(projectID) ?? projects.archived.first { $0.id == projectID }
        if let remote = remoteSession(key), let host = hosts.host(remote.host) {
            if let name = host.session(remote.session)?.titles?.request?.projectName, !name.isEmpty { return name }
            if let path = project?.checkouts.first(where: { $0.host == remote.host })?.path {
                return URL(filePath: path).lastPathComponent
            }
            return remotePlace(of: key).map { URL(filePath: $0.cwd).lastPathComponent }
        }
        if let place = remotePlace(of: key) {
            let path = project?.checkouts.first { $0.host == place.host.id }?.path ?? place.cwd
            return URL(filePath: path).lastPathComponent
        }
        return project?.name
    }
}
