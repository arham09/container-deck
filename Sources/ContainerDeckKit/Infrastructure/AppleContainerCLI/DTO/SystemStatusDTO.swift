import Foundation

/// Raw shape of `container system status --format json`.
///
/// Captured from Apple Container CLI 1.0.0
/// (fixtures: system-status-running.json, system-status-stopped.json).
/// Every field is optional so missing keys never break decoding; unknown
/// extra keys are ignored by `Decodable`.
struct SystemStatusDTO: Decodable {
    var status: String?
    var apiServerAppName: String?
    var apiServerVersion: String?
    var apiServerBuild: String?
    var apiServerCommit: String?
    var appRoot: String?
    var installRoot: String?
}
