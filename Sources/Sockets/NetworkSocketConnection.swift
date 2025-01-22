//
//  NetworkSocketConnection.swift
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
import Network

public final class NetworkSocketConnection: AsyncConnection {
            
    /// The current close code of the connection.
    public var closeCode: CloseCode { _closeCode.value }
    
    /// The current state of this SocketConnection.
    public var state: ConnectionState { _state.value }
    
    /// Whether or not this connection is viable
    public var isViableConnection: Bool? { _isViableConnection.value }
    
    /// The current path of the connection, nil if not connected
    public var currentPath: NWPath? { _currentPath.value }
    
    /// Storage for active receive tasks to avoid leaks
    private let receiveContinuations: Lock<[UUID: CheckedContinuation<SocketMessage, Error>]> = Lock([:])
    
    /// The continuation for connecting, resumed successfully when the connection state is ready.
    private let connectionContinuation: Lock<CheckedContinuation<Void, Error>?> = Lock(nil)
    
    /// The continuation for disconnecting, fulfilled successfully when the connection receives proper FIN/ACK messaging from the server
    private let disconnectionContinuation: Lock<CheckedContinuation<Void, Error>?> = Lock(nil)
    
    /// The underlying `NWConnection`
    private let connection: NWConnection
    
    /// The connection endpoing
    private let endpoint: NWEndpoint
    
    /// The connection parameters
    private let parameters: NWParameters
    
    /// Allow migration when a better path is detected - connection will immediately migrate to a better path when detected if `true`, else ignore the better path.
    private let allowPathMigration: Bool
    
    /// Dispatch queue to connect to the connection on.
    private let queue = DispatchQueue(label: "NWSocketQueue")
    
    /// `closeCode` mutable threadsafe storage
    private let _closeCode: Lock<CloseCode> = Lock(CloseCode.protocolCode(.noStatusReceived))
    
    /// `state` mutable threadsafe storage
    private let _state: Lock<ConnectionState> = Lock(.disconnected)
    
    /// `isViableConnection` mutable threadsafe storage
    private let _isViableConnection: Lock<Bool?> = Lock(nil)
    
    /// `currentPath` mutable threadsafe storage
    private let _currentPath: Lock<NWPath?>
    
    /// Action to run when the state updates
    private let _onStateChange: Lock<@Sendable (ConnectionState) -> Void> = Lock({ _ in})
    
    /// Action to run when the state updates
    private let _onShouldRefresh: Lock<@Sendable () -> Void> = Lock({})
    
    /// A publisher for distributing received messages to all subscribers.  Allows any number of `AsyncSocketSequences` to run on the same connection.
    private let publisher: Publisher<(connection: AsyncConnection, result: Result<SocketMessage, Error>)> = Publisher()
    
    /// JSONDecoder for decoding socket messages
    private let decoder = JSONDecoder()
    
    /// Default options for the WebSocketProtocol:
    ///     - `autoReplyPing: on`
    public static let defaultSocketOptions: WebSocketProtocolOptions = {
        let options = WebSocketProtocolOptions()
        options.autoReplyPing = true
        return options
    }()
    
    /// Initialize a new `SocketConnection` with the given URL and options.
    ///
    ///    - Parameters:
    ///      - url: The url to use to create the connection
    ///      - options: Additional options for the socket connection
    ///
    ///    - Returns: A new `SocketConnection`
    convenience init(url: URL, options: Socket.Options) {
        self.init(endpoint: NWEndpoint.url(url), options: options)
    }
    
    /// Initialize a new `SocketConnection` with the given host, port and options.  Returns nil if an invalid port is provided.
    ///
    ///    - Parameters:
    ///      - host: The host string for the connection
    ///      - port: The port for the connection
    ///      - options: Additional options for the socket connection
    ///
    ///    - Returns: A new `SocketConnection` if the port is valid, else `nil`
    convenience init?(host: String, port: Int, options: Socket.Options) {
        guard let port = NWEndpoint.Port("\(port)") else { return nil }
        self.init(endpoint: NWEndpoint.hostPort(host: .init(host), port: port), options: options)
    }
    
