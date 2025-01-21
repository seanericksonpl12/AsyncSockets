//
//  PublisherTests.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/16/25.
//

import XCTest
@testable import AsyncSockets

// Mock subscriber for testing
final class MockSubscriber: Subscriber, Sendable {
    func end() {
        onEnd()
    }
    
    typealias Value = String
    
    private let id = UUID()
    private let onReceive: @Sendable (String) -> Void
    private let onEnd: @Sendable () -> Void
    
    init(onReceive: @escaping @Sendable (String) -> Void, onEnd: @escaping @Sendable () -> Void = { }) {
        self.onReceive = onReceive
        self.onEnd = onEnd
    }
    
    func didReceiveValue(_ value: String) {
        onReceive(value)
    }
    
    static func == (lhs: MockSubscriber, rhs: MockSubscriber) -> Bool {
        lhs.id == rhs.id
    }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

final class PublisherTests: XCTestCase {
    var publisher: Publisher<String>!
    
    override func setUp() {
        publisher = Publisher()
    }
    
    override func tearDown() {
        publisher = nil
    }
    
    func testSingleSubscriber() {
        let receivedValue: Lock<String?> = Lock(nil)
        let subscriber = MockSubscriber { value in
            receivedValue.modify { $0 = value }
        }
        
        publisher.addSubscriber(subscriber)
        publisher.push("test message")
        
        XCTAssertEqual(receivedValue.value, "test message")
    }
    
    func testMultipleSubscribers() {
        let count1 = Lock(0)
        let count2 = Lock(0)
        
        let subscriber1 = MockSubscriber { _ in count1.modify { $0 += 1 } }
        let subscriber2 = MockSubscriber { _ in count2.modify { $0 += 1 } }
        
        publisher.addSubscriber(subscriber1)
        publisher.addSubscriber(subscriber2)
        
        publisher.push("test")
        
        XCTAssertEqual(count1.value, 1)
        XCTAssertEqual(count2.value, 1)
    }
    
    func testConcurrentSubscribers() async {
        // use fresh publisher to avoid concurrency warnings with self
        let publisher = Publisher<String>()
        let messageCount = 1000
        let subscriberCount = 10
        let expectation = XCTestExpectation(description: "All messages received")
        expectation.expectedFulfillmentCount = subscriberCount
        
        let counters = Lock<[UUID: Int]>([:])
        
        // Add multiple subscribers
        for _ in 0..<subscriberCount {
            let id = UUID()
            counters.modify { $0[id] = 0 }
            
            let subscriber = MockSubscriber { _ in
                counters.modify { dict in
                    dict[id, default: 0] += 1
                    if dict[id] == messageCount {
                        expectation.fulfill()
                    }
                }
            }
            publisher.addSubscriber(subscriber)
        }
        
        // Push messages concurrently
        await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<messageCount {
                group.addTask {
                    publisher.push("message \(i)")
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Verify all subscribers received all messages
        counters.modify { dict in
            for count in dict.values {
                XCTAssertEqual(count, messageCount)
            }
        }
    }
    
    func testEditSubscribers() {
        let receivedCount = Lock(0)
        let subscriber = MockSubscriber { _ in receivedCount.modify { $0 += 1 } }
        
        publisher.addSubscriber(subscriber)
        publisher.push("test1")
        XCTAssertEqual(receivedCount.value, 1)
        
        // Remove all subscribers
        publisher.editSubscribers { $0.removeAll() }
        publisher.push("test2")
        XCTAssertEqual(receivedCount.value, 1) // Should not increase
    }
}
