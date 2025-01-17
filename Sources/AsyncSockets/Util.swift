//
//  Util.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/14/25.
//

import Foundation.NSDateInterval

///
/// Execute an operation in the current task subject to a timeout.
///
/// via  https://forums.swift.org/t/running-an-async-task-with-a-timeout/49733/13
///
/// - Parameters:
///   - seconds: The duration in seconds `operation` is allowed to run before timing out.
///   - operation: The async operation to perform.
/// - Returns: Returns the result of `operation` if it completed in time.
/// - Throws: Throws ``taskTimedOut`` error if the timeout expires before `operation` completes.
///   If `operation` throws an error before the timeout expires, that error is propagated to the caller.
internal func withTimeout<R: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> R
) async rethrows -> R {
    return try await withThrowingTaskGroup(of: R.self) { group in
        let deadline = Date(timeIntervalSinceNow: seconds)

        // Start actual work.
        group.addTask {
            return try await operation()
        }
        // Start timeout child task.
        group.addTask {
            let interval = deadline.timeIntervalSinceNow
            if interval > 0 {
                try await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            }
            try Task.checkCancellation()
            // We’ve reached the timeout.
            throw CancellationError()
        }
        // First finished child task wins, cancel the other task.
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

internal func withCheckedThrowingContinuation<T: Sendable>(timeInterval: TimeInterval, _ body: @Sendable @escaping (CheckedContinuation<T, any Error>) -> Void) async throws -> T {
    try await withTimeout(seconds: timeInterval, operation: { try await withCheckedThrowingContinuation(body) })
}

internal func debugLog(_ message: Any) {
    if let str = message as? String {
        Logger.shared.logDebug(str)
    } else {
        Logger.shared.logDebug(String(describing: message))
    }
}
