import Foundation
import CheeseCoolCore

public struct MenuBarVisibility: Equatable {
    public let mainIconVisible: Bool
    public let visibleMetrics: Set<MetricIdentifier>
}

public enum MenuBarVisibilityPolicy {
    public static func resolve(
        preferredMainIconVisible: Bool,
        visibleMetrics: Set<MetricIdentifier>
    ) -> MenuBarVisibility {
        MenuBarVisibility(
            mainIconVisible: visibleMetrics.isEmpty ? true : preferredMainIconVisible,
            visibleMetrics: visibleMetrics
        )
    }
}
