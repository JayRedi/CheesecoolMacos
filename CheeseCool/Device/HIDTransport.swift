import Foundation
import IOKit.hid

public enum HIDTransportError: Error, Equatable, LocalizedError, Sendable {
    case deviceNotFound
    case deviceDisconnected
    case openFailed(Int32)
    case writeFailed(Int32)
    case readFailed(Int32)
    case timeout
    case invalidReportLength(Int)
    case unsupportedDevice
    case transportClosed
    case transactionInFlight

    public var errorDescription: String? {
        switch self {
        case .deviceNotFound: return "未找到 CheeseCool USB HID 设备"
        case .deviceDisconnected: return "CheeseCool USB HID 设备已断开"
        case .openFailed(let code): return "无法打开 CheeseCool HID 设备（IOKit \(code)）"
        case .writeFailed(let code): return "HID 写入失败（IOKit \(code)）"
        case .readFailed(let code): return "HID 读取失败（IOKit \(code)）"
        case .timeout: return "HID 请求超时"
        case .invalidReportLength(let length): return "HID 输入报告长度无效：\(length)"
        case .unsupportedDevice: return "不支持的 HID 设备"
        case .transportClosed: return "HID 传输已关闭"
        case .transactionInFlight: return "已有 HID 请求正在进行"
        }
    }
}

public struct HIDDeviceIdentity: Equatable, Comparable, Sendable {
    public static let cheeseCoolVendorID = 0x1A86
    public static let cheeseCoolProductID = 0xFE01
    public static let goldenDFUProductID = 0x8035

    public let vendorID: Int
    public let productID: Int
    public let locationID: UInt32?
    public let serialNumber: String?
    public let registryID: UInt64

    public init(
        vendorID: Int = HIDDeviceIdentity.cheeseCoolVendorID,
        productID: Int = HIDDeviceIdentity.cheeseCoolProductID,
        locationID: UInt32? = nil,
        serialNumber: String? = nil,
        registryID: UInt64
    ) {
        self.vendorID = vendorID
        self.productID = productID
        self.locationID = locationID
        self.serialNumber = serialNumber
        self.registryID = registryID
    }

    public static func < (lhs: HIDDeviceIdentity, rhs: HIDDeviceIdentity) -> Bool {
        let left = (lhs.locationID ?? UInt32.max, lhs.serialNumber ?? "", lhs.registryID)
        let right = (rhs.locationID ?? UInt32.max, rhs.serialNumber ?? "", rhs.registryID)
        return left < right
    }

    public var displayName: String {
        if let serialNumber, !serialNumber.isEmpty { return "序列号 \(serialNumber)" }
        if let locationID { return String(format: "位置 0x%08X", locationID) }
        return String(format: "注册表 0x%016llX", registryID)
    }
}

public protocol HIDDeviceDiscovering: Sendable {
    func start()
    func stop()
    func selectedDevice() -> HIDDeviceIdentity?
    func matchingDevices() -> [HIDDeviceIdentity]
    func setRemovalHandler(_ handler: @escaping @Sendable (HIDDeviceIdentity) -> Void)
}

public protocol HIDTransport: Sendable {
    func open(_ identity: HIDDeviceIdentity) async throws
    func close() async
    var isOpen: Bool { get async }
    func transact(_ frame: [UInt8], timeout: Duration) async throws -> [UInt8]
}

/// Native passive discovery for only the CheeseCool application VID/PID (1A86:FE01).
/// The golden DFU PID (1A86:8035) is deliberately not matched and never opened here.
public final class HIDDeviceDiscovery: HIDDeviceDiscovering, @unchecked Sendable {
    private let lock = NSLock()
    private let manager: IOHIDManager
    private var identities: [UInt64: HIDDeviceIdentity] = [:]
    private var rawDevices: [UInt64: IOHIDDevice] = [:]
    private var removalHandler: (@Sendable (HIDDeviceIdentity) -> Void)?
    private var started = false

