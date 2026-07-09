import Foundation
import Observation

/// Pending Turn Off confirmation, with running-resource counts when the
/// engine can report them (mock in Phase 0; real listing arrives in Phase 1).
public struct StopConfirmation: Sendable, Equatable {
    public var runningContainers: Int?
    public var runningMachines: Int?

    public init(runningContainers: Int? = nil, runningMachines: Int? = nil) {
        self.runningContainers = runningContainers
        self.runningMachines = runningMachines
    }

    public var hasKnownRunningResources: Bool {
        (runningContainers ?? 0) > 0 || (runningMachines ?? 0) > 0
    }
}

/// The single owner of Apple Container system state (spec §12).
///
/// Sidebar, Dashboard, Settings, and onboarding all observe this object;
/// no view keeps an independent system state. Start and stop verify the
/// final state by polling `system status` — exit code 0 is never trusted
/// as proof of a completed transition (verified against CLI 1.0.0, where
/// `start` can also exit non-zero while the apiserver comes up).
@MainActor
@Observable
public final class SystemPowerController {
    // MARK: Observable state

    public private(set) var state: ContainerSystemState = .unknown
    public private(set) var version: ContainerSystemVersion?
    public private(set) var binaryLocation: ContainerBinaryLocation?
    /// Set when an operation fails; bound to an alert.
    public var lastError: UserFacingError?
    /// Retained copy of the most recent failure so "View Details" can
    /// re-present it after the alert was dismissed.
    public private(set) var lastFailure: UserFacingError?
    /// Set when Turn Off needs confirmation; bound to a dialog.
    public var stopConfirmation: StopConfirmation?
    /// Set when starting requires a kernel-install decision; bound to a dialog.
    public var kernelInstallPrompt = false

    public var isPerformingLifecycleAction: Bool { lifecycleTask != nil }

    // MARK: Dependencies

    private let engine: any ContainerEngine
    private let operations: OperationStore
    private let settings: UserSettings
    private let locator: ContainerBinaryLocator?
    private let pollInterval: Duration
    private let startVerificationTimeout: Duration
    private let stopVerificationTimeout: Duration

    /// Called after a verified start so resource stores can refresh.
    public var onSystemStarted: (@MainActor () -> Void)?
    /// Called after a verified stop so resource stores can mark data stale.
    public var onSystemStopped: (@MainActor () -> Void)?
    /// Posts a native notification (title, body) when the app is inactive.
    public var notify: (@MainActor (String, String) -> Void)?

    private var lifecycleTask: Task<Void, Never>?

    /// - Parameters:
    ///   - locator: nil when the engine needs no binary discovery (mocks).
    ///   - pollInterval/timeouts: injectable for fast tests.
    public init(
        engine: any ContainerEngine,
        operations: OperationStore,
        settings: UserSettings,
        locator: ContainerBinaryLocator? = nil,
        pollInterval: Duration = .seconds(1),
        startVerificationTimeout: Duration = .seconds(60),
        stopVerificationTimeout: Duration = .seconds(30)
    ) {
        self.engine = engine
        self.operations = operations
        self.settings = settings
        self.locator = locator
        self.pollInterval = pollInterval
        self.startVerificationTimeout = startVerificationTimeout
        self.stopVerificationTimeout = stopVerificationTimeout
    }

    // MARK: - Launch

    /// Detects the binary and synchronizes state. Never auto-starts unless
    /// the (default-off) preference is enabled.
    public func bootstrap() async {
        if let locator {
            do {
                let location = try await locator.locate(
                    userConfiguredPath: settings.binaryPathOverride,
                    persistedPath: settings.lastDetectedBinaryPath
                )
                binaryLocation = location
                version = location.version
                settings.lastDetectedBinaryPath = location.url.path
            } catch {
                state = .unavailable
                return
            }
        } else {
            version = try? await engine.systemVersion()
        }

        await refreshStatus()

        if settings.autoStartOnLaunch, state == .stopped {
            requestTurnOn()
        }
    }

    /// Re-runs binary discovery (Settings → Re-detect).
    public func redetectBinary() async {
        guard let locator else { return }
        await locator.invalidate()
        binaryLocation = nil
        state = .unknown
        await bootstrap()
    }

