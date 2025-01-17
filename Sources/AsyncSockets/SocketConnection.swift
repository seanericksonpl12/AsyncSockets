//
//  SocketConnection.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/10/25.
//

import Foundation
import Network

public final class SocketConnection: Sendable {
    
    public enum State: Sendable {
        case connecting
        case migrating
        case connected
        case disconnected
    }
    
    public var closeCode: CloseCode { _closeCode.value }
    
    public var state: State { _state.value }
    
    public var isViableConnection: Bool? { _isViableConnection.value }
    
    public var currentPath: NWPath? { _currentPath.value }
    
    private let connectionContinuation: Lock<CheckedContinuation<Void, Error>?> = Lock(nil)
    
    private let disconnectionContinuation: Lock<CheckedContinuation<Void, Error>?> = Lock(nil)
    
    private var connection: NWConnection { _connection.value }
    
    private let endpoint: NWEndpoint
    
    private let parameters: NWParameters
    
    private let allowPathMigration: Bool
    
    private let queue = DispatchQueue(label: "NWSocketQueue")
    
    private let _closeCode: Lock<CloseCode> = Lock(CloseCode.protocolCode(.noStatusReceived))
    
    private let _state: Lock<State> = Lock(.disconnected)
    
    private let _isViableConnection: Lock<Bool?> = Lock(nil)
    
    private let _currentPath: Lock<NWPath?>
    
    private let _connection: Lock<NWConnection>
    
    private let userDisconnected: Lock<Bool> = Lock(false)
    
    private let publisher: Publisher<AsyncSocketSequence<SocketMessage>> = Publisher()
    
    private let genericPublishers: Lock<[String: AnySendable]> = Lock([:])
    
    private let decoder = JSONDecoder()
    
    public static let defaultSocketOptions: WebSocketProtocolOptions = {
        let options = WebSocketProtocolOptions()
        options.autoReplyPing = true
        return options
    }()
    
    convenience init(
        url: URL,
        options: Socket.Options
    ) {
        self.init(endpoint: NWEndpoint.url(url), options: options)
    }
    
    convenience init(
        host: String,
        port: Int,
        options: Socket.Options
    ) {
        self.init(endpoint: NWEndpoint.hostPort(host: .init(host), port: NWEndpoint.Port(integerLiteral: UInt16(port))), options: options)
    }
    
    init(
        endpoint: NWEndpoint,
        options: Socket.Options
    ) {
        self.allowPathMigration = options.allowPathMigration
        self.parameters = NWParameters(tls: options.allowInsecureConnections ? nil : .init(), tcp: options.tcpProtocolOptions)
        self.parameters.defaultProtocolStack.applicationProtocols.insert(options.websocketProtocolOptions, at: 0)
        self.endpoint = endpoint
        self._connection = Lock(NWConnection(to: self.endpoint, using: self.parameters))
        self._currentPath = Lock(_connection.value.currentPath)
        self.setHandlers(for: self.connection)
    }
    
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
    }
}

extension SocketConnection {
    
