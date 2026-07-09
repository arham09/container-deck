import Foundation

/// Raw shape of one entry of `container system version --format json`.
///
/// Captured from Apple Container CLI 1.0.0 (fixture: system-version.json):
/// the command emits a JSON *array* of component objects.
struct SystemVersionEntryDTO: Decodable {
    var appName: String?
    var version: String?
    var commit: String?
    var buildType: String?
}
