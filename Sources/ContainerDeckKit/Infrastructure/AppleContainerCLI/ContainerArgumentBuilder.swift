import Foundation

/// Builds verified `container run`/`create` argument arrays from a
/// `ContainerRunConfiguration`. All flags below were verified against CLI
/// 1.0.0 help output; the `--mount` and `-v` formats were exercised against
/// real containers (see docs/supported-commands.md).
///
/// Output is always an argument array — never a shell string. The redacted
/// variant masks every environment value (spec §8).
public enum ContainerArgumentBuilder {
    public struct BuiltCommand: Sendable, Equatable {
        public let arguments: [String]
        public let redactedArguments: [String]
    }

    public static func build(_ configuration: ContainerRunConfiguration) throws -> BuiltCommand {
        var arguments: [String] = [configuration.mode.rawValue]
        var redacted: [String] = [configuration.mode.rawValue]

        func append(_ values: String...) {
            arguments.append(contentsOf: values)
            redacted.append(contentsOf: values)
        }

        // Identity
        let name = configuration.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty {
            try InputValidator.validateResourceName(name)
            append("--name", name)
        }

        // Runtime options (run-only flags guarded by mode)
        if configuration.mode == .run, configuration.detached {
            append("--detach")
        }
        if configuration.removeAfterStop {
            append("--rm")
        }
        if configuration.useInit {
            append("--init")
        }
        if configuration.readOnlyRootFilesystem {
            append("--read-only")
        }
        let entrypoint = configuration.entrypoint.trimmingCharacters(in: .whitespaces)
        if !entrypoint.isEmpty {
            append("--entrypoint", entrypoint)
        }
        let workdir = configuration.workingDirectory.trimmingCharacters(in: .whitespaces)
        if !workdir.isEmpty {
            guard workdir.hasPrefix("/") else {
                throw ContainerEngineError.invalidInput("Working directory must be an absolute path.")
            }
            append("--workdir", workdir)
        }

        // Resources
        let cpus = configuration.cpus.trimmingCharacters(in: .whitespaces)
        if !cpus.isEmpty {
            try InputValidator.validateCPUCount(cpus)
            append("--cpus", cpus)
        }
        let memory = configuration.memory.trimmingCharacters(in: .whitespaces)
        if !memory.isEmpty {
            try InputValidator.validateMemoryString(memory)
            append("--memory", memory)
        }
        let shmSize = configuration.shmSize.trimmingCharacters(in: .whitespaces)
        if !shmSize.isEmpty {
            try InputValidator.validateMemoryString(shmSize)
            append("--shm-size", shmSize)
        }

        // Platform
        let architecture = configuration.architecture.trimmingCharacters(in: .whitespaces)
        if !architecture.isEmpty {
            append("--arch", architecture)
        }
        let os = configuration.os.trimmingCharacters(in: .whitespaces)
        if !os.isEmpty {
            append("--os", os)
        }
        let platform = configuration.platform.trimmingCharacters(in: .whitespaces)
        if !platform.isEmpty {
            append("--platform", platform)
        }

        // Environment (values are redacted in previews — spec §8)
        for entry in configuration.environment where !entry.key.isEmpty {
            try InputValidator.validateEnvironmentKey(entry.key)
            arguments.append(contentsOf: ["--env", "\(entry.key)=\(entry.value)"])
            redacted.append(contentsOf: ["--env", "\(entry.key)=\(SecretRedactor.placeholder)"])
        }
        let environmentFile = configuration.environmentFile.trimmingCharacters(in: .whitespaces)
        if !environmentFile.isEmpty {
            guard environmentFile.hasPrefix("/") else {
                throw ContainerEngineError.invalidInput("Environment file must be an absolute path.")
            }
            append("--env-file", environmentFile)
        }

        // Labels
        for label in configuration.labels where !label.key.isEmpty {
            try InputValidator.validateEnvironmentKey(label.key)
            append("--label", "\(label.key)=\(label.value)")
        }

        // Published ports: [host-ip:]host-port:container-port[/protocol]
        for port in configuration.publishedPorts {
            let hostPort = port.hostPort.trimmingCharacters(in: .whitespaces)
            let containerPort = port.containerPort.trimmingCharacters(in: .whitespaces)
            guard !hostPort.isEmpty || !containerPort.isEmpty else { continue }
            try InputValidator.validatePort(hostPort)
            try InputValidator.validatePort(containerPort)
            var spec = ""
            let hostIP = port.hostIP.trimmingCharacters(in: .whitespaces)
            if !hostIP.isEmpty {
                try InputValidator.validateIPv4(hostIP)
                spec += "\(hostIP):"
            }
            spec += "\(hostPort):\(containerPort)/\(port.portProtocol.rawValue)"
            append("--publish", spec)
        }

        // Mounts: verified format type=bind,source=…,target=…[,readonly]
        for mount in configuration.mounts {
            let source = mount.source.trimmingCharacters(in: .whitespaces)
            let target = mount.target.trimmingCharacters(in: .whitespaces)
            guard !source.isEmpty || !target.isEmpty else { continue }
            try InputValidator.validateMountSource(source)
            try InputValidator.validateMountTarget(target)
            var spec = "type=bind,source=\(source),target=\(target)"
            if mount.readOnly {
                spec += ",readonly"
            }
            append("--mount", spec)
        }

        // Networks
        for network in configuration.networks {
            let networkName = network.name.trimmingCharacters(in: .whitespaces)
            guard !networkName.isEmpty else { continue }
            try InputValidator.validateResourceName(networkName)
            append("--network", networkName)
        }

        // Progress output stays machine-friendly for operation logs.
        append("--progress", "plain")

        // Image
        let image = configuration.image.trimmingCharacters(in: .whitespaces)
        try InputValidator.validateImageReference(image)
        append(image)

        // Init-process arguments
        let commandArguments = tokenize(configuration.commandLine)
        arguments.append(contentsOf: commandArguments)
        redacted.append(contentsOf: commandArguments)

        return BuiltCommand(arguments: arguments, redactedArguments: redacted)
    }

    /// Splits a command line into arguments with single/double-quote support.
    /// This is tokenization only — the result is passed as argv, never to a shell.
    public static func tokenize(_ commandLine: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var hasContent = false
        var quote: Character?

        for character in commandLine {
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
            } else if character == "\"" || character == "'" {
                quote = character
                hasContent = true
            } else if character.isWhitespace {
                if hasContent || !current.isEmpty {
                    tokens.append(current)
                    current = ""
                    hasContent = false
                }
            } else {
                current.append(character)
            }
        }
        if hasContent || !current.isEmpty {
            tokens.append(current)
        }
        return tokens
    }
}