    /// Initialize a new `SocketConnection` with the given endpoing and options.
    ///
    ///    - Parameters:
    ///      - endpoint: The endpoint for the connection
    ///      - options: Additional options for the socket connection
    ///
    ///    - Returns: A new `SocketConnection`
    init(endpoint: NWEndpoint, options: Socket.Options) {
        self.allowPathMigration = options.allowPathMigration
        self.parameters = NWParameters(tls: options.allowInsecureConnections ? nil : .init(), tcp: options.tcpProtocolOptions)
        self.parameters.defaultProtocolStack.applicationProtocols.insert(options.websocketProtocolOptions, at: 0)
        self.endpoint = endpoint
        self.connection = NWConnection(to: self.endpoint, using: self.parameters)
        self._currentPath = Lock(connection.currentPath)
        self.setHandlers(for: self.connection)
    }
    
    /// clean up any active continuations.
    deinit {
        killAllStreams()
        self.connectionContinuation.modify { connectionContinuation in
            connectionContinuation?.resume()
            connectionContinuation = nil
        }
        self.disconnectionContinuation.modify { disconnectionContinuation in
            disconnectionContinuation?.resume()
            disconnectionContinuation = nil
        }
        self.receiveContinuations.modify { continuations in
            for continuation in continuations.values {
                continuation.resume(throwing: CancellationError())
            }
            continuations = [:]
        }
    }
}

// MARK: - Socket APIs
extension NetworkSocketConnection {
    
