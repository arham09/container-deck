import Foundation
import Testing
@testable import ContainerDeckKit

@MainActor
@Suite("System lifecycle (SystemPowerController + MockContainerEngine)")
struct SystemLifecycleTests {
    private func makeController(
        engine: MockContainerEngine,
        settings: UserSettings? = nil
    ) -> (SystemPowerController, OperationStore, UserSettings) {
        let operations = OperationStore()
        let settings = settings ?? makeTestSettings()
        let controller = SystemPowerController(
            engine: engine,
            operations: operations,
            settings: settings,
            pollInterval: .milliseconds(20),
            startVerificationTimeout: .milliseconds(600),
            stopVerificationTimeout: .milliseconds(400)
        )
        return (controller, operations, settings)
    }

    // MARK: Initial state

    @Test("Bootstrap detects an initially running system")
    func initialRunning() async {
        let engine = MockContainerEngine(running: true)
        let (controller, _, _) = makeController(engine: engine)
        await controller.bootstrap()
        #expect(controller.state == .running)
        #expect(controller.version?.version == "1.0.0")
    }

    @Test("Bootstrap detects an initially stopped system and never auto-starts")
    func initialStopped() async {
        let engine = MockContainerEngine(running: false)
        let (controller, operations, _) = makeController(engine: engine)
        await controller.bootstrap()
        #expect(controller.state == .stopped)
        #expect(operations.operations.isEmpty)
    }

    @Test("Auto-start preference (default off) starts the system when enabled")
    func autoStart() async {
        let engine = MockContainerEngine(
            running: false,
            startBehavior: .success(becomesRunningAfter: .milliseconds(50))
        )
        let settings = makeTestSettings()
        #expect(settings.autoStartOnLaunch == false)
        settings.autoStartOnLaunch = true

        let (controller, _, _) = makeController(engine: engine, settings: settings)
        await controller.bootstrap()
        await controller.waitForLifecycleCompletion()
        #expect(controller.state == .running)
    }

    // MARK: Start

    @Test("Successful start verifies via status polling")
    func successfulStart() async {
        let engine = MockContainerEngine(
            running: false,
            startBehavior: .success(becomesRunningAfter: .milliseconds(100))
        )
        let (controller, operations, _) = makeController(engine: engine)
        await controller.refreshStatus()

        var refreshed = false
        controller.onSystemStarted = { refreshed = true }
        controller.requestTurnOn()
        #expect(controller.state == .starting)
        await controller.waitForLifecycleCompletion()

        #expect(controller.state == .running)
        #expect(refreshed)
        #expect(operations.operations.first?.status == .succeeded)
        #expect(operations.operations.first?.redactedCommand == "container system start")
    }

    @Test("Start command succeeds but status stays stopped → failed state")
    func startSucceedsButStaysStopped() async {
        let engine = MockContainerEngine(running: false, startBehavior: .succeedsButStaysStopped)
        let (controller, operations, _) = makeController(engine: engine)
        await controller.refreshStatus()

        controller.requestTurnOn()
        await controller.waitForLifecycleCompletion()

        #expect(controller.state == .failed(message: "Start Failed"))
        #expect(controller.lastError?.title == "Apple Container could not be started.")
        #expect(controller.lastError?.explanation.contains("did not report a running state") == true)
        if case .failed = operations.operations.first?.status {} else {
            Issue.record("expected a failed operation")
        }
    }

    @Test("Start command failure surfaces a user-facing error")
    func startFailure() async {
        let engine = MockContainerEngine(running: false, startBehavior: .fails(message: "boom"))
        let (controller, _, _) = makeController(engine: engine)
        await controller.refreshStatus()

        controller.requestTurnOn()
        await controller.waitForLifecycleCompletion()

        #expect(controller.state == .failed(message: "Start Failed"))
        #expect(controller.lastError != nil)
        // Diagnostics carry the stderr for copy-out.
        #expect(controller.lastError?.diagnostics.contains("boom") == true)
    }

    @Test("Kernel-install requirement prompts instead of failing silently")
    func kernelInstallPrompt() async {
        let engine = MockContainerEngine(running: false, startBehavior: .requiresKernelInstall)
        let (controller, _, _) = makeController(engine: engine)
        await controller.refreshStatus()

        controller.requestTurnOn()
        await controller.waitForLifecycleCompletion()

        #expect(controller.kernelInstallPrompt)
        #expect(controller.state == .stopped)

        // Explicit consent retries with the install flag; the mock then starts.
        controller.confirmKernelInstallAndStart()
        await controller.waitForLifecycleCompletion()
        #expect(controller.state == .running)
    }

    @Test("Duplicate start requests are ignored while one is in flight")
    func duplicateStartPrevented() async {
        let engine = MockContainerEngine(
            running: false,
            startBehavior: .success(becomesRunningAfter: .milliseconds(150))
        )
        let (controller, operations, _) = makeController(engine: engine)
        await controller.refreshStatus()

        controller.requestTurnOn()
        controller.requestTurnOn()
        controller.requestTurnOn()
        await controller.waitForLifecycleCompletion()

        #expect(operations.operations.count == 1)
        #expect(controller.state == .running)
    }

