//
//  Listener.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/19/25.
//

import Network
import Foundation
import CryptoKit

class Server: @unchecked Sendable {
    
    private let startLock = NSLock()
    private let stopLock = NSLock()
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var stopContinuation: CheckedContinuation<Void, Error>?
    private let listener: NWListener
    
    var state: NWListener.State
    
    init(port: UInt16) throws {
        let parameters = NWParameters.tcp
        self.listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        self.state = listener.state
        self.setHandlers()
    }
    
    func start() async throws {
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            guard let self else {
                continuation.resume(throwing: CancellationError())
                return
            }
            startLock.withLock { self.startContinuation = continuation }
            self.listener.start(queue: .main)
        }
        print("Listener started")
    }
    
    func stop() async throws {
        do {
            try stopLock.withLock {
                if self.stopContinuation != nil {
                    stopLock.unlock()
                    throw CancellationError()
                }
            }
        } catch {
            return
        }
        guard self.state == .ready else { return }
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            guard let self else {
                continuation.resume(throwing: CancellationError())
                return
            }
            stopLock.withLock { self.stopContinuation = continuation }
            self.listener.cancel()
        }
    }
    
    func unsafeStop() {
        listener.cancel()
    }
    
    private func setHandlers() {
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.state = state
            switch state {
            case .ready:
                startLock.withLock {
                    self.startContinuation?.resume()
                    self.startContinuation = nil
                }
                stopLock.withLock {
                    self.stopContinuation?.resume(throwing: CancellationError())
                    self.stopContinuation = nil
                }
            case .failed(let error):
                startLock.withLock {
                    self.startContinuation?.resume(throwing: error)
                    self.startContinuation = nil
                }
                stopLock.withLock {
                    self.stopContinuation?.resume(throwing: error)
                    self.stopContinuation = nil
                }
            case .setup:
                break
            case .waiting(let error):
                startLock.withLock {
                    self.startContinuation?.resume(throwing: error)
                    self.startContinuation = nil
                }
                stopLock.withLock {
                    self.stopContinuation?.resume(throwing: error)
                    self.stopContinuation = nil
                }
            case .cancelled:
                startLock.withLock {
                    self.startContinuation?.resume(throwing: CancellationError())
                    self.startContinuation = nil
                }
                stopLock.withLock {
                    self.stopContinuation?.resume()
                    self.stopContinuation = nil
                }
            @unknown default:
                break
            }
        }
        
        listener.newConnectionHandler = { [weak self] connection in
            self?.handleNewConnection(connection)
        }
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        print("New connection received")
        
        connection.stateUpdateHandler = { state in
            switch state {
            case .ready:
                print("Connection ready")
                self.receiveHTTPHeaders(on: connection)
            case .failed(let error):
                print("Connection failed with error: \(error)")
            case .cancelled:
                print("Connection cancelled")
            default:
                break
            }
        }
        
        connection.start(queue: .main)
    }
    
    private func receiveHTTPHeaders(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1024) { data, context, isComplete, error in
            
            if let data = data, !data.isEmpty {
                if let request = String(data: data, encoding: .utf8) {
                    print("Received HTTP request:\n\(request)")
                    self.handleHTTPRequest(request, on: connection)
                }
            }
            
            if let error = error {
                print("Receive error: \(error)")
                connection.cancel()
                return
            }
        }
    }
    
    private func handleHTTPRequest(_ request: String, on connection: NWConnection) {
        guard request.lowercased().contains("upgrade: websocket"),
              let key = extractWebSocketKey(from: request) else {
            print("Invalid WebSocket upgrade request, closing connection")
            connection.cancel()
            return
        }
        
        let acceptKey = generateWebSocketAcceptKey(for: key)
        let response = """
        HTTP/1.1 101 Switching Protocols\r
        Upgrade: websocket\r
        Connection: upgrade\r
        Sec-WebSocket-Accept: \(acceptKey)\r
        \r\n
        """
        
        print("Sending handshake response:\n\(response)")
        
        connection.send(content: response.data(using: .utf8), completion: .contentProcessed { error in
            if let error = error {
                print("Failed to send handshake response: \(error)")
                connection.cancel()
            } else {
                print("Handshake complete, ready to echo messages")
                // self.handleWebSocketMessages(on: connection)
                self.receiveWebSocketMessage(on: connection)
            }
        })
    }
    
    private func extractWebSocketKey(from request: String) -> String? {
        let lines = request.split(separator: "\r\n")
        for line in lines {
            if line.hasPrefix("Sec-WebSocket-Key:") {
                return line.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)
            }
        }
        return nil
    }
    
    private func generateWebSocketAcceptKey(for key: String) -> String {
        let magicString = key + "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
        let hash = Insecure.SHA1.hash(data: magicString.data(using: .utf8)!)
        return Data(hash).base64EncodedString()
    }
    
    func receiveWebSocketMessage(on connection: NWConnection) {
        connection.receive(minimumIncompleteLength: 2, maximumLength: 1024) { data, context, isComplete, error in
            guard let data = data, !data.isEmpty, let frame = SocketFrame(data) else {
                if let error = error {
                    print("Receive error: \(error)")
                }
                return
            }
            
            self.parseFrame(frame, connection: connection)
        }
    }
    
    func parseFrame(_ frame: SocketFrame, connection: NWConnection) {
        if frame.fin {
            print("Fin!")
        }
        print("Opcode received: \(frame.opcode)")
        let opcodeToSend = frame.opcode == .ping ? .pong : frame.opcode
        let context = NWConnection.ContentContext(identifier: "serverContext", metadata: [NWProtocolWebSocket.Metadata(opcode: frame.opcode)])
        switch frame.opcode {
        case .cont:
            print("still receiving, add data to buffer?")
        case .text:
            print("received text")
            self.sendWebSocketMessage(frame, with: context, on: connection)
        case .binary:
            print("received data")
            self.sendWebSocketMessage(frame, with: context, on: connection)
        case .close:
            print("close connection")
            connection.cancel()
        case .ping:
            print("send back pong")
            self.sendWebSocketMessage(frame, with: context, on: connection)
        case .pong:
            print("do nothing, just pong")
        @unknown default:
            fatalError()
        }
        self.receiveWebSocketMessage(on: connection)
    }
    
    
    
    func sendWebSocketMessage(_ data: SocketFrame, with context: NWConnection.ContentContext?, on connection: NWConnection) {
        // WebSocket frame: text frame (0x1) with FIN bit set
      //  var frame = Data([0x81]) // 0x81 = FIN + Text Frame
        let opcodeToSend = data.opcode == .ping ? .pong : data.opcode
        let frame = SocketFrame(opcode: opcodeToSend, payload: data.payload, mask: false)
        
        connection.send(content: frame.raw, contentContext: context ?? .defaultMessage, completion: .contentProcessed { error in
            if let error = error {
                print("Failed to send WebSocket message: \(error)")
            } else {
                print("Sent WebSocket message: \(String(data: data.payload, encoding: .utf8))")
            }
        })
    }
}

extension UInt16 {
    var bytes: [UInt8] {
        return withUnsafeBytes(of: self) { Array($0) }
    }
}

extension UInt64 {
    var bytes: [UInt8] {
        return withUnsafeBytes(of: self) { Array($0) }
    }
}
