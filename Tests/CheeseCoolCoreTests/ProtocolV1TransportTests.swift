import XCTest
@testable import CheeseCoolCore

final class ProtocolV1TransportTests: XCTestCase {
    func testPingRequestMatchesFrozenFrameLayout() throws {
        let frame = try ProtocolV1Codec.encode(.init(command: .ping, sequence: 0x2A))
        XCTAssertEqual(frame.count, 64)
        XCTAssertEqual(Array(frame.prefix(5)), [1, 0x01, 0x2A, 0, 0])
        XCTAssertEqual(frame[63], ProtocolV1Codec.checksum(frame[0...62]))
    }

    func testSetModeAndExactDutyVectors() throws {
        let hostMode = try ProtocolV1Codec.encode(.init(command: .setMode, sequence: 1, payload: [0]))
        let maxMode = try ProtocolV1Codec.encode(.init(command: .setMode, sequence: 2, payload: [1]))
        XCTAssertEqual(Array(hostMode.prefix(5)), [1, 0x0A, 1, 1, 0])
        XCTAssertEqual(Array(maxMode.prefix(5)), [1, 0x0A, 2, 1, 1])
        for duty: UInt8 in [0, 50, 100] {
            let frame = try ProtocolV1Codec.encode(.init(command: .setDuty, sequence: duty, payload: [duty]))
            XCTAssertEqual(Array(frame.prefix(5)), [1, 0x0B, duty, 1, duty])
        }
    }

    func testResponseRejectsCorruptionAndMismatches() throws {
        let request = ProtocolV1Request(command: .ping, sequence: 3)
        var response = try ProtocolV1Codec.encodeResponse(command: .ping, sequence: 3)
        response[63] ^= 0xFF
        XCTAssertThrowsError(try ProtocolV1Codec.decodeResponse(response, expecting: request)) {
            XCTAssertEqual($0 as? ProtocolV1Error, .checksumMismatch(expected: ProtocolV1Codec.checksum(response[0...62]), actual: response[63]))
        }
        response = try ProtocolV1Codec.encodeResponse(command: .getStatus, sequence: 3)
        XCTAssertThrowsError(try ProtocolV1Codec.decodeResponse(response, expecting: request))
        response = try ProtocolV1Codec.encodeResponse(command: .ping, sequence: 4)
        XCTAssertThrowsError(try ProtocolV1Codec.decodeResponse(response, expecting: request))
        response = try ProtocolV1Codec.encodeResponse(command: .ping, sequence: 3)
        response[0] = 2; response[63] = ProtocolV1Codec.checksum(response[0...62])
        XCTAssertThrowsError(try ProtocolV1Codec.decodeResponse(response, expecting: request))
    }

    func testCodecRejectsOversizedAndTruncatedFrames() throws {
        XCTAssertThrowsError(try ProtocolV1Codec.encode(.init(command: .ping, sequence: 0, payload: Array(repeating: 0, count: 60))))
        XCTAssertThrowsError(try ProtocolV1Codec.decodeRequest([UInt8](repeating: 0, count: 63)))
    }

    func testGetStatusDecodesLittleEndianPayload() throws {
        let request = ProtocolV1Request(command: .getStatus, sequence: 7)
        let payload: [UInt8] = [0, 50, 49, 0xD2, 0x04, 0, 0, 1, 0, 1, 0x78, 0x56, 0x34, 0x12, 1, 2, 3]
        let frame = try ProtocolV1Codec.encodeResponse(command: .getStatus, sequence: 7, payload: payload)
        let status = try ProtocolV1Codec.decodeDeviceStatus(try ProtocolV1Codec.decodeResponse(frame, expecting: request))
        XCTAssertEqual(status.mode, .hostControlled)
        XCTAssertEqual(status.targetDuty, 50)
        XCTAssertEqual(status.actualDuty, 49)
        XCTAssertEqual(status.rpm, 1_234)
        XCTAssertEqual(status.uptime, 0x12345678)
        XCTAssertTrue(status.powerFault)
        XCTAssertEqual(status.firmwareVersion.value, "1.2.3")
    }

    func testGetStatusRejectsInvalidFlagsAndPayload() throws {
        let request = ProtocolV1Request(command: .getStatus, sequence: 1)
        let short = try ProtocolV1Codec.encodeResponse(command: .getStatus, sequence: 1, payload: [0])
        XCTAssertThrowsError(try ProtocolV1Codec.decodeDeviceStatus(ProtocolV1Codec.decodeResponse(short, expecting: request)))
        var payload = [UInt8](repeating: 0, count: 17)
        payload[7] = 2
        let invalidFlag = try ProtocolV1Codec.encodeResponse(command: .getStatus, sequence: 1, payload: payload)
        XCTAssertThrowsError(try ProtocolV1Codec.decodeDeviceStatus(ProtocolV1Codec.decodeResponse(invalidFlag, expecting: request)))
    }

    func testSequenceAllocatorWrapsDeterministically() async {
        let allocator = ProtocolV1SequenceAllocator(initialSequence: 254)
        let first = await allocator.allocate()
        let second = await allocator.allocate()
        let third = await allocator.allocate()
        XCTAssertEqual(first, 254)
        XCTAssertEqual(second, 255)
        XCTAssertEqual(third, 0)
    }