    func connect() async throws {
        guard self.connection.state == .setup else { return }
        
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            guard let self else {
                continuation.resume()
                return
            }
            
            self.connectionContinuation.unsafeLock()
            guard self.connectionContinuation.unsafeValue == nil else {
                continuation.resume(throwing: CancellationError())
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
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
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
            self.receive { [weak self] result in
                guard let self else { return }
                self.publisher.push((connection: self, result: result))
                switch result {
                case .success(let message):
                    continuation.resume(returning: message)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }
    
    func receive<T: Decodable & Sendable>(decodingType: T.Type, ignoringDecodeError: Bool) {
        self.receive { [weak self] result in
            guard let self else { return }
            
            if let genericPublisher = self.getGenericPublishers(for: decodingType) {
                switch result {
                case .success(let message):
                    do {
                        genericPublisher.push(.success(try self.decode(message, type: decodingType)), from: self)
                    } catch {
                        if !ignoringDecodeError {
                            genericPublisher.push(.failure(error), from: self)
                        } else {
                            receive(decodingType: decodingType, ignoringDecodeError: ignoringDecodeError)
                        }
                    }
                case .failure(let error):
                    genericPublisher.push(.failure(error), from: self)
                }
            }
        }
    }

    func receive() {
        self.receive { [weak self] result in
            guard let self else { return }
            self.publisher.push((connection: self, result: result))
        }
    }
    
    private func receive(completion: @escaping @Sendable (Result<SocketMessage, Error>) -> Void) {
        guard self.state == .connected else {
            return
        }
        
        self.connection.receiveMessage { [weak self] data, context, isComplete, error in
            if let error = SocketError(error) {
                self?.handleError(error: error)
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
                self?.handleClose(closeCode: metadata.closeCode, reason: data)
            case .ping:
                self?.handlePing()
            case .pong:
                self?.handlePong()
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
extension SocketConnection {
    
    private func setHandlers(for connection: NWConnection) {
        setStateHandler(connection: connection)
        setPathHandler(connection: connection)
        setBetterPathHandler(connection: connection)
        setViabilityHandler(connection: connection)
    }
    
    /// Set the state handler to update the shared state, and resume any non-nil continuations from either connect or disconnect
    private func setStateHandler(connection: NWConnection) {
        self.connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .setup, .preparing:
                self._state.set(.connecting)
            case .waiting(let error):
                self._state.set(.disconnected)
                self.connectionContinuation.modify { continuation in
                    continuation?.resume(throwing: error)
                    continuation = nil
                }
                self.disconnectionContinuation.modify { continuation in
                    continuation?.resume(throwing: error)
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
                    continuation?.resume(throwing: error)
                    continuation = nil
                }
                self.disconnectionContinuation.modify { continuation in
                    continuation?.resume(throwing: error)
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
        }
    }
    
    private func setPathHandler(connection: NWConnection) {
        self.connection.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            self._currentPath.set(path)
        }
    }
    
    private func setBetterPathHandler(connection: NWConnection) {
        self.connection.betterPathUpdateHandler = { betterPathAvailable in
            // TODO - Migration
        }
    }
    
    private func setViabilityHandler(connection: NWConnection) {
        self.connection.viabilityUpdateHandler = { [weak self] isViable in
            guard let self else { return }
            self._isViableConnection.set(isViable)
        }
    }
    
    // TODO: - Ping pong handling
    private func handlePing() {
        
    }
    
    private func handlePong() {
        
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
extension SocketConnection {
    
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
extension SocketConnection {
    
    func consumableSequence() -> AsyncSocketSequence<SocketMessage> {
        let stream = AsyncSocketSequence<SocketMessage>(connection: self)
        self.publisher.addSubscriber(stream)
        return stream
    }
    
    func consumableGenericSequence<T: Decodable & Sendable>(ignoringFailure: Bool) -> AsyncSocketSequence<T> {
        let stream = AsyncSocketSequence<T>(connection: self, ignoringDecodeError: ignoringFailure)
        let publisher: GenericSequencePublisher<T> = getOrCreateGenericPublisher()
        publisher.addSubscriber(stream)
        return stream
    }
    
    private func getOrCreateGenericPublisher<T: Decodable & Sendable>() -> GenericSequencePublisher<T> {
        genericPublishers.unsafeLock()
        defer { genericPublishers.unlock() }
        
        let key = String(describing: T.self)
        if let publisher = genericPublishers.unsafeValue[key]?.value as? GenericSequencePublisher<T> {
            return publisher
        }
        let publisher = GenericSequencePublisher<T>()
        genericPublishers.unsafeValue[key] = AnySendable(value: publisher)
        return publisher
    }
    
    private func getGenericPublishers<T: Decodable & Sendable>(for type: T.Type) -> GenericSequencePublisher<T>? {
        genericPublishers.unsafeLock()
        defer { genericPublishers.unlock() }
        
        let key = String(describing: T.self)
        if let publisher = genericPublishers.unsafeValue[key]?.value as? GenericSequencePublisher<T> {
            return publisher
        }
        
        return nil
    }
    
    func killAllStreams() {
        publisher.editSubscribers { streams in
            for stream in streams {
                stream.end()
            }
            streams.removeAll()
        }
        // kill all generic publishers
        genericPublishers.set([:])
    }
}
