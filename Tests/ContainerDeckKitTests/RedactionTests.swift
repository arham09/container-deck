import Foundation
import Testing
@testable import ContainerDeckKit

@Suite("Secret redaction")
struct RedactionTests {
    @Test("Environment values are redacted, keys preserved")
    func environmentValues() {
        let redacted = SecretRedactor.redactArguments([
            "run", "--name", "postgres",
            "-e", "POSTGRES_PASSWORD=hunter2",
            "-e", "PGDATA=/var/lib/postgresql/data",
            "postgres:17",
        ])
        #expect(redacted == [
            "run", "--name", "postgres",
            "-e", "POSTGRES_PASSWORD=<redacted>",
            "-e", "PGDATA=<redacted>",
            "postgres:17",
        ])
        #expect(!redacted.joined().contains("hunter2"))
    }

    @Test("Password-style flags are fully redacted in both forms")
    func passwordFlags() {
        #expect(
            SecretRedactor.redactArguments(["login", "--password", "s3cret", "ghcr.io"])
                == ["login", "--password", "<redacted>", "ghcr.io"]
        )
        #expect(
            SecretRedactor.redactArguments(["login", "--password=s3cret"])
                == ["login", "--password=<redacted>"]
        )
    }

    @Test("Non-sensitive arguments pass through unchanged")
    func passthrough() {
        let arguments = ["system", "start", "--enable-kernel-install"]
        #expect(SecretRedactor.redactArguments(arguments) == arguments)
    }

    @Test("Free-text redaction removes known secrets")
    func text() {
        let text = "connecting with token abc123 to registry"
        #expect(SecretRedactor.redactText(text, secrets: ["abc123"]) == "connecting with token <redacted> to registry")
    }

    @Test("CommandRequest display uses redacted arguments, never the real ones")
    func displayCommand() {
        let arguments = ["run", "-e", "API_KEY=topsecret", "img"]
        let request = CommandRequest(
            executable: URL(fileURLWithPath: "/usr/local/bin/container"),
            arguments: arguments,
            redactedArguments: SecretRedactor.redactArguments(arguments)
        )
        #expect(request.displayCommand == "container run -e API_KEY=<redacted> img")
        #expect(!request.displayCommand.contains("topsecret"))
        // Execution still sees the real values.
        #expect(request.arguments == arguments)
    }

    @Test("Shell-style formatting quotes only for display")
    func formatting() {
        let formatted = ShellCommandFormatter.format(
            executable: URL(fileURLWithPath: "/usr/local/bin/container"),
            arguments: ["run", "--name", "my container", "img"]
        )
        #expect(formatted == "container run --name 'my container' img")
    }
}

@Suite("Input validation")
struct InputValidatorTests {
    @Test("Valid resource names pass")
    func validNames() throws {
        try InputValidator.validateResourceName("payment-api")
        try InputValidator.validateResourceName("ubuntu_dev.2")
        try InputValidator.validateResourceName("a")
    }

    @Test("Invalid resource names are rejected")
    func invalidNames() {
        #expect(throws: ContainerEngineError.self) {
            try InputValidator.validateResourceName("")
        }
        #expect(throws: ContainerEngineError.self) {
            try InputValidator.validateResourceName("has space")
        }
        #expect(throws: ContainerEngineError.self) {
            try InputValidator.validateResourceName("-leading-dash")
        }
        #expect(throws: ContainerEngineError.self) {
            try InputValidator.validateResourceName("semi;colon")
        }
        #expect(throws: ContainerEngineError.self) {
            try InputValidator.validateResourceName(String(repeating: "x", count: 200))
        }
    }

    @Test("Executable path validation checks existence and permissions")
    func executablePaths() throws {
        try InputValidator.validateExecutablePath("/bin/echo")
        #expect(throws: ContainerEngineError.self) {
            try InputValidator.validateExecutablePath("relative/path")
        }
        #expect(throws: ContainerEngineError.self) {
            try InputValidator.validateExecutablePath("/nonexistent/binary")
        }
    }
}
