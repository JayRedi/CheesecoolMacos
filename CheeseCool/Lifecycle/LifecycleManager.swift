import Foundation

public actor LifecycleManager {
    private let controlSession: ControlSession

    public init(controlSession: ControlSession) {
        self.controlSession = controlSession
    }

    public func prepareForSleep() async {
        await controlSession.prepareForSleep()
    }

    public func resumeFromSleep() async {
        await controlSession.resumeFromSleep()
    }

    public func stop() async {
        await controlSession.stop()
    }
}
