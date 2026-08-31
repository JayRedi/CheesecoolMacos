import Foundation
import ServiceManagement

@MainActor
public protocol LoginItemManaging: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

@MainActor
public final class SMAppServiceLoginItemManager: LoginItemManaging {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled, SMAppService.mainApp.status != .enabled {
            try SMAppService.mainApp.register()
        } else if !enabled, SMAppService.mainApp.status == .enabled {
            try SMAppService.mainApp.unregister()
        }
    }
}

@MainActor
public final class FakeLoginItemManager: LoginItemManaging {
    public private(set) var isEnabled: Bool
    public var injectedError: Error?

    public init(isEnabled: Bool = false) {
        self.isEnabled = isEnabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if let injectedError { throw injectedError }
        isEnabled = enabled
    }
}
