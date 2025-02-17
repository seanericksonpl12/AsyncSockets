//
//  AsyncConnection.swift
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

import Foundation

/// A state representing the state of a SocketConnection
public enum ConnectionState: Sendable, Decodable {
    case connecting
    case connected
    case disconnected
}

protocol AsyncConnection: Sendable, AnyObject {
    var closeCode: CloseCode { get }
    var state: ConnectionState { get }
    
    init(url: URL, options: Socket.Options)
    init(host: String, port: UInt16, options: Socket.Options)
    
    func connect() async throws
    func close(withCode code: CloseCode?) async throws
    func close(withCode code: CloseCode?)
    func forceClose()
    func receive() async throws -> SocketMessage
    func receive<T: Decodable>(decodingType: T.Type) async throws -> T
    func receiveAndPublish()
    func send(_ text: String) async throws
    func send(_ data: Data) async throws
    func ping() async throws
    func pong() async throws
    func buildMessageSequence() -> AsyncSocketSequence
    func buildEventSequence() -> AsyncEventSequence
}