    /// Connect to the current endpoint, returning once the connection is marked `ready` or throwing an error if marked otherwise.
    func connect() async throws {
        guard self.connection.state == .setup else {
            if self.connection.state != .ready {
                throw SocketError.wsError(.init(domain: .WSConnectionDomain, code: .invalidConnectionAccess))
            }
            return
        }
        
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            guard let self else {
                continuation.resume()
                return
            }
            
            self.connectionContinuation.unsafeLock()
            guard self.connectionContinuation.unsafeValue == nil else {
                continuation.resume(throwing: SocketError.wsError(.init(domain: .WSConnectionDomain, code: .invalidConnectionAccess)))
                self.connectionContinuation.unlock()
                return
            }
            self.connectionContinuation.unsafeValue = continuation
            self.connectionContinuation.unlock()
            self.connection.start(queue: self.queue)
        }
    }
    
    /// Close the conection and clean up any process / storage
    func close(withCode code: CloseCode?) {
        defer { killAllStreams() }
        guard self.state != .disconnected else { return }
        
        // TODO: - Send correct close code info to server
        self.handleClose(closeCode: code ?? .protocolCode(.goingAway), reason: nil)
        self.connection.cancel()
    }
    
    /// Close the conection and clean up any process / storage, waiting for the proper FIN/ACK messages before returning.
    func close(withCode code: CloseCode?) async throws {
        defer { killAllStreams() }
        
        guard self.state != .disconnected else {
            return
        }
        
        // TODO: - Send correct close code info to server
        self.handleClose(closeCode: code ?? .protocolCode(.goingAway), reason: nil)
        
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            guard let self else {
                continuation.resume()
                return
            }
            
            guard self.state == .connected else {
                continuation.resume(throwing: SocketError.wsError(.init(domain: .WSConnectionDomain, code: .connectionNotReady)))
                return
            }
            
            self.disconnectionContinuation.unsafeLock()
            guard self.disconnectionContinuation.unsafeValue == nil else {
                continuation.resume(throwing: CancellationError())
                self.disconnectionContinuation.unlock()
                return
            }
            self.disconnectionContinuation.unsafeValue = continuation
            self.disconnectionContinuation.unlock()
            
            self.connection.cancel()
        }
    }
    
    
    /// Encode and send a string through the connection
    func send(_ text: String) async throws {
        guard let data = text.data(using: .utf8) else {
            throw SocketError.wsError(
                .init(
                    domain: .WSDataDomain,
                    code: .failedToEncode
                )
            )
        }
        let context = Context(identifier: "textContext", metadata: [WebSocketMetadata(opcode: .text)])
        
        try await send(data: data, context: context)
    }
    
    /// Send binary data through the connection
    func send(_ data: Data) async throws {
        let context = Context(identifier: "dataContext", metadata: [WebSocketMetadata(opcode: .binary)])
        
        try await send(data: data, context: context)
    }
    
    private func send(data: Data, context: Context) async throws {
        guard self.state == .connected else {
            throw SocketError.wsError(
                .init(
                    domain: .WSConnectionDomain,
                    code: .socketNotConnected,
                    userInfo: ["State": self.connection.state]
                )
            )
        }
        
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            guard let self else { return }

            self.connection.send(
                content: data,
                contentContext: context,
                isComplete: true,
                completion: NWConnection.SendCompletion.contentProcessed({ [weak self] error in
                    if let metadata = context.protocolMetadata.first as? WebSocketMetadata, metadata.opcode == .close {
                        self?.handleClose(closeCode: metadata.closeCode, reason: data)
                    }
                    
                    if let error = SocketError(error) {
                        continuation.resume(throwing: error)
                        self?.handleError(error: error)
                    } else {
                        continuation.resume()
                    }
                })
            )
        }
    }
    
    func receive<T: Decodable>(decodingType: T.Type) async throws -> T {
        let message = try await receive()
        return try decode(message, type: decodingType)
    }
    
    func receive() async throws -> SocketMessage {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<SocketMessage, Error>) in
            let id = UUID()
            self.receiveContinuations.modify { $0[id] = continuation }
            self.receive { [weak self] result in
                guard let self else {
                    continuation.resume(throwing: SocketError.wsError(.init(domain: .WSConnectionDomain, code: .connectionNotReady)))
                    return
                }
                self.publisher.push((connection: self, result: result))
                self.receiveContinuations.modify { continuations in
                    switch result {
                    case .success(let message):
                        continuations[id]?.resume(returning: message)
                    case .failure(let error):
                        continuations[id]?.resume(throwing: error)
                    }
                    continuations[id] = nil
                }
            }
        }
    }
    
    /// Receive a value and publish it to all subscribers
    func receiveAndPublish() {
        self.receive { [weak self] result in
            guard let self else { return }
            self.publisher.push((connection: self, result: result))
        }
    }
    
    /// Receive and parse a value directly from the provided connection.
    private func receive(connection: NWConnection? = nil, completion: @escaping @Sendable (Result<SocketMessage, Error>) -> Void) {
        guard self.state == .connected else {
            completion(.failure(SocketError.wsError(.init(domain: .WSConnectionDomain, code: .socketNotConnected))))
            return
        }
        
        (connection ?? self.connection).receiveMessage { [weak self] data, context, isComplete, error in
            guard let self else { return }

            if let error = SocketError(error) {
                self.handleError(error: error)
                completion(.failure(error))
                return
            }
            
            guard let metadata = context?.protocolMetadata.first as? WebSocketMetadata else {
                return
            }
            
            switch metadata.opcode {
            case .cont:
                break
            case .text:
                guard let data, let text = String(data: data, encoding: .utf8) else { return }
                completion(.success(.string(text)))
            case .binary:
                guard let data else { return }
                completion(.success(.data(data)))
            case .close:
                self.handleClose(closeCode: metadata.closeCode, reason: data)
            case .ping:
                self.handlePing()
            case .pong:
                self.handlePong()
            @unknown default:
                fatalError()
            }
            return
        }
    }
    
    func ping() async throws {
        guard self.state == .connected else { return }
        guard let ping = "ping".data(using: .utf8) else { return }
        
        let context = Context(identifier: "pingContext", metadata: [WebSocketMetadata(opcode: .ping)])
        
        try await send(data: ping, context: context)
    }
}

// MARK: - Handlers
extension NetworkSocketConnection {
    
    func onStateChange(_ action: @Sendable @escaping (ConnectionState) -> Void) {
        self._onStateChange.set(action)
    }
    
    func onShouldRefresh(_ action: @Sendable @escaping () -> Void) {
        self._onShouldRefresh.set(action)
    }
    
    private func setHandlers(for connection: NWConnection) {
        setStateHandler(connection: connection)
        setPathHandler(connection: connection)
        setViabilityHandler(connection: connection)
    }
    
