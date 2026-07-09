import Foundation

/// Builds verified `container build` argument arrays. Build-arg values and
/// secret specs are masked in the redacted form (spec §8: build secrets never
/// appear in previews, logs, or history).
public enum BuildArgumentBuilder {
    public static func build(_ configuration: BuildConfiguration) throws
        -> ContainerArgumentBuilder.BuiltCommand {
        var arguments = ["build"]
        var redacted = ["build"]

        func append(_ values: String...) {
            arguments.append(contentsOf: values)
            redacted.append(contentsOf: values)
        }

        let tag = configuration.tag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty else {
            throw ContainerEngineError.invalidInput("A tag is required (e.g. my-app:latest).")
        }
        try InputValidator.validateImageReference(tag)
        append("--tag", tag)

        let dockerfile = configuration.dockerfilePath.trimmingCharacters(in: .whitespaces)
        if !dockerfile.isEmpty {
            guard dockerfile.hasPrefix("/"), FileManager.default.fileExists(atPath: dockerfile) else {
                throw ContainerEngineError.invalidInput("Dockerfile “\(dockerfile)” does not exist.")
            }
            append("--file", dockerfile)
        }

        let target = configuration.target.trimmingCharacters(in: .whitespaces)
        if !target.isEmpty {
            append("--target", target)
        }
        if configuration.noCache {
            append("--no-cache")
        }
        if configuration.pullBaseImage {
            append("--pull")
        }

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
        let platform = configuration.platform.trimmingCharacters(in: .whitespaces)
        if !platform.isEmpty {
            append("--platform", platform)
        }

        for argument in configuration.buildArguments where !argument.key.isEmpty {
            try InputValidator.validateEnvironmentKey(argument.key)
            arguments.append(contentsOf: ["--build-arg", "\(argument.key)=\(argument.value)"])
            redacted.append(contentsOf: ["--build-arg", "\(argument.key)=\(SecretRedactor.placeholder)"])
        }
        for label in configuration.labels where !label.key.isEmpty {
            try InputValidator.validateEnvironmentKey(label.key)
            append("--label", "\(label.key)=\(label.value)")
        }
        for secret in configuration.secrets where !secret.isEmpty {
            arguments.append(contentsOf: ["--secret", secret])
            redacted.append(contentsOf: ["--secret", SecretRedactor.placeholder])
        }

        append("--progress", "plain")

        let context = configuration.contextDirectory.trimmingCharacters(in: .whitespaces)
        guard context.hasPrefix("/") else {
            throw ContainerEngineError.invalidInput("Build context must be an absolute directory path.")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: context, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw ContainerEngineError.invalidInput("Build context “\(context)” is not a directory.")
        }
        append(context)

        return ContainerArgumentBuilder.BuiltCommand(arguments: arguments, redactedArguments: redacted)
    }
}
