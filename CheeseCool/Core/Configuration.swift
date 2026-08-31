import Foundation

public struct AutoCurvePoint: Codable, Equatable, Sendable {
    public let temperatureCelsius: Double
    public let duty: Double

    public init(temperatureCelsius: Double, duty: Double) {
        self.temperatureCelsius = temperatureCelsius
        self.duty = duty
    }
}

public enum CriticalBehavior: String, Codable, Sendable {
    case immediate100 = "IMMEDIATE_100"
}

public struct ReconnectPolicy: Codable, Equatable, Sendable {
    public let maxAttempts: Int
    public let initialDelay: TimeInterval
    public let backoffMultiplier: Double
    public let maxDelay: TimeInterval

    public init(
        maxAttempts: Int = 3,
        initialDelay: TimeInterval = 2,
        backoffMultiplier: Double = 2,
        maxDelay: TimeInterval = 30
    ) {
        self.maxAttempts = maxAttempts
        self.initialDelay = initialDelay
        self.backoffMultiplier = backoffMultiplier
        self.maxDelay = maxDelay
    }
}

public struct MenuBarPreferences: Codable, Equatable, Sendable {
    public var mainIconPreferredVisible: Bool
    public var visibleMetrics: [MetricIdentifier]
    public var metricOrder: [MetricIdentifier]

    public init(
        mainIconPreferredVisible: Bool = true,
        visibleMetrics: [MetricIdentifier] = [.fanRPM],
        metricOrder: [MetricIdentifier] = MetricIdentifier.allCases
    ) {
        self.mainIconPreferredVisible = mainIconPreferredVisible
        self.visibleMetrics = visibleMetrics
        self.metricOrder = metricOrder
    }
}

public enum ConfigurationError: Error, Equatable, LocalizedError {
    case unsupportedVersion(Int)
    case invalidValue(String)
    case fieldMismatch(path: String, missing: [String], extra: [String])
    case invalidRoot

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Unsupported configuration version: \(version)"
        case .invalidValue(let field):
            return "Invalid configuration value: \(field)"
        case .fieldMismatch(let path, let missing, let extra):
            return "Configuration fields mismatch at \(path); missing=\(missing), extra=\(extra)"
        case .invalidRoot:
            return "Configuration root must be a JSON object"
        }
    }
}

public struct Configuration: Codable, Equatable, Sendable {
    public let version: Int
    public var operatingMode: OperatingMode
    public var manualDuty: Int
    public var autoCurve: [AutoCurvePoint]
    public var deadband: Double
    public var rampUpPerSecond: Double
    public var rampDownPerSecond: Double
    public var criticalBehavior: CriticalBehavior
    public var temperatureGrace: TimeInterval
    public var temperatureStaleAfter: TimeInterval
    public var keepaliveInterval: TimeInterval
    public var controlTickInterval: TimeInterval
    public var reconnectPolicy: ReconnectPolicy
    public let physicalFanOffSupported: Bool
    public var menuBar: MenuBarPreferences
    public var refreshInterval: TimeInterval
    public var launchAtLogin: Bool
    public var restorePreviousMode: Bool

    public init(
        version: Int = 1,
        operatingMode: OperatingMode = .auto,
        manualDuty: Int = 50,
        autoCurve: [AutoCurvePoint] = [
            .init(temperatureCelsius: 40, duty: 0),
            .init(temperatureCelsius: 50, duty: 25),
            .init(temperatureCelsius: 60, duty: 40),
            .init(temperatureCelsius: 70, duty: 60),
            .init(temperatureCelsius: 80, duty: 80),
            .init(temperatureCelsius: 90, duty: 100)
        ],
        deadband: Double = 2,
        rampUpPerSecond: Double = 20,
        rampDownPerSecond: Double = 8,
        criticalBehavior: CriticalBehavior = .immediate100,
        temperatureGrace: TimeInterval = 3,
        temperatureStaleAfter: TimeInterval = 5,
        keepaliveInterval: TimeInterval = 5,
        controlTickInterval: TimeInterval = 1,
        reconnectPolicy: ReconnectPolicy = .init(),
        physicalFanOffSupported: Bool = false,
        menuBar: MenuBarPreferences = .init(),
        refreshInterval: TimeInterval = 1,
        launchAtLogin: Bool = true,
        restorePreviousMode: Bool = true
    ) throws {
        self.version = version
        self.operatingMode = operatingMode
        self.manualDuty = manualDuty
        self.autoCurve = autoCurve
        self.deadband = deadband
        self.rampUpPerSecond = rampUpPerSecond
        self.rampDownPerSecond = rampDownPerSecond
        self.criticalBehavior = criticalBehavior
        self.temperatureGrace = temperatureGrace
        self.temperatureStaleAfter = temperatureStaleAfter
        self.keepaliveInterval = keepaliveInterval
        self.controlTickInterval = controlTickInterval
        self.reconnectPolicy = reconnectPolicy
        self.physicalFanOffSupported = physicalFanOffSupported
        self.menuBar = menuBar
        self.refreshInterval = refreshInterval
        self.launchAtLogin = launchAtLogin
        self.restorePreviousMode = restorePreviousMode
        try validate()
    }