    /// Set the state handler to update the shared state, and resume any non-nil continuations from either connect or disconnect
    private func setStateHandler(connection: NWConnection) {
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .setup, .preparing:
                self._state.set(.connecting)
            case .waiting(let error):
                self._state.set(.disconnected)
                self.connectionContinuation.modify { continuation in
                    continuation?.resume(throwing: SocketError(error))
                    continuation = nil
                }
                self.disconnectionContinuation.modify { continuation in
                    continuation?.resume(throwing: SocketError(error))
                    continuation = nil
                }
            case .ready:
                self._state.set(.connected)
                self.connectionContinuation.modify { continuation in
                    continuation?.resume()
                    continuation = nil
                }
                self.disconnectionContinuation.modify { continuation in
                    continuation?.resume(throwing: SocketError.wsError(.init(domain: .WSConnectionDomain, code: .disconnectFailed)))
                    continuation = nil
                }
            case .failed(let error):
                self._state.set(.disconnected)
                self.connectionContinuation.modify { continuation in
                    continuation?.resume(throwing: SocketError(error))
                    continuation = nil
                }
                self.disconnectionContinuation.modify { continuation in
                    continuation?.resume(throwing: SocketError(error))
                    continuation = nil
                }
            case .cancelled:
                self._state.set(.disconnected)
                self.connectionContinuation.modify { continuation in
                    continuation?.resume(throwing: CancellationError())
                    continuation = nil
                }
                self.disconnectionContinuation.modify { continuation in
                    continuation?.resume()
                    continuation = nil
                }
            @unknown default:
                self._state.set(.disconnected)
                self.connectionContinuation.modify { continuation in
                    continuation?.resume(throwing: SocketError.wsError(.init(domain: .WSConnectionDomain, code: .connectFailed)))
                    continuation = nil
                }
                self.disconnectionContinuation.modify { continuation in
                    continuation?.resume(throwing: SocketError.wsError(.init(domain: .WSConnectionDomain, code: .disconnectFailed)))
                    continuation = nil
                }
            }
            _onStateChange.value(self.state)
        }
    }
    
    private func setPathHandler(connection: NWConnection) {
        connection.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self._currentPath.set(path)
        }
    }
    
    private func setBetterPathHandler(connection: NWConnection) {
        connection.betterPathUpdateHandler = { [weak self] _ in
            guard let self else { return }
            self._onShouldRefresh.value()
        }
    }
    
    private func setViabilityHandler(connection: NWConnection) {
        connection.viabilityUpdateHandler = { [weak self] isViable in
            guard let self else { return }
            self._isViableConnection.set(isViable)
        }
    }
    
    // TODO: - Ping pong handling
    private func handlePing() {
        print("socket got a ping!")
    }
    
    private func handlePong() {
        print("socket got a pong!")
    }
    
    private func handleClose(closeCode: NWProtocolWebSocket.CloseCode, reason: Data?) {
        self._closeCode.set(closeCode)
    }
    
    private func handleError(error: SocketError) {
        switch error {
        case .nwError(let nwError):
            switch nwError {
            case .posix(let code):
                switch code {
                case .ECONNABORTED, .ECANCELED, .ENETDOWN, .ETIMEDOUT, .ENOTCONN:
                    handleClose(closeCode: .protocolCode(.goingAway), reason: "Socket disconnected.".data(using: .utf8))
                default:
                    break
                }
            default:
                break
            }
        case .nsError:
            break
        case .wsError:
            break
        }
        
    }
}

// MARK: - Decode
extension NetworkSocketConnection {
    
    private func decode<T: Decodable>(_ message: SocketMessage, type: T.Type) throws -> T {
        switch message {
        case .string(let string):
            guard let data = string.data(using: .utf8) else { throw SocketError.wsError(.init(domain: .WSDataDomain, code: .failedToDecode)) }
            return try decoder.decode(type, from: data)
        case .data(let data):
            return try decoder.decode(type, from: data)
        }
    }
}

// MARK: - Sequences
extension NetworkSocketConnection {
    
    /// Build a new `AsyncSocketSequence` that iterates a given decodable type
    func buildSequence<T: Decodable & Sendable>() -> AsyncSocketSequence<T> {
        let stream = AsyncSocketSequence<T>(connection: self)
        self.publisher.addSubscriber(stream)
        return stream
    }
    
    /// End all active sequences and clear the subscriber storage.
    func killAllStreams() {
        publisher.editSubscribers { streams in
            for stream in streams {
                stream.end()
            }
            streams.removeAll()
        }
    }
}
