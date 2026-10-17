#if canImport(Sparkle)
import Foundation
import Sparkle

/// Sparkle's user driver and delegate, turning Sparkle's callbacks into `UpdateState` for
/// `UpdateController`. It shows no UI of its own: Native's views render the state. Sparkle calls
/// every method on the main thread.
final class SparkleUpdateDriver: NSObject {
    private unowned let controller: UpdateController
    private var updater: SPUUpdater?

    /// The release Sparkle is working on, and the replies it waits for.
    private var release: UpdateRelease?
    private var choiceReply: ((SPUUserUpdateChoice) -> Void)?
    private var readyReply: ((SPUUserUpdateChoice) -> Void)?
    private var immediateInstall: (() -> Void)?
    private var cancelDownloadHandler: (() -> Void)?
    private var expectedLength: UInt64 = 0
    private var receivedLength: UInt64 = 0

    init(controller: UpdateController) {
        self.controller = controller
    }

    func start() throws {
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: self, delegate: self)
        try updater.start()
        self.updater = updater
    }

    var automaticallyChecks: Bool {
        get { updater?.automaticallyChecksForUpdates ?? false }
        set { updater?.automaticallyChecksForUpdates = newValue }
    }

    var automaticallyDownloads: Bool {
        get { updater?.automaticallyDownloadsUpdates ?? false }
        set { updater?.automaticallyDownloadsUpdates = newValue }
    }

    var lastChecked: Date? { updater?.lastUpdateCheckDate }

    func checkForUpdates() {
        updater?.checkForUpdates()
    }

    /// Starts a quiet check shortly, after any session in progress has wound down.
    func recheckSoon() {
        updater?.resetUpdateCycleAfterShortDelay()
    }

    /// Downloads the offered update if needed, then installs it.
    func install() { reply(.install) }

    /// Not now: Sparkle offers it again at the next scheduled check.
    func remindLater() { reply(.dismiss) }

    /// Never offer this version again.
    func skip() { reply(.skip) }

    /// Answers the offer Sparkle is waiting on.
    private func reply(_ choice: SPUUserUpdateChoice) {
        if let reply = choiceReply ?? readyReply {
            choiceReply = nil
            readyReply = nil
            reply(choice)
        }
    }

    func cancelDownload() {
        cancelDownloadHandler?()
        cancelDownloadHandler = nil
    }

    /// Installs the ready update and relaunches into it.
    func installAndRelaunch() {
        if let immediateInstall {
            self.immediateInstall = nil
            immediateInstall()
        } else {
            reply(.install)
        }
    }

    private func show(_ state: UpdateState) {
        controller.driverDidChange(state)
    }

    private func makeRelease(_ item: SUAppcastItem) -> UpdateRelease {
        UpdateRelease(
            version: item.displayVersionString,
            build: item.versionString,
            notes: item.itemDescription.map { Self.readableNotes($0, format: item.itemDescriptionFormat) },
            date: item.date,
            size: item.contentLength > 0 ? item.contentLength : nil,
            isCritical: item.isCriticalUpdate,
            channel: item.channel
        )
    }

    /// Notes are Markdown (`generate_appcast --embed-release-notes` with scripts/release's
    /// notes); older HTML items lose their tags rather than showing markup.
    private static func readableNotes(_ text: String, format: String?) -> String {
        guard format == nil || format == "html" else { return text }
        return text.replacing(/<li>/, with: "- ").replacing(/<[^>]+>/, with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - SPUUserDriver

extension SparkleUpdateDriver: SPUUserDriver {
    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        // Info.plist turns automatic checks on, so Sparkle shouldn't ask; if it does, keep them on.
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: true, sendSystemProfile: false))
    }

    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) {
        show(.checking)
    }

    func showUpdateFound(
        with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void
    ) {
        let release = makeRelease(appcastItem)
        self.release = release
        switch state.stage {
        case .notDownloaded:
            choiceReply = reply
            show(.available(release))
        case .downloaded:
            // Downloaded in an earlier session: installing now relaunches straight into it.
            readyReply = reply
            show(.ready(release))
        case .installing:
            readyReply = reply
            show(.ready(release))
        @unknown default:
            choiceReply = reply
            show(.available(release))
        }
    }

    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {
        if let notes = String(data: downloadData.data, encoding: .utf8) {
            controller.driverDidLoadNotes(
                Self.readableNotes(notes, format: downloadData.mimeType == "text/html" ? "html" : "markdown"))
        }
    }

    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: any Error) {
        // The update can still install; the page links to the release instead.
    }

    func showUpdateNotFoundWithError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        let checked = Date()
        controller.driverDidCheck(at: checked)
        show(.upToDate(checkedAt: checked))
        acknowledgement()
    }

    func showUpdaterError(_ error: any Error, acknowledgement: @escaping () -> Void) {
        show(.failed(UpdateFailure(error, version: controller.current.version)))
        acknowledgement()
    }

    func showDownloadInitiated(cancellation: @escaping () -> Void) {
        cancelDownloadHandler = cancellation
        expectedLength = 0
        receivedLength = 0
        if let release {
            show(.downloading(release, progress: nil))
        }
    }

    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {
        expectedLength = expectedContentLength
    }

    func showDownloadDidReceiveData(ofLength length: UInt64) {
        receivedLength += length
        guard let release, expectedLength > 0 else { return }
        show(.downloading(release, progress: min(Double(receivedLength) / Double(expectedLength), 1)))
    }

    func showDownloadDidStartExtractingUpdate() {
        cancelDownloadHandler = nil
        if let release {
            show(.preparing(release, progress: 0))
        }
    }

    func showExtractionReceivedProgress(_ progress: Double) {
        if let release {
            show(.preparing(release, progress: progress))
        }
    }

    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) {
        readyReply = reply
        if let release {
            show(.ready(release))
        }
    }

    func showInstallingUpdate(
        withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void
    ) {
        if let release {
            show(.installing(release))
        }
    }

    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
    }

    func showUpdateInFocus() {
        // The Updates window or page already shows the session; nothing to bring forward here.
    }

    func dismissUpdateInstallation() {
        choiceReply = nil
        readyReply = nil
        cancelDownloadHandler = nil
        // The session ended. Keep what the user should still see; anything in flight is over.
        switch controller.state {
        case .checking, .available, .downloading, .preparing:
            release = nil
            show(.idle)
        case .ready where immediateInstall == nil:
            release = nil
            show(.idle)
        case .idle, .upToDate, .ready, .installing, .failed, .unavailable:
            break
        }
    }
}

