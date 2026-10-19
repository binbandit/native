import Foundation

/// A Compose file: bring the services up and take them down again.
enum ComposeDetector {
    static func detect(_ folder: ProjectFolder) -> [ProjectSuggestion] {
        let files = ["compose.yaml", "compose.yml", "docker-compose.yaml", "docker-compose.yml"]
        guard let file = folder.first(of: files) else { return [] }
        // `docker compose` finds the standard names itself.
        let compose = file.hasPrefix("docker-") ? "docker compose -f \(file)" : "docker compose"
        return [
            ProjectSuggestion(
                name: "Compose Up", command: "\(compose) up", role: .dev, source: .dockerCompose, icon: "shippingbox"),
            ProjectSuggestion(
                name: "Compose Down", command: "\(compose) down", role: .other, source: .dockerCompose,
                icon: "stop.circle", presentation: .background),
        ]
    }
}
