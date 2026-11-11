import Foundation

// FotoAsist GC — open-source edition.
// This module replaces the licensing layer of the full GDC edition. There is no account, activation,
// trial or licensing server here: every feature that exists in this edition is always available.

/// Decision points of the application. They are kept so the rest of the code can ask one place
/// whether a feature may run; in this edition the answer is always yes.
public enum PhotoFeature: String, CaseIterable, Sendable {
    case exportImages = "export-images"
    case batchApply = "batch-apply"
    case profileEstimation = "profile-estimation"
    case resolveHandoff = "resolve-handoff"
    case advancedModules = "advanced-modules"
    case editProcessing = "edit-processing"
}

public protocol PhotoFeaturePolicy: Sendable {
    var name: String { get }
    var restrictsAnything: Bool { get }
    func permits(_ feature: PhotoFeature) -> Bool
}

/// The only policy of the open-source edition: nothing is restricted.
public struct OpenEditionPolicy: PhotoFeaturePolicy {
    public init() {}
    public let name = "open-source edition (no restrictions)"
    public let restrictsAnything = false
    public func permits(_ feature: PhotoFeature) -> Bool { true }
}

public enum PhotoPolicies {
    public static func standard() -> PhotoFeaturePolicy { OpenEditionPolicy() }
}

/// Name used by the shared test suite for "a policy that restricts nothing".
public typealias DevOpenPolicy = OpenEditionPolicy
