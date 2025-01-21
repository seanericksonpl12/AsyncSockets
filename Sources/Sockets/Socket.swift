//
//  Socket.swift
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

import Network
import Foundation

public final class Socket: Sendable {
    
    public struct Options {
        public var allowInsecureConnections: Bool
        public var allowPathMigration: Bool
        public var tcpProtocolOptions: NWProtocolTCP.Options
        public var websocketProtocolOptions: NWProtocolWebSocket.Options
        
        public init(
            allowInsecureConnections: Bool = false,
            allowPathMigration: Bool = true,
            tcpProtocolOptions: NWProtocolTCP.Options = NWProtocolTCP.Options(),
            websocketProtocolOptions: NWProtocolWebSocket.Options = NetworkSocketConnection.defaultSocketOptions
        ) {
            self.allowInsecureConnections = allowInsecureConnections
            self.allowPathMigration = allowPathMigration
            self.tcpProtocolOptions = tcpProtocolOptions
            self.websocketProtocolOptions = websocketProtocolOptions
        }
    }
    
    /// The current state of the socket connection
    public var state: ConnectionState { connection.state }
    
    /// The current closeCode of the socket connection. Defaults to `.noStatusReceived` if not closed.
    public var closeCode: CloseCode { connection.closeCode }
    
    /// The underlying socket connection.
    internal let connection: AsyncConnection

    public init(url: URL, options: Options = Options()) {
        self.connection = NetworkSocketConnection(url: url, options: options)
    }
    
    public init?(host: String, port: Int, options: Options = Options()) {
        guard let connection = NetworkSocketConnection(host: host, port: port, options: options) else { return nil }
        self.connection = connection
    }
    
    /// Start the socket connection.
    ///
    /// Connect may only be called once - subsequence calls will either be ignored or throw an error, depending on the
    /// concurrency context.  To create a new socket connection, you must initialize a new `Socket` object.
    ///
    /// - Throws: An error of type `SocketError` if the socket fails to connect.
    public func connect() async throws {
        try await self.connection.connect()
    }
    
    /// Receive a single message from the socket.
    ///
    /// Receive will wait until it receives a message from the server, or the socket connection is severed.  The message
    /// received will still be parsed by any active `SocketSequence` as well.
    ///
    /// - Throws: An error of type `SocketError` if the socket encounters an error while listening.
    ///
    /// - Returns: A `SocketMessage` with either the String or Data received from the socket connection.
    public func receive() async throws -> SocketMessage {
        try await self.connection.receive()
    }
    
    public func receive<T: Decodable>(type: T.Type = T.self) async throws -> T {
        try await self.connection.receive(decodingType: type)
    }

    /// An AsyncSequence of all messages received by the websocket, of type `SocketMessage`.
    ///
    /// Example:
    ///
    ///     for try await message in socket.messages() {
    ///         switch message {
    ///         case .string(let message):
    ///             print(message)
    ///         case .data(let data):
    ///             // handle Data obj
    ///             break
    ///         }
    ///     }
    ///
    public func messages() -> AsyncSocketSequence<SocketMessage> {
        return connection.buildSequence()
    }
    
    /// An AsyncSequence of all messages received by the websocket, of type `SocketMessage`.
    ///
    /// This sequence
    /// Example:
    ///
    ///     for try await message in socket.messages {
    ///         print(message)
    ///     }
    public func messages<T: Decodable & Sendable>(ofType type: T.Type) -> AsyncSocketSequence<T> {
        return connection.buildSequence()
    }
    
    /// Close the socket connection gracefully and terminate all streams.
    ///
    /// Calling close will send a close segment through the socket - this means close is asynchronous.  However, it is safe to run
    /// in a synchronous environment as no additional data besides FIN and ACK segments _should_ be exchanged after it is
    /// called.
    ///
    /// If you prefer to wait for the server response, call the `async` version of `close(withCode: CloseCode?)`
    ///
    /// - Parameter withCode: The close code to send the server, uses `.goingAway` if nil.
    public func close(withCode closeCode: CloseCode? = nil) {
        self.connection.close(withCode: closeCode)
    }
    
    /// Close the socket connection gracefully and terminate all streams, waiting until the connection is fully dismantled before
    /// returning.
    ///
    /// This function will send proper close segments through the socket, and wait until the correct FIN and ACK segments are
    /// received by the server.
    ///
    /// If you prefer not to wait for the server response, it's perfectly safe to call the non-`async` version of
    /// `close(withCode: CloseCode?)`
    ///
    /// - Parameter withCode: The close code to send the server, uses `.goingAway` if nil.
    public func close(withCode closeCode: CloseCode? = nil) async throws {
        do {
            try await self.connection.close(withCode: closeCode)
        } catch {
            debugLog(error)
            throw error
        }
    }
    
    /// Send a string through the websocket.
    ///
    /// This function will return once the data is either successfully processed by the connection or fails to send - not necessarily
    /// once it is sent over the connection.
    ///
    /// From the `Network` module:
    /// *Note that this does not guarantee that the data was sent out over the network, or acknowledge, but only that it has been
    /// consumed by the protocol stack*
    ///
    /// - Parameter text: The string to send over the connection
    ///
    /// - Throws: An error of type `SocketError` if the connection is not ready, or the connection fails to process the data
    public func send(_ text: String) async throws {
        do {
            try await self.connection.send(text)
        } catch {
            debugLog(error)
            throw error
        }
    }
    
    /// Sends data through the websocket.
    ///
    /// This function will return once the data is either successfully processed by the connection or fails to send - not necessarily
    /// once it is sent over the connection.
    ///
    /// From the `Network` module:
    /// *Note that this does not guarantee that the data was sent out over the network, or acknowledge, but only that it has been
    /// consumed by the protocol stack*
    ///
    /// - Parameter data: The data to send over the connection
    ///
    /// - Throws: An error of type `SocketError` if the connection is not ready, or the connection fails to process the data
    public func send(_ data: Data) async throws {
        do {
            try await self.connection.send(data)
        } catch {
            debugLog(error)
            throw error
        }
    }
    
    /// Sends a ping through the websocket.
    ///
    /// This function will return once the data is either successfully processed by the connection or fails to send - not necessarily
    /// once it is sent over the connection.
    ///
    /// From the `Network` module:
    /// *Note that this does not guarantee that the data was sent out over the network, or acknowledge, but only that it has been
    /// consumed by the protocol stack*
    ///
    /// - Throws: An error of type `SocketError` if the connection is not ready, or the connection fails to process the data
    public func ping() async throws {
        do {
        try await self.connection.ping()
        } catch {
            debugLog(error)
            throw error
        }
    }
}

extension Socket {
    
    /// Sets a block of code to run when the socket state changes.
    public func onStateChange(_ action: @Sendable @escaping (ConnectionState) -> Void) {
        self.connection.onStateChange(action)
    }
    
    /// Sets a block of code to run when the socket detects a better path, signalling a refresh is suggested.
    public func onShouldRefresh(_ action: @Sendable @escaping () -> Void) {
        self.connection.onShouldRefresh(action)
    }
}