    public init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))
        let matching: [String: Any] = [
            kIOHIDVendorIDKey as String: HIDDeviceIdentity.cheeseCoolVendorID,
            kIOHIDProductIDKey as String: HIDDeviceIdentity.cheeseCoolProductID
        ]
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)
    }

    public func start() {
        lock.lock()
        guard !started else { lock.unlock(); return }
        started = true
        lock.unlock()

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceAdded, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemoved, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        let result = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { return }
        if let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> {
            for device in devices { add(device) }
        }
    }

    public func stop() {
        lock.lock()
        guard started else { lock.unlock(); return }
        started = false
        identities.removeAll()
        rawDevices.removeAll()
        lock.unlock()
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.commonModes.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
    }

    public func selectedDevice() -> HIDDeviceIdentity? {
        lock.lock(); defer { lock.unlock() }
        return identities.values.sorted().first
    }

    public func matchingDevices() -> [HIDDeviceIdentity] {
        lock.lock(); defer { lock.unlock() }
        return identities.values.sorted()
    }

    public func setRemovalHandler(_ handler: @escaping @Sendable (HIDDeviceIdentity) -> Void) {
        lock.lock(); defer { lock.unlock() }
        removalHandler = handler
    }

    func rawDevice(for identity: HIDDeviceIdentity) -> IOHIDDevice? {
        lock.lock(); defer { lock.unlock() }
        return rawDevices[identity.registryID]
    }

    private static let deviceAdded: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<HIDDeviceDiscovery>.fromOpaque(context).takeUnretainedValue().add(device)
    }

    private static let deviceRemoved: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<HIDDeviceDiscovery>.fromOpaque(context).takeUnretainedValue().remove(device)
    }

    private func add(_ device: IOHIDDevice) {
        guard let identity = Self.identity(for: device),
              identity.vendorID == HIDDeviceIdentity.cheeseCoolVendorID,
              identity.productID == HIDDeviceIdentity.cheeseCoolProductID else { return }
        lock.lock()
        identities[identity.registryID] = identity
        rawDevices[identity.registryID] = device
        lock.unlock()
    }

    private func remove(_ device: IOHIDDevice) {
        guard let identity = Self.identity(for: device) else { return }
        lock.lock()
        let removed = identities.removeValue(forKey: identity.registryID)
        rawDevices.removeValue(forKey: identity.registryID)
        let handler = removalHandler
        lock.unlock()
        if let removed { handler?(removed) }
    }

    private static func identity(for device: IOHIDDevice) -> HIDDeviceIdentity? {
        let vendorID = (IOHIDDeviceGetProperty(device, kIOHIDVendorIDKey as CFString) as? NSNumber)?.intValue
        let productID = (IOHIDDeviceGetProperty(device, kIOHIDProductIDKey as CFString) as? NSNumber)?.intValue
        guard let vendorID, let productID else { return nil }
        let locationID = (IOHIDDeviceGetProperty(device, kIOHIDLocationIDKey as CFString) as? NSNumber)?.uint32Value
        let serialNumber = IOHIDDeviceGetProperty(device, kIOHIDSerialNumberKey as CFString) as? String
        var registryID: UInt64 = 0
        let service = IOHIDDeviceGetService(device)
        guard IORegistryEntryGetRegistryEntryID(service, &registryID) == KERN_SUCCESS, registryID != 0 else { return nil }
        return HIDDeviceIdentity(
            vendorID: vendorID,
            productID: productID,
            locationID: locationID,
            serialNumber: serialNumber,
            registryID: registryID
        )
    }
}

/// Uses IOHIDDeviceSetReport with report ID 0 and exactly the 64-byte Protocol V1 frame.
/// The firmware has no Report ID, so unlike hidapi's 65-byte convention no leading byte is
/// prepended to this IOKit output buffer. Input callbacks likewise receive a 64-byte frame.
public final class NativeHIDTransport: HIDTransport, @unchecked Sendable {
    private struct PendingTransaction {
        let id: UUID
        let continuation: CheckedContinuation<[UInt8], Error>
    }