    public static let defaults: Configuration = {
        do { return try Configuration() }
        catch { preconditionFailure("Invalid built-in configuration: \(error)") }
    }()

    public func validate() throws {
        guard version == 1 else { throw ConfigurationError.unsupportedVersion(version) }
        guard (0...100).contains(manualDuty) else {
            throw ConfigurationError.invalidValue("manualDuty")
        }
        guard autoCurve.count >= 2 else {
            throw ConfigurationError.invalidValue("autoCurve")
        }
        var previousTemperature = -Double.infinity
        for point in autoCurve {
            guard point.temperatureCelsius.isFinite,
                  point.duty.isFinite,
                  point.temperatureCelsius > previousTemperature,
                  (0...100).contains(point.duty) else {
                throw ConfigurationError.invalidValue("autoCurve")
            }
            previousTemperature = point.temperatureCelsius
        }
        let finiteValues = [
            deadband, rampUpPerSecond, rampDownPerSecond, temperatureGrace,
            temperatureStaleAfter, keepaliveInterval, controlTickInterval,
            refreshInterval, reconnectPolicy.initialDelay,
            reconnectPolicy.backoffMultiplier, reconnectPolicy.maxDelay
        ]
        guard finiteValues.allSatisfy(\.isFinite) else {
            throw ConfigurationError.invalidValue("non-finite number")
        }
        guard deadband >= 0,
              rampUpPerSecond > 0,
              rampDownPerSecond > 0,
              temperatureGrace >= 0,
              temperatureStaleAfter > 0,
              keepaliveInterval > 0,
              controlTickInterval > 0,
              refreshInterval > 0 else {
            throw ConfigurationError.invalidValue("control timing/rate")
        }
        guard reconnectPolicy.maxAttempts >= 0,
              reconnectPolicy.initialDelay >= 0,
              reconnectPolicy.maxDelay >= 0,
              reconnectPolicy.initialDelay <= reconnectPolicy.maxDelay,
              reconnectPolicy.backoffMultiplier >= 1 else {
            throw ConfigurationError.invalidValue("reconnectPolicy")
        }
        guard physicalFanOffSupported == false else {
            throw ConfigurationError.invalidValue("physicalFanOffSupported")
        }
        guard Set(menuBar.metricOrder) == Set(MetricIdentifier.allCases),
              menuBar.metricOrder.count == MetricIdentifier.allCases.count,
              Set(menuBar.visibleMetrics).count == menuBar.visibleMetrics.count else {
            throw ConfigurationError.invalidValue("menuBar metrics")
        }
    }

    public func encoded(prettyPrinted: Bool = true) throws -> Data {
        try validate()
        let encoder = JSONEncoder()
        encoder.outputFormatting = prettyPrinted ? [.prettyPrinted, .sortedKeys] : [.sortedKeys]
        return try encoder.encode(self)
    }

    public static func decodeStrict(from data: Data) throws -> Configuration {
        let json = try JSONSerialization.jsonObject(with: data, options: [])
        guard let root = json as? [String: Any] else { throw ConfigurationError.invalidRoot }
        try requireExactKeys(
            root,
            expected: [
                "version", "operatingMode", "manualDuty", "autoCurve", "deadband",
                "rampUpPerSecond", "rampDownPerSecond", "criticalBehavior",
                "temperatureGrace", "temperatureStaleAfter", "keepaliveInterval",
                "controlTickInterval", "reconnectPolicy", "physicalFanOffSupported",
                "menuBar", "refreshInterval", "launchAtLogin", "restorePreviousMode"
            ],
            path: "$"
        )
        guard let reconnect = root["reconnectPolicy"] as? [String: Any] else {
            throw ConfigurationError.invalidValue("reconnectPolicy")
        }
        try requireExactKeys(
            reconnect,
            expected: ["maxAttempts", "initialDelay", "backoffMultiplier", "maxDelay"],
            path: "$.reconnectPolicy"
        )
        guard let menuBar = root["menuBar"] as? [String: Any] else {
            throw ConfigurationError.invalidValue("menuBar")
        }
        try requireExactKeys(
            menuBar,
            expected: ["mainIconPreferredVisible", "visibleMetrics", "metricOrder"],
            path: "$.menuBar"
        )
        guard let curve = root["autoCurve"] as? [[String: Any]] else {
            throw ConfigurationError.invalidValue("autoCurve")
        }
        for (index, point) in curve.enumerated() {
            try requireExactKeys(
                point,
                expected: ["temperatureCelsius", "duty"],
                path: "$.autoCurve[\(index)]"
            )
        }
        let configuration = try JSONDecoder().decode(Configuration.self, from: data)
        try configuration.validate()
        return configuration
    }

    private static func requireExactKeys(
        _ object: [String: Any],
        expected: Set<String>,
        path: String
    ) throws {
        let actual = Set(object.keys)
        guard actual == expected else {
            throw ConfigurationError.fieldMismatch(
                path: path,
                missing: Array(expected.subtracting(actual)).sorted(),
                extra: Array(actual.subtracting(expected)).sorted()
            )
        }
    }
}

public struct ConfigurationLoadResult: Sendable {
    public let configuration: Configuration
    public let usedDefaults: Bool
    public let error: String?
}
