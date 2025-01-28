//
//  AsyncSocketSequence.swift
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

/// Async
public final class AsyncSocketSequence: AsyncSequence, Subscriber, Sendable {
    
    public typealias AsyncIterator = AsyncThrowingStream<SocketMessage, Error>.Iterator
    
    internal typealias Value = (connection: AsyncConnection, result: Result<SocketMessage, Error>)
    
    private let continuationLock: Lock<AsyncThrowingStream<SocketMessage, Error>.Continuation?> = Lock(nil)
    
    private let stream: Lazy<AsyncThrowingStream<SocketMessage, Error>> = Lazy()

    private let id: UUID
    
    internal init(connection: AsyncConnection) {
        self.id = UUID()
        self.stream.set { [weak self, weak connection] in
            guard let self, let connection else {
                return AsyncThrowingStream<SocketMessage, Error> { $0.finish() }
            }
            
            return AsyncThrowingStream<SocketMessage, Error> { continuation in
                self.continuationLock.set(continuation)
                connection.receiveAndPublish()
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
                value.connection.receiveAndPublish()
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

extension AsyncSocketSequence {
    
    /// Convenience function to compactMap the sequence into Text cases.
    ///
    /// If the sequence receives types `.data`, `.ping`, or `.pong`, they will be dropped silently
    ///
    /// Example:
    ///
    ///     for try await text in socket.messages().text() {
    ///         print("received string: \(text)")
    ///     }
    ///
    /// - Returns: An AsyncSequence that iterates the .string cases of all socket messages
    public func text() -> AsyncCompactMapSequence<AsyncSocketSequence, String> {
        self.compactMap { element in
            switch element {
            case .string(let message):
                return message
            default:
                return nil
            }
        }
    }
    
    /// Convenience function to compactMap the sequence into Data cases.
    ///
    /// If the sequence receives types `.string`, `.ping`, or `.pong`, they will be dropped silently
    ///
    /// Example:
    ///
    ///     for try await text in socket.messages().data() {
    ///         print("received data: \(String(data: data, encoding: .utf8))")
    ///     }
    ///
    /// - Returns: An AsyncSequence that iterates the .data cases of all socket messages
    public func data() -> AsyncCompactMapSequence<AsyncSocketSequence, Data> {
        self.compactMap { element in
            switch element {
            case .data(let data):
                return data
            default:
                return nil
            }
        }
    }
    
    /// Convenience function to compactMap the sequence into on objects of a given Decodable type.
    ///
    /// This function will attempt to decode both data and string messages to the given object type, and
    /// drop them silently on failure.
    ///
    /// Example:
    ///
    ///     struct MyStruct: Decodable, Sendable {
    ///         let id = Int
    ///         let value = String
    ///     }
    ///
    ///     for try await obj in socket.messages.obj(ofType: MyStruct.self) {
    ///         print("received object \(obj.id) with value \(obj.value)")
    ///     }
    ///
    /// - Returns: An AsyncSequence that iterates the .data cases of all socket messages
    public func objects<T: Sendable & Decodable>(ofType type: T.Type) -> AsyncCompactMapSequence<AsyncSocketSequence, T> {
        let decoder = JSONDecoder()
        return self.compactMap { message in
            switch message {
            case .string(let string):
                 guard let data = string.data(using: .utf8) else { return nil }
                return try? decoder.decode(type, from: data)
            case .data(let data):
                return try? decoder.decode(type, from: data)
            default:
                return nil
            }
        }
    }
}