    /// Adopts a manually chosen binary (Settings / onboarding file picker).
    public func adoptBinary(at url: URL) async {
        guard let locator else { return }
        do {
            let location = try await locator.adopt(manualSelection: url)
            binaryLocation = location
            version = location.version
            settings.lastDetectedBinaryPath = location.url.path
            await refreshStatus()
        } catch let error as ContainerEngineError {
            lastError = UserFacingError.make(from: error, context: "validating \(url.path)")
        } catch {
            lastError = UserFacingError.make(from: .unexpectedOutput(error.localizedDescription))
        }
    }

    /// Queries `system status` and updates state. Skipped while a lifecycle
    /// transition owns the state.
    public func refreshStatus() async {
        guard lifecycleTask == nil else { return }
        guard state != .unavailable || locator == nil else { return }
        do {
            let status = try await engine.systemStatus()
            state = status.isRunning ? .running : .stopped
        } catch let error as ContainerEngineError {
            switch error {
            case .binaryNotFound:
                state = .unavailable
            default:
                state = .failed(message: "Status check failed")
                lastError = UserFacingError.make(from: error, context: "querying system status")
            }
        } catch {
            state = .failed(message: "Status check failed")
        }
    }

    // MARK: - Turn On

    public func requestTurnOn() {
        performStart(installKernel: false)
    }

    /// User explicitly approved installing the recommended default kernel.
    public func confirmKernelInstallAndStart() {
        kernelInstallPrompt = false
        performStart(installKernel: true)
    }

    private func performStart(installKernel: Bool) {
        guard lifecycleTask == nil, state.canTurnOn else { return }
        state = .starting

        let command = installKernel
            ? "container system start --enable-kernel-install"
            : "container system start"
        let operationID = operations.begin(
            title: "Starting Apple Container",
            kind: .startSystem,
            redactedCommand: command,
            phase: "Running system start"
        )

        lifecycleTask = Task {
            defer { lifecycleTask = nil }
            do {
                try await engine.startSystem(
                    options: SystemStartOptions(installDefaultKernelIfNeeded: installKernel)
                )
                operations.updatePhase(operationID, phase: "Waiting for the system to report running")
                try await verify(running: true, within: startVerificationTimeout)
                state = .running
                operations.finish(operationID, status: .succeeded)
                onSystemStarted?()
                notify?("Apple Container", "Apple Container is now running.")
            } catch let error as ContainerEngineError {
                switch error {
                case .kernelInstallationRequired:
                    // The apiserver may have partially started; report the
                    // real state, then ask the user about the kernel.
                    await resyncStateAfterInterruption()
                    kernelInstallPrompt = true
                    operations.finish(operationID, status: .failed("A Linux kernel must be installed first"))
                case .commandCancelled:
                    await resyncStateAfterInterruption()
                    operations.finish(operationID, status: .cancelled)
                case .unexpectedOutput:
                    let facing = UserFacingError(
                        title: "Apple Container could not be started.",
                        explanation: "The start command completed, but the system did not report a running state.",
                        recommendedAction: "Retry or copy the diagnostic information for further investigation.",
                        diagnostics: "start verification timed out after \(startVerificationTimeout)"
                    )
                    state = .failed(message: "Start Failed")
                    lastFailure = facing
                    lastError = facing
                    operations.finish(operationID, status: .failed(facing.title))
                default:
                    let facing = UserFacingError.make(from: error, context: "starting Apple Container")
                    state = .failed(message: "Start Failed")
                    lastFailure = facing
                    lastError = facing
                    operations.finish(operationID, status: .failed(facing.title))
                }
            } catch is CancellationError {
                await resyncStateAfterInterruption()
                operations.finish(operationID, status: .cancelled)
            } catch {
                state = .failed(message: "Start Failed")
                lastError = UserFacingError.make(from: .unexpectedOutput(error.localizedDescription))
                operations.finish(operationID, status: .failed("Start failed"))
            }
        }
    }

    // MARK: - Turn Off

