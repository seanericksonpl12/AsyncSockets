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
    
    /// Additional Options for a Socket.
    public struct Options {
        
        /// Allow the socket to connect with using TLS.  If true, TLS is disabled.  Default is `false`.
        public var allowInsecureConnections: Bool
        
        /// Additional TCP Protocol options, from the `Network` framework.
        public var tcpProtocolOptions: NWProtocolTCP.Options
        
        /// Additional WebSocket Protocol options, from the `Network` framework.
        public var websocketProtocolOptions: NWProtocolWebSocket.Options
        
        /// Create a new Options object with the given options.
        public init(
            allowInsecureConnections: Bool = false,
            tcpProtocolOptions: NWProtocolTCP.Options = NWProtocolTCP.Options(),
            websocketProtocolOptions: NWProtocolWebSocket.Options = NetworkSocketConnection.defaultSocketOptions
        ) {
            self.allowInsecureConnections = allowInsecureConnections
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

    /// Creates a new `Socket` instance with the provided url and options.
    ///
    /// - Parameters:
    ///    - url: The url of the socket connection.
    ///    - options: Additional socket options to use, if provided.
    public init(url: URL, options: Options = Options()) {
        self.connection = NetworkSocketConnection(url: url, options: options)
    }
    
    /// Creates a new `Socket` instance with the provided host, port and options
    /// - Parameters:
    ///    - host: The host of the socket connection
    ///    - port: The port of the socket connection.
    ///    - options: Additional socket options to use, if provided.
    public init(host: String, port: UInt16, options: Options = Options()) {
        self.connection = NetworkSocketConnection(host: host, port: port, options: options)
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
    
    /// Receive a single message from the socket of a given decodable type.
    ///
    /// Receive will wait until it receives a message from the server that can be decoded into the provided type, or the
    /// socket connection is severed.  The message received will still be parsed by any active `SocketSequence`
    /// as well.
    ///
    /// This function will only return objects that are successfully decoded as the given type - meaning that if a message
    /// fails to be decoded as the given type, **No Error Will Be Thrown, and Receive Will Continue Waiting**. If
    /// you want receive to return the first message received, decoded or not, you can use the other `receive()` func
    /// and manually decode socket messages.
    ///
    /// - Parameter type: The type to decode the received message to.
    ///
    /// - Throws: An error of type `SocketError` if the socket encounters an error while listening.
    ///
    /// - Returns: An object returned from the socket, of the type provided.
    public func receive<T: Decodable>(type: T.Type = T.self) async throws -> T {
        try await self.connection.receive(decodingType: type)
    }

    /// An AsyncSequence of all messages received by the websocket.
    ///
    /// This sequence will return all messages received by the websocket as type `SocketMessage`.  If you
    /// want to listen for only messages of a certain `Decodable` type, try the `messages(ofType:)`
    /// function.
    ///
    /// - Note: Pings and Pongs will not be received by this sequence.  They are considered a `SocketEvent`
    /// and can be streamed from `AsyncEventSequence`, returned by the `events()` function.
    ///
    /// Example:
    ///
    ///     for try await message in socket.messages(ofType: ExpectedResponse.self) {
    ///         switch message {
    ///         case .string(let str):
    ///             print("received type string: \(str)")
    ///         case .data(let data):
    ///             print("received type data of size \(data)")
    ///         }
    ///     }
    ///
    /// - Returns: An AsyncSocketSequence that streams `SocketMessage`s.
    public func messages() -> AsyncSocketSequence<SocketMessage> {
        return connection.buildMessageSequence()
    }
    
    /// A convenience AsyncSequence of all messages received by the websocket, of a given `Decodable` type.
    ///
    /// This sequence will only return objects that are successfully decoded as the given type - meaning that if a
    /// message fails to be decoded as the given type, **No Error Will Be Thrown, and No Message Will be
    /// Delivered**. If you need to receive all messages or want to know when a message fails decoding, you
    /// must use the `messages()` func and manually decode socket messages.
    ///
    /// Example:
    ///
    ///     struct ExpectedResponse: Decodable {
    ///         let value: Int
    ///         let name: String
    ///     }
    ///
    ///     for try await response in socket.messages(ofType: ExpectedResponse.self) {
    ///         print("received \(response.name) of value \(response.value)")
    ///     }
    ///
    /// - Parameter ofType: The `Decodable` & `Sendable` type that AsyncSockets will use to decode
    /// messages.
    ///
    /// - Returns: An AsyncSocketSequence that streams the given object type provided.
    public func messages<T: Decodable & Sendable>(ofType type: T.Type) -> AsyncSocketSequence<T> {
        return connection.buildMessageSequence()
    }
    
    /// An AsyncSequence of all events that occur on the websocket.
    ///
    /// This sequence will not throw or end until either `.end()` is called or the sequence is deallocated.
    ///
    /// - Warning: Pings and Pongs will not be published to this stream until there is also an active message
    /// stream, or an active call to `receive()`.  Since pings and pongs are just data parsed by
    /// `NWConnection` like any other message, if you are not listening to any messages, no pings or pongs
    /// will be parsed.
    ///
    /// Example:
    ///
    ///     for try await response in socket.messages(ofType: ExpectedResponse.self) {
    ///         print("received \(response.name) of value \(response.value)")
    ///     }
    ///
    /// - Parameter ofType: The `Decodable` & `Sendable` type that AsyncSockets will use to decode
    /// messages.
    ///
    /// - Returns: An AsyncSocketSequence that streams the given object type provided.
    public func events() -> AsyncEventSequence {
        return connection.buildEventSequence()
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
        try await self.connection.close(withCode: closeCode)
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
        try await self.connection.send(text)
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
        try await self.connection.send(data)
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
        try await self.connection.ping()
    }
    
    /// Sends a pong through the websocket.
    ///
    /// This function will return once the data is either successfully processed by the connection or fails to send - not necessarily
    /// once it is sent over the connection.
    ///
    /// From the `Network` module:
    /// *Note that this does not guarantee that the data was sent out over the network, or acknowledge, but only that it has been
    /// consumed by the protocol stack*
    ///
    /// - Note: Unless specified in `Options`, this socket will auto-reply to any pings with a pong, and calling this function
    /// would not be necessary.
    ///
    /// - Throws: An error of type `SocketError` if the connection is not ready, or the connection fails to process the data
    public func pong() async throws {
        try await self.connection.pong()
    }
}