// MARK: - SPUUpdaterDelegate

extension SparkleUpdateDriver: SPUUpdaterDelegate {
    func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        controller.channel.sparkleChannels
    }

    func updaterShouldPromptForPermissionToCheck(forUpdates updater: SPUUpdater) -> Bool {
        false
    }

    /// A silent automatic download finished: the update installs at quit, or now on request.
    func updater(
        _ updater: SPUUpdater, willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        let release = makeRelease(item)
        self.release = release
        immediateInstall = immediateInstallHandler
        show(.ready(release))
        return true
    }

    func updater(_ updater: SPUUpdater, didFinishUpdateCycleFor updateCheck: SPUUpdateCheck, error: (any Error)?) {
        controller.driverDidCheck(at: updater.lastUpdateCheckDate)
        // A failed background check stays quiet (it retries on schedule) but the page still says so.
        if updateCheck == .updatesInBackground, let error = error as NSError?, !Self.isBenign(error) {
            if !controller.state.isBusy, controller.state.release == nil {
                show(.failed(UpdateFailure(error, version: controller.current.version)))
            }
        }
    }

    private static func isBenign(_ error: NSError) -> Bool {
        error.domain == SUSparkleErrorDomain
            && [Int(SUError.noUpdateError.rawValue), Int(SUError.installationCanceledError.rawValue)].contains(
                error.code)
    }
}

// MARK: - Failures

extension UpdateFailure {
    /// Words a Sparkle or network error the way `ErrorState` shows it.
    init(_ error: any Error, version: String) {
        let error = error as NSError
        let details = "\(error.localizedDescription) (\(error.domain) \(error.code))"
        let still = "Native is still on version \(version)."
        if error.domain == NSURLErrorDomain || (error.underlyingErrors.first as NSError?)?.domain == NSURLErrorDomain {
            self.init(
                kind: .offline, title: "Native couldn't reach GitHub",
                recovery: "\(still) It checks again on its own.",
                suggestion: "Check your internet connection, then try again.", details: details)
            return
        }
        guard error.domain == SUSparkleErrorDomain, let code = SUError(rawValue: OSStatus(error.code)) else {
            self.init(
                kind: .other, title: "The update didn't finish", recovery: still, suggestion: "Try again in a moment.",
                details: details)
            return
        }
        switch code {
        case .appcastParseError, .appcastError, .resumeAppcastError:
            self.init(
                kind: .feed, title: "The update feed couldn't be read", recovery: still,
                suggestion: "Try again later. If it keeps happening, download the latest release from GitHub.",
                details: details)
        case .downloadError, .temporaryDirectoryError:
            self.init(
                kind: .download, title: "The download didn't finish", recovery: "\(still) Nothing was installed.",
                suggestion: "Try again; the download starts over.", details: details)
        case .signatureError, .validationError, .unarchivingError, .insufficientSigningError, .noPublicDSAFoundError:
            self.init(
                kind: .security, title: "The update failed a security check",
                recovery: "\(still) Native didn't install the download because it couldn't verify who made it.",
                suggestion: "Download the latest release from GitHub instead.", details: details)
        case .runningFromDiskImageError, .runningTranslocated:
            self.init(
                kind: .location, title: "Native can't update itself from here",
                recovery: "It's running from a disk image or a temporary location macOS chose.",
                suggestion: "Move Native to your Applications folder and open it from there.", details: details)
        case .installationWriteNoPermissionError, .authenticationFailure, .fileCopyFailure, .installationError,
            .relaunchError, .missingInstallerToolError, .agentInvalidationError, .notValidUpdateError:
            self.init(
                kind: .install, title: "The update couldn't be installed", recovery: still,
                suggestion: "Quit and reopen Native, then try again. If it keeps happening, download it from GitHub.",
                details: details)
        default:
            self.init(
                kind: .other, title: "The update didn't finish", recovery: still, suggestion: "Try again in a moment.",
                details: details)
        }
    }
}
#endif
