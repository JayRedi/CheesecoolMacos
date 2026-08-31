import Foundation
import CheeseCoolCore

@main
struct SimulationMain {
    static func main() async throws {
        let report = await DeterministicSimulation.run24Hours()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        FileHandle.standardOutput.write(try encoder.encode(report))
        FileHandle.standardOutput.write(Data("\n".utf8))
        if !report.passed { throw SimulationFailure.failed }
    }
}

private enum SimulationFailure: Error {
    case failed
}