    private let discovery: HIDDeviceDiscovery
    private let lock = NSLock()
    private let inputBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: ProtocolV1Codec.frameLength)
    private var device: IOHIDDevice?
    private var identity: HIDDeviceIdentity?
    private var pending: PendingTransaction?

    public init(discovery: HIDDeviceDiscovery) {
        self.discovery = discovery
        inputBuffer.initialize(repeating: 0, count: ProtocolV1Codec.frameLength)
    }

    deinit {
        inputBuffer.deinitialize(count: ProtocolV1Codec.frameLength)
        inputBuffer.deallocate()
    }

    public var isOpen: Bool {
        lock.lock(); defer { lock.unlock() }
        return device != nil
    }

    public func open(_ identity: HIDDeviceIdentity) async throws {
        guard identity.vendorID == HIDDeviceIdentity.cheeseCoolVendorID,
              identity.productID == HIDDeviceIdentity.cheeseCoolProductID else {
            throw HIDTransportError.unsupportedDevice
        }
        guard let rawDevice = discovery.rawDevice(for: identity) else { throw HIDTransportError.deviceNotFound }
        let alreadyOpen = lock.withLock { self.identity == identity && device != nil }
        if alreadyOpen { return }
        let result = IOHIDDeviceOpen(rawDevice, IOOptionBits(kIOHIDOptionsTypeNone))
        guard result == kIOReturnSuccess else { throw HIDTransportError.openFailed(result) }
        IOHIDDeviceRegisterInputReportCallback(
            rawDevice,
            inputBuffer,
            ProtocolV1Codec.frameLength,
            Self.inputReport,
            Unmanaged.passUnretained(self).toOpaque()
        )
        lock.withLock {
            device = rawDevice
            self.identity = identity
        }
    }

    public func close() async {
        let state = lock.withLock { () -> (IOHIDDevice?, PendingTransaction?) in
            let currentDevice = device
            let currentPending = pending
            device = nil
            identity = nil
            pending = nil
            return (currentDevice, currentPending)
        }
        let deviceToClose = state.0
        let pendingTransaction = state.1
        if let deviceToClose { IOHIDDeviceClose(deviceToClose, IOOptionBits(kIOHIDOptionsTypeNone)) }
        pendingTransaction?.continuation.resume(throwing: HIDTransportError.transportClosed)
    }

    public func transact(_ frame: [UInt8], timeout: Duration) async throws -> [UInt8] {
        guard frame.count == ProtocolV1Codec.frameLength else { throw HIDTransportError.invalidReportLength(frame.count) }
        return try await withCheckedThrowingContinuation { continuation in
            let id = UUID()
            lock.lock()
            guard let device else {
                lock.unlock()
                continuation.resume(throwing: HIDTransportError.transportClosed)
                return
            }
            guard pending == nil else {
                lock.unlock()
                continuation.resume(throwing: HIDTransportError.transactionInFlight)
                return
            }
            pending = PendingTransaction(id: id, continuation: continuation)
            lock.unlock()

            let result = frame.withUnsafeBufferPointer { buffer -> IOReturn in
                guard let baseAddress = buffer.baseAddress else { return kIOReturnBadArgument }
                return IOHIDDeviceSetReport(
                    device,
                    kIOHIDReportTypeOutput,
                    0,
                    baseAddress,
                    ProtocolV1Codec.frameLength
                )
            }
            guard result == kIOReturnSuccess else {
                resolve(id: id, result: .failure(HIDTransportError.writeFailed(result)))
                return
            }
            Task { [weak self] in
                try? await Task.sleep(for: timeout)
                self?.resolve(id: id, result: .failure(HIDTransportError.timeout))
            }
        }
    }

    public func deviceRemoved(_ removedIdentity: HIDDeviceIdentity) {
        lock.lock()
        let shouldClose = identity == removedIdentity
        lock.unlock()
        if shouldClose { Task { await close() } }
    }

    private static let inputReport: IOHIDReportCallback = { context, result, _, reportType, reportID, report, reportLength in
        guard let context else { return }
        let owner = Unmanaged<NativeHIDTransport>.fromOpaque(context).takeUnretainedValue()
        guard result == kIOReturnSuccess else {
            owner.resolveCurrent(.failure(HIDTransportError.readFailed(result)))
            return
        }
        guard reportType == kIOHIDReportTypeInput, reportID == 0 else {
            owner.resolveCurrent(.failure(HIDTransportError.invalidReportLength(Int(reportLength))))
            return
        }
        owner.receive(report: Array(UnsafeBufferPointer(start: report, count: Int(reportLength))))
    }

    private func receive(report: [UInt8]) {
        guard report.count == ProtocolV1Codec.frameLength else {
            resolveCurrent(.failure(HIDTransportError.invalidReportLength(report.count)))
            return
        }
        resolveCurrent(.success(report))
    }

    private func resolveCurrent(_ result: Result<[UInt8], Error>) {
        lock.lock()
        let pendingTransaction = pending
        pending = nil
        lock.unlock()
        guard let pendingTransaction else { return }
        pendingTransaction.continuation.resume(with: result)
    }

    private func resolve(id: UUID, result: Result<[UInt8], Error>) {
        lock.lock()
        guard let pendingTransaction = pending, pendingTransaction.id == id else { lock.unlock(); return }
        pending = nil
        lock.unlock()
        pendingTransaction.continuation.resume(with: result)
    }
}

public final class StaticHIDDeviceDiscovery: HIDDeviceDiscovering, @unchecked Sendable {
    private let lock = NSLock()
    private var devices: [HIDDeviceIdentity]
    private var removalHandler: (@Sendable (HIDDeviceIdentity) -> Void)?

    public init(devices: [HIDDeviceIdentity] = []) { self.devices = devices }
    public func start() {}
    public func stop() {}
    public func selectedDevice() -> HIDDeviceIdentity? { lock.withLock { devices.sorted().first } }
    public func matchingDevices() -> [HIDDeviceIdentity] { lock.withLock { devices.sorted() } }
    public func setRemovalHandler(_ handler: @escaping @Sendable (HIDDeviceIdentity) -> Void) { lock.withLock { removalHandler = handler } }
    public func setDevices(_ devices: [HIDDeviceIdentity]) { lock.withLock { self.devices = devices } }
    public func remove(_ identity: HIDDeviceIdentity) {
        let handler = lock.withLock { () -> (@Sendable (HIDDeviceIdentity) -> Void)? in
            devices.removeAll { $0 == identity }
            return removalHandler
        }
        handler?(identity)
    }
}
