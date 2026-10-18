/// Whether Native is the frontmost app, from the platform adapter.
final class PlatformAppActivity: AppActivity {
    var isActive: Bool {
        PlatformApplication.isActive
    }
}
