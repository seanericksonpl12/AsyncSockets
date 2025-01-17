//
//  Log.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/16/25.
//

import OSLog

struct Logger {
    
    static let shared = Logger()
    private let osLog: OSLog

    private init() {
        osLog = OSLog(subsystem: Bundle.main.bundleIdentifier ?? "SDK.DefaultSubsystem", category: "SDKLogging")
    }

    func logVerbose(_ message: @autoclosure () -> String) {
        os_log("%{public}@", log: osLog, type: .default, message())
    }

    func logInfo(_ message: @autoclosure () -> String) {
        os_log("%{public}@", log: osLog, type: .info, message())
    }

    func logDebug(_ message: @autoclosure () -> String) {
        os_log("%{public}@", log: osLog, type: .debug, message())
    }

    func logFault(_ message: @autoclosure () -> String) {
        os_log("%{public}@", log: osLog, type: .fault, message())
    }

    func logError(_ message: @autoclosure () -> String) {
        os_log("%{public}@", log: osLog, type: .error, message())
    }

}
