import Foundation

/// Validates user-provided values before they reach an argument array.
/// Phase 0 needs paths and resource names; later phases extend this with
/// ports, memory sizes, image references, subnets, and mounts.
public enum InputValidator {
    /// Container/machine/volume/network-style resource names.
    public static func validateResourceName(_ name: String) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ContainerEngineError.invalidInput("Name must not be empty.")
        }
        guard trimmed.count <= 128 else {
            throw ContainerEngineError.invalidInput("Name must be 128 characters or fewer.")
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw ContainerEngineError.invalidInput(
                "Name may only contain letters, numbers, dashes, underscores, and dots."
            )
        }
        guard let first = trimmed.unicodeScalars.first,
              CharacterSet.alphanumerics.contains(first) else {
            throw ContainerEngineError.invalidInput("Name must start with a letter or number.")
        }
    }

    /// TCP/UDP port in 1...65535.
    public static func validatePort(_ port: String) throws {
        guard let value = Int(port), (1...65535).contains(value) else {
            throw ContainerEngineError.invalidInput("Port must be a number between 1 and 65535.")
        }
    }

    /// Memory strings per verified CLI help: bytes with optional K/M/G/T/P suffix.
    public static func validateMemoryString(_ memory: String) throws {
        let pattern = /^[0-9]+(?:[KMGTPkmgtp][iI]?[bB]?)?$/
        guard memory.wholeMatch(of: pattern) != nil else {
            throw ContainerEngineError.invalidInput(
                "Memory must be a number with an optional K, M, G, T, or P suffix (e.g. 512M, 4G)."
            )
        }
    }

    /// Environment/label keys: POSIX-style identifier.
    public static func validateEnvironmentKey(_ key: String) throws {
        let pattern = /^[A-Za-z_][A-Za-z0-9_.-]*$/
        guard key.wholeMatch(of: pattern) != nil else {
            throw ContainerEngineError.invalidInput(
                "Key “\(key)” must start with a letter or underscore and contain no spaces or “=”."
            )
        }
    }

    /// Positive CPU count.
    public static func validateCPUCount(_ cpus: String) throws {
        guard let value = Int(cpus), value > 0 else {
            throw ContainerEngineError.invalidInput("CPUs must be a positive whole number.")
        }
    }

    /// Image references: conservative character set, no whitespace.
    public static func validateImageReference(_ reference: String) throws {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ContainerEngineError.invalidInput("Image must not be empty.")
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:@+"))
        guard trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else {
            throw ContainerEngineError.invalidInput(
                "Image reference contains unsupported characters."
            )
        }
    }

    /// Bind-mount source: absolute path that exists.
    public static func validateMountSource(_ path: String) throws {
        guard path.hasPrefix("/") else {
            throw ContainerEngineError.invalidInput("Mount source must be an absolute path.")
        }
        guard !path.contains(","), FileManager.default.fileExists(atPath: path) else {
            throw ContainerEngineError.invalidInput("Mount source “\(path)” does not exist.")
        }
    }

    /// In-container target path: absolute, no commas (the --mount format is
    /// comma-separated).
    public static func validateMountTarget(_ path: String) throws {
        guard path.hasPrefix("/"), !path.contains(",") else {
            throw ContainerEngineError.invalidInput("Mount target must be an absolute path without commas.")
        }
    }

    /// Basic IPv4 shape for published-port host addresses.
    public static func validateIPv4(_ address: String) throws {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4,
              parts.allSatisfy({ UInt8($0) != nil }) else {
            throw ContainerEngineError.invalidInput("“\(address)” is not a valid IPv4 address.")
        }
    }

    /// Absolute filesystem path expected to exist and be executable.
    public static func validateExecutablePath(_ path: String) throws {
        guard path.hasPrefix("/") else {
            throw ContainerEngineError.invalidInput("Path must be absolute.")
        }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            throw ContainerEngineError.invalidInput("No file exists at \(path).")
        }
        guard FileManager.default.isExecutableFile(atPath: path) else {
            throw ContainerEngineError.invalidInput("The file at \(path) is not executable.")
        }
    }
}