    /// Gathers running-resource counts, then either asks for confirmation or
    /// stops directly when confirmations are disabled in Settings.
    public func requestTurnOff() {
        guard state.canTurnOff, lifecycleTask == nil, stopConfirmation == nil else { return }
        Task {
            var confirmation = StopConfirmation()
            // Counts are best-effort: the Phase 0 CLI engine cannot list
            // resources yet and reports honestly unknown counts.
            if let containers = try? await engine.listContainers(all: false) {
                confirmation.runningContainers = containers.count(where: \.isRunning)
            }
            if let machines = try? await engine.listMachines() {
                confirmation.runningMachines = machines.count(where: \.isRunning)
            }
            guard state.canTurnOff, lifecycleTask == nil else { return }
            if settings.confirmBeforeStopping {
                stopConfirmation = confirmation
            } else {
                performStop()
            }
        }
    }

    public func confirmTurnOff() {
        stopConfirmation = nil
        performStop()
    }

    public func cancelTurnOff() {
        stopConfirmation = nil
    }

    private func performStop() {
        guard lifecycleTask == nil, state.canTurnOff else { return }
        state = .stopping

        let operationID = operations.begin(
            title: "Stopping Apple Container",
            kind: .stopSystem,
            redactedCommand: "container system stop",
            phase: "Running system stop"
        )

        lifecycleTask = Task {
            defer { lifecycleTask = nil }
            do {
                try await engine.stopSystem()
                operations.updatePhase(operationID, phase: "Waiting for the system to report stopped")
                try await verify(running: false, within: stopVerificationTimeout)
                state = .stopped
                operations.finish(operationID, status: .succeeded)
                onSystemStopped?()
                notify?("Apple Container", "Apple Container has been turned off.")
            } catch let error as ContainerEngineError {
                switch error {
                case .commandCancelled:
                    await resyncStateAfterInterruption()
                    operations.finish(operationID, status: .cancelled)
                case .unexpectedOutput:
                    // Stop reported success but the system still runs:
                    // reflect reality and surface the failure.
                    let facing = UserFacingError(
                        title: "Apple Container could not be stopped.",
                        explanation: "The stop command completed, but the system still reports a running state.",
                        recommendedAction: "Retry or copy the diagnostic information for further investigation.",
                        diagnostics: "stop verification timed out after \(stopVerificationTimeout)"
                    )
                    state = .running
                    lastFailure = facing
                    lastError = facing
                    operations.finish(operationID, status: .failed(facing.title))
                default:
                    let facing = UserFacingError.make(from: error, context: "stopping Apple Container")
                    state = .failed(message: "Stop Failed")
                    lastFailure = facing
                    lastError = facing
                    operations.finish(operationID, status: .failed(facing.title))
                }
            } catch is CancellationError {
                await resyncStateAfterInterruption()
                operations.finish(operationID, status: .cancelled)
            } catch {
                state = .failed(message: "Stop Failed")
                lastError = UserFacingError.make(from: .unexpectedOutput(error.localizedDescription))
                operations.finish(operationID, status: .failed("Stop failed"))
            }
        }
    }

    /// Cancels the in-flight start/stop where safe; state is re-synchronized
    /// from a fresh status query afterwards.
    public func cancelLifecycleOperation() {
        lifecycleTask?.cancel()
    }

    /// Re-presents the most recent failure (sidebar "View Details").
    public func showLastFailureDetails() {
        guard let lastFailure else { return }
        lastError = lastFailure
    }

    /// Awaits the in-flight lifecycle transition, if any (used by tests and
    /// teardown).
    public func waitForLifecycleCompletion() async {
        await lifecycleTask?.value
    }

    // MARK: - Verification

    /// Polls `system status` until the target state is observed. Exit codes
    /// are never trusted; only observed status counts (spec §12).
    private func verify(running target: Bool, within timeout: Duration) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while clock.now < deadline {
            try Task.checkCancellation()
            if let status = try? await engine.systemStatus(), status.isRunning == target {
                return
            }
            try await Task.sleep(for: pollInterval)
        }
        throw ContainerEngineError.unexpectedOutput(
            target
                ? "The system did not report a running state."
                : "The system still reports a running state."
        )
    }

    /// After cancellation or a partial start, trust only a fresh status query.
    private func resyncStateAfterInterruption() async {
        if let status = try? await engine.systemStatus() {
            state = status.isRunning ? .running : .stopped
        } else {
            state = .unknown
        }
    }
}
