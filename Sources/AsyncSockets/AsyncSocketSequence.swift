//
//  SocketStream.swift
//  AsyncSockets
//
// Created by Sean Erickson on 1/13/25.
//

import Foundation

/// Async
public final class AsyncSocketSequence<Message: Decodable & Sendable>: AsyncSequence, Subscriber, Sendable {
    
    public typealias AsyncIterator = AsyncThrowingStream<Message, Error>.Iterator
    
    internal typealias Value = (connection: SocketConnection, result: Result<Message, Error>)
    
    private let continuationLock: Lock<AsyncThrowingStream<Message, Error>.Continuation?> = Lock(nil)
    
    private let ignoreDecodeError: Bool?
    
    private let stream: Lazy<AsyncThrowingStream<Message, Error>> = Lazy()

    private let id: UUID
    
    internal init(connection: SocketConnection, ignoringDecodeError: Bool? = nil) {
        self.id = UUID()
        self.ignoreDecodeError = ignoringDecodeError
        self.stream.set { [weak self, weak connection] in
            guard let self, let connection else {
                return AsyncThrowingStream<Message, Error> { $0.finish() }
            }
            
            return AsyncThrowingStream<Message, Error> { continuation in
                self.continuationLock.set(continuation)
                if let ignoreDecodeError {
                    connection.receive(decodingType: Message.self, ignoringDecodeError: ignoreDecodeError)
                } else {
                    connection.receive()
                }
            }
        }
    }
    
    internal func didReceiveValue(_ value: Value) {
        guard value.connection.closeCode == .protocolCode(.noStatusReceived) else {
            self.continuationLock.value?.finish()
            return
        }
        
        guard value.connection.state == .connected else {
            self.continuationLock.value?.finish()
            return
        }
        
        continuationLock.modify { continuation in
            guard let continuation else { return }
            switch value.result {
            case .success(let message):
                continuation.yield(message)
                if let ignoreDecodeError {
                    value.connection.receive(decodingType: Message.self, ignoringDecodeError: ignoreDecodeError)
                } else {
                    value.connection.receive()
                }
            case .failure(let error):
                continuation.finish(throwing: error)
            }
        }
    }

    deinit {
        end()
    }
    
    public static func == (lhs: AsyncSocketSequence, rhs: AsyncSocketSequence) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    public func makeAsyncIterator() -> AsyncIterator {
        return stream.value.makeAsyncIterator()
    }
    
    /// End the current stream
    public func end() {
        continuationLock.value?.finish()
    }
}


