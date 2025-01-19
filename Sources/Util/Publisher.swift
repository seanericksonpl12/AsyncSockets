//
//  LockedBuffer.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/15/25.
//

import Foundation

protocol Subscriber<Value>: Sendable, Hashable {
    associatedtype Value
    func didReceiveValue(_ value: Value)
}

final class Publisher<T: Subscriber>: Sendable {
    
    private let subscribers: Lock<Set<T>> = Lock([])
    
    func push(_ element: T.Value) {
        subscribers.modify { subscribers in
            subscribers.forEach { subscriber in
                subscriber.didReceiveValue(element)
            }
        }
    }
    
    func addSubscriber(_ subscriber: T) {
        subscribers.modify { $0.insert(subscriber) }
    }
    
    func editSubscribers(_ transform: (inout Set<T>) -> Void) {
        subscribers.modify { subscribers in
            transform(&subscribers)
        }
    }
}

final class GenericSequencePublisher<Message: Decodable & Sendable>: Sendable {
    
    private let subscribers: Lock<Set<AsyncSocketSequence<Message>>> = Lock([])
    
    deinit {
        self.editSubscribers { subscribers in
            for sequence in subscribers {
                sequence.end()
            }
        }
    }
    
    func push(_ result: Result<Message, Error>, from connection: SocketConnection) {
        subscribers.modify { subscribers in
            subscribers.forEach { subscriber in
                subscriber.didReceiveValue((connection: connection, result: result))
            }
        }
    }
    
    func addSubscriber(_ subscriber: AsyncSocketSequence<Message>) {
        subscribers.modify { $0.insert(subscriber) }
    }
    
    func editSubscribers(_ transform: (inout Set<AsyncSocketSequence<Message>>) -> Void) {
        subscribers.modify { subscribers in
            transform(&subscribers)
        }
    }
}

