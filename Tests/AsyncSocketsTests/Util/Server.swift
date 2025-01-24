//
//  Listener.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/19/25.
//

import Network
import Foundation
import CryptoKit
@testable import AsyncSockets
final class Server: Sendable {
    
    let startContinuation: Lock<CheckedContinuation<Void, Error>?> = Lock(nil)
    let stopContinuation: Lock<CheckedContinuation<Void, Error>?> = Lock(nil)
    
    private let listener: NWListener
    private let queue = DispatchQueue(label: "com.asyncsockets.server")
    
    private let connections = Lock<[ServerConnection]>([])
    
    let state: Lock<NWListener.State>
    let receiveCount = Lock(0)
    let sendCount = Lock(0)
    
    init(port: UInt16) throws {
        let parameters = NWParameters.tcp
        self.listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
        self.state = Lock(listener.state)
        self.setHandlers()
    }
    
    deinit {
        self.startContinuation.modify {
            $0?.resume()
            $0 = nil
        }
        self.stopContinuation.modify {
            $0?.resume()
            $0 = nil
        }
    }
    
    func start() async throws {
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            guard let self else {
                continuation.resume(throwing: CancellationError())
                return
            }
            self.startContinuation.modify { $0 = continuation }
            self.listener.start(queue: queue)
        }
        print("Listener started")
    }
    
    func stop() async throws {
        try await withCheckedThrowingContinuation { [weak self] (continuation: CheckedContinuation<Void, Error>) in
            guard let self, self.state.value == .ready else {
                continuation.resume(throwing: CancellationError())
                return
            }
            self.stopContinuation.modify { $0 = continuation }
            self.listener.cancel()
        }
    }
    
    func unsafeStop() {
        listener.cancel()
    }
    
    private func setHandlers() {
        listener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            self.state.modify { $0 = state }
            switch state {
            case .ready:
                self.startContinuation.modify { continuation in
                    continuation?.resume()
                    continuation = nil
                }
                self.stopContinuation.modify { continuation in
                    continuation?.resume(throwing: CancellationError())
                    continuation = nil
                }
            case .failed(let error), .waiting(let error):
                self.startContinuation.modify { continuation in
                    continuation?.resume(throwing: error)
                    continuation = nil
                }
                self.stopContinuation.modify { continuation in
                    continuation?.resume(throwing: error)
                    continuation = nil
                }
            case .setup:
                break
            case .cancelled:
                self.startContinuation.modify { continuation in
                    continuation?.resume(throwing: CancellationError())
                    continuation = nil
                }
                self.stopContinuation.modify { continuation in
                    continuation?.resume()
                    continuation = nil
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
        let new = ServerConnection(connection: connection)
        self.connections.modify { $0.append(new) }
        new.start()
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