    func testDeviceSelectionIsStableAndExcludesDFUIdentity() {
        let later = HIDDeviceIdentity(locationID: 2, registryID: 2)
        let earlier = HIDDeviceIdentity(locationID: 1, registryID: 3)
        let discovery = StaticHIDDeviceDiscovery(devices: [later, earlier])
        XCTAssertEqual(discovery.selectedDevice(), earlier)
        let dfu = HIDDeviceIdentity(productID: HIDDeviceIdentity.goldenDFUProductID, registryID: 4)
        XCTAssertNotEqual(dfu.productID, HIDDeviceIdentity.cheeseCoolProductID)
    }

    func testHIDHostDeviceUsesPingStatusAndExactCommands() async throws {
        let identity = HIDDeviceIdentity(registryID: 42)
        let discovery = StaticHIDDeviceDiscovery(devices: [identity])
        let transport = MockHIDTransport(identity: identity)
        let device = HIDHostDevice(discovery: discovery, transport: transport)
        try await device.connect()
        _ = try await device.getStatus()
        try await device.setHostControlled()
        try await device.setDuty(0)
        try await device.setDuty(50)
        try await device.setMax()
        let requests = await transport.requestFrames.map { try? ProtocolV1Codec.decodeRequest($0) }
        XCTAssertEqual(requests.compactMap { $0?.command }, [.ping, .getStatus, .setMode, .setDuty, .setDuty, .setMode])
        XCTAssertEqual(requests[3]?.payload, [0])
        XCTAssertEqual(requests[4]?.payload, [50])
        XCTAssertEqual(requests[5]?.payload, [1])
        let diagnostics = await device.diagnostics()
        XCTAssertTrue(diagnostics.connected)
        XCTAssertEqual(diagnostics.lastCommand, .setMode)
    }

    func testHIDHostDeviceRejectsTimeoutMalformedAndDisconnect() async throws {
        let identity = HIDDeviceIdentity(registryID: 43)
        let discovery = StaticHIDDeviceDiscovery(devices: [identity])
        let transport = MockHIDTransport(identity: identity)
        let device = HIDHostDevice(discovery: discovery, transport: transport)
        try await device.connect()
        await transport.setBehavior(.timeout)
        await assertAsyncThrows { try await device.getStatus() }
        await transport.setBehavior(.normal)
        try await device.connect()
        await transport.setBehavior(.badChecksum)
        await assertAsyncThrows { try await device.getStatus() }
        await transport.setBehavior(.normal)
        try await device.connect()
        await transport.setBehavior(.disconnected)
        await assertAsyncThrows { try await device.getStatus() }
    }

    func testHIDRemovalClearsConnection() async throws {
        let identity = HIDDeviceIdentity(registryID: 44)
        let discovery = StaticHIDDeviceDiscovery(devices: [identity])
        let transport = MockHIDTransport(identity: identity)
        let device = HIDHostDevice(discovery: discovery, transport: transport)
        try await device.connect()
        discovery.remove(identity)
        try? await Task.sleep(for: .milliseconds(20))
        let connected = await device.isConnected
        XCTAssertFalse(connected)
    }

    func testControlSessionUsesHIDHostDeviceAndStopsTrafficWhenTemperatureUnavailable() async throws {
        let clock = ManualClock()
        let source = FakeSensorProvider(temperature: 60)
        let identity = HIDDeviceIdentity(registryID: 45)
        let discovery = StaticHIDDeviceDiscovery(devices: [identity])
        let transport = MockHIDTransport(identity: identity)
        let device = HIDHostDevice(discovery: discovery, transport: transport)
        let session = ControlSession(temperatureSource: source, device: device, clock: clock)
        _ = await session.tick()
        let beforeLoss = await transport.requestFrames.count
        await source.setUnavailable()
        try clock.advance(by: 4)
        _ = await session.tick()
        for _ in 0..<40 { try clock.advance(by: 1); _ = await session.tick() }
        let controlState = await session.currentControlState
        let requestCount = await transport.requestFrames.count
        XCTAssertEqual(controlState, .temperatureUnavailable)
        XCTAssertEqual(requestCount, beforeLoss)
    }

    func testControlSessionRecoversMockHIDAfterPowerFault() async throws {
        let clock = ManualClock()
        let source = FakeSensorProvider(temperature: 55)
        let identity = HIDDeviceIdentity(registryID: 46)
        let discovery = StaticHIDDeviceDiscovery(devices: [identity])
        let transport = MockHIDTransport(identity: identity)
        let device = HIDHostDevice(discovery: discovery, transport: transport)
        let session = ControlSession(temperatureSource: source, device: device, clock: clock)
        _ = await session.tick()
        await transport.setPowerFault(true)
        try clock.advance(by: 5)
        _ = await session.tick()
        let faultState = await session.currentControlState
        XCTAssertEqual(faultState, .powerFault)
        await transport.setPowerFault(false)
        await session.acknowledgePowerFault()
        _ = await session.tick()
        let recoveredState = await session.currentControlState
        XCTAssertEqual(recoveredState, .autoActive)
    }
}

private extension XCTestCase {
    func assertAsyncThrows<T>(_ operation: () async throws -> T) async {
        do {
            _ = try await operation()
            XCTFail("预期抛出错误")
        } catch {}
    }
}
