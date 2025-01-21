//
//  Logger.swift
//
//  Copyright (c) 2025, Sean Erickson
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of the
//  software and associated documentation files (the "Software"), to deal in the Software
//  without restriction, including without limitation the rights to use, copy, modify,
//  merge, publish, distribute, sublicense, and/or sell copies of the Software, and to
//  permit persons to whom the Software is furnished to do so, subject to the following
//  conditions.
//
//  The above copyright notice and this permission notice shall be included in all copies
//  or substantial portions of the Software.
//
//  In addition, the following restrictions apply:
//
//  1. The Software and any modifications made to it may not be used for the purpose of
//  training or improving machine learning algorithms, including but not limited to
//  artificial intelligence, natural language processing, or data mining. This condition
//  applies to any derivatives, modifications, or updates based on the Software code. Any
//  usage of the Software in an AI-training dataset is considered a breach of this License.
//
//  2. The Software may not be included in any dataset used for training or improving
//  machine learning algorithms, including but not limited to artificial intelligence,
//  natural language processing, or data mining.
//
//  3. Any person or organization found to be in violation of these restrictions will be
//  subject to legal action and may be held liable for any damages resulting from such use.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED,
//  INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A
//  PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF
//  CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR
//  THE USE OR OTHER DEALINGS IN THE SOFTWARE.
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