    @Test("Cancelling a start re-synchronizes from a fresh status query")
    func startCancellation() async {
        let engine = MockContainerEngine(
            running: false,
            startBehavior: .success(becomesRunningAfter: .seconds(30))
        )
        let (controller, operations, _) = makeController(engine: engine)
        await controller.refreshStatus()

        controller.requestTurnOn()
        try? await Task.sleep(for: .milliseconds(60))
        controller.cancelLifecycleOperation()
        await controller.waitForLifecycleCompletion()

        #expect(controller.state == .stopped)
        #expect(operations.operations.first?.status == .cancelled)
    }

    // MARK: Stop

    @Test("Turn Off requests confirmation with running-resource counts")
    func stopConfirmationCounts() async {
        let engine = MockContainerEngine(running: true)
        let (controller, _, _) = makeController(engine: engine)
        await controller.refreshStatus()

        controller.requestTurnOff()
        let appeared = await eventually { controller.stopConfirmation != nil }
        #expect(appeared)
        // MockData: 3 running containers, 1 running machine.
        #expect(controller.stopConfirmation?.runningContainers == 3)
        #expect(controller.stopConfirmation?.runningMachines == 1)
        #expect(controller.stopConfirmation?.hasKnownRunningResources == true)

        // Cancelling leaves the system untouched.
        controller.cancelTurnOff()
        #expect(controller.state == .running)
    }

    @Test("Confirmed stop verifies via polling and preserves resources")
    func successfulStop() async {
        let engine = MockContainerEngine(
            running: true,
            stopBehavior: .success(becomesStoppedAfter: .milliseconds(100))
        )
        let (controller, operations, _) = makeController(engine: engine)
        await controller.refreshStatus()

        var markedStale = false
        controller.onSystemStopped = { markedStale = true }

        controller.requestTurnOff()
        _ = await eventually { controller.stopConfirmation != nil }
        controller.confirmTurnOff()
        #expect(controller.state == .stopping)
        await controller.waitForLifecycleCompletion()

        #expect(controller.state == .stopped)
        #expect(markedStale)
        #expect(operations.operations.first?.status == .succeeded)

        // Stopping must never delete resources (spec §12).
        let containers = try? await engine.listContainers(all: true)
        let machines = try? await engine.listMachines()
        #expect(containers?.count == MockData.containers.count)
        #expect(machines?.count == MockData.machines.count)
    }

    @Test("Disabled confirmation preference stops without a dialog")
    func stopWithoutConfirmation() async {
        let engine = MockContainerEngine(
            running: true,
            stopBehavior: .success(becomesStoppedAfter: .milliseconds(50))
        )
        let settings = makeTestSettings()
        settings.confirmBeforeStopping = false
        let (controller, _, _) = makeController(engine: engine, settings: settings)
        await controller.refreshStatus()

        controller.requestTurnOff()
        let stopped = await eventually { controller.state == .stopped }
        #expect(stopped)
        #expect(controller.stopConfirmation == nil)
    }

    @Test("Stop command succeeds but status stays running → honest running state + error")
    func stopSucceedsButStaysRunning() async {
        let engine = MockContainerEngine(running: true, stopBehavior: .succeedsButStaysRunning)
        let (controller, _, _) = makeController(engine: engine)
        await controller.refreshStatus()

        controller.requestTurnOff()
        _ = await eventually { controller.stopConfirmation != nil }
        controller.confirmTurnOff()
        await controller.waitForLifecycleCompletion()

        #expect(controller.state == .running)
        #expect(controller.lastError?.title == "Apple Container could not be stopped.")
    }

    @Test("Stop command failure surfaces a user-facing error")
    func stopFailure() async {
        let engine = MockContainerEngine(running: true, stopBehavior: .fails(message: "stop broke"))
        let (controller, _, _) = makeController(engine: engine)
        await controller.refreshStatus()

        controller.requestTurnOff()
        _ = await eventually { controller.stopConfirmation != nil }
        controller.confirmTurnOff()
        await controller.waitForLifecycleCompletion()

        #expect(controller.state == .failed(message: "Stop Failed"))
        #expect(controller.lastError?.diagnostics.contains("stop broke") == true)
    }

    @Test("Start and stop cannot run simultaneously")
    func noSimultaneousLifecycleMutations() async {
        let engine = MockContainerEngine(
            running: false,
            startBehavior: .success(becomesRunningAfter: .milliseconds(150))
        )
        let (controller, operations, _) = makeController(engine: engine)
        await controller.refreshStatus()

        controller.requestTurnOn()
        // A stop request during .starting must be rejected outright.
        controller.requestTurnOff()
        #expect(controller.stopConfirmation == nil)
        await controller.waitForLifecycleCompletion()

        #expect(operations.operations.count == 1)
        #expect(controller.state == .running)
    }
}
