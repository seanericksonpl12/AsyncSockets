//
//  MigrationTests 2.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/20/25.
//

import XCTest
@testable import AsyncSockets
import Network

final class MigrationTests: XCTestCase {
    var url: URL!
    
    override func setUp() {
        super.setUp()
        self.url = URL(string: "ws://localhost:8000")!
    }
    
    func testBasicMigration() async throws {
        let socket = Socket(url: self.url, options: .init(allowInsecureConnections: true))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(block: { _,_ in return socket.state == .connected }), object: socket)
        
        try await socket.connect()
        
        socket.connection.migrate()
        XCTAssertEqual(socket.state, .migrating)
        await fulfillment(of: [expectation], timeout: 5.0)
    }
    
    func testBasicMigrationConcurrent() async throws {
        var sockets = [Socket]()
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(block: { _,_ in
            var fulfilled = true
            for socket in sockets {
                if socket.state != .connected { fulfilled = false }
            }
            return fulfilled
        }), object: socket)
        
        for i in 0..<4 {
            sockets.append(Socket(url: self.url, options: .init(allowInsecureConnections: true)))
        }
        
        for socket in sockets {
            try await socket.connect()
        }
        
        for socket in sockets {
            socket.connection.migrate()
            XCTAssertEqual(socket.state, .migrating)
        }
        
        await fulfillment(of: [expectation])
    }
    
    func testMigrationSending() async throws {
        let socket = Socket(url: self.url, options: .init(allowInsecureConnections: true))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(block: { _,_ in return socket.state == .connected }), object: socket)
        
        try await socket.connect()
        let sendAttempts = Lock(0)
        let successfulSends = Lock(0)
        
        Task {
            socket.connection.migrate()
            while true {
                sendAttempts.modify { $0 += 1 }
                try await socket.send("Test String")
                successfulSends.modify { $0 += 1 }
                if socket.state == .connected { break }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(sendAttempts.value, successfulSends.value)
    }
    
    func testMigrationSendingConcurrent() async throws {
        var sockets = [Socket]()
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(block: { _,_ in
            var fulfilled = true
            for socket in sockets {
                if socket.state != .connected { fulfilled = false }
            }
            return fulfilled
        }), object: socket)
        
        for _ in 0..<4 {
            sockets.append(Socket(url: self.url, options: .init(allowInsecureConnections: true)))
        }
        
        for socket in sockets {
            try await socket.connect()
        }
        
        let sendAttempts = Lock([0,0,0,0])
        let successfulSends = Lock([0,0,0,0])
        
        Task {
            for socket in sockets {
                socket.connection.migrate()
            }
            while true {
                for i in 0..<4 {
                    sendAttempts.modify { $0[i] += 1 }
                    try await sockets[i].send("Test String")
                    successfulSends.modify { $0[i] += 1 }
                    if sockets[3].state == .connected { return }
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 2.0)
        XCTAssertEqual(sendAttempts.value, [1,1,1,1])
    }

    func testMigrationWhileReceiving() async throws {
        let socket = Socket(url: self.url, options: .init(allowInsecureConnections: true))
        
        try await socket.connect()
        let sendCount = 40
        let messageCount = Lock(0)
        Task {
            for try await _ in socket.messages() {
                messageCount.modify { $0 += 1 }
            }
        }
        
        for i in 0..<sendCount {
            if i == 10 { socket.connection.migrate() }
            try await socket.send("test")
        }
        
        // Wait for messages to be processed
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(messageCount.value, sendCount)
    }

    func testMigrationWithMultipleStreams() async throws {
        let socket = Socket(url: self.url, options: .init(allowInsecureConnections: true))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(block: { _,_ in return socket.state == .connected }), object: socket)
        
        try await socket.connect()
        
        let streamCount = 3
        let messageCountPerStream = Lock(Array(repeating: 0, count: streamCount))
        
        // Create multiple message streams
        for i in 0..<streamCount {
            Task {
                for try await _ in socket.messages() {
                    messageCountPerStream.modify { $0[i] += 1 }
                    if messageCountPerStream.value[i] == 2 { break }
                }
            }
        }
        
        // Send messages, migrate, then send more
        for _ in 0..<streamCount {
            try await socket.send("Pre-migration")
        }
        
        socket.connection.migrate()
        
        for _ in 0..<streamCount {
            try await socket.send("Post-migration")
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        
        // Verify each stream received messages
        for count in messageCountPerStream.value {
            XCTAssertEqual(count, 2)
        }
    }

    func testMigrationFailure() async throws {
        let socket = Socket(url: self.url, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        socket.connection.migrate()
        try await socket.close()
        
        XCTAssertEqual(socket.state, .disconnected)
    }

    func testConcurrentMigrationAttempts() async throws {
        let socket = Socket(url: self.url, options: .init(allowInsecureConnections: true))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(block: { _,_ in return socket.state == .connected }), object: socket)
        
        try await socket.connect()
        
        // Attempt multiple migrations concurrently
        await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 0..<5 {
                group.addTask {
                    socket.connection.migrate()
                }
            }
        }
        
        await fulfillment(of: [expectation], timeout: 5.0)
        XCTAssertEqual(socket.state, .connected)
    }

    func testMigrationDuringDecodableMessageSequence() async throws {
        let socket = Socket(url: self.url, options: .init(allowInsecureConnections: true))
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(block: { _,_ in return socket.state == .connected }), object: socket)
        
        try await socket.connect()
        
        struct TestMessage: Codable, Sendable {
            let id: Int
            let text: String
        }
        
        let messageCount = Lock(0)
        Task {
            for try await _ in socket.messages(ofType: TestMessage.self) {
                messageCount.modify { $0 += 1 }
            }
        }
        
        // Send encoded message, migrate, then send another
        let message1 = TestMessage(id: 1, text: "Pre-migration")
        try await socket.send(JSONEncoder().encode(message1))
        
        socket.connection.migrate()
        
        let message2 = TestMessage(id: 2, text: "Post-migration")
        try await socket.send(JSONEncoder().encode(message2))
        
        await fulfillment(of: [expectation], timeout: 5.0)
        XCTAssertEqual(messageCount.value, 2)
    }
    
    func testMigrationReceivingDataLoss() async throws {
        let socket = Socket(url: self.url, options: .init(allowInsecureConnections: true))
        
        try await socket.connect()
        
        let sendCount = 40
        let receivedCount = Lock(0)
        
        Task {
            while true {
                let message = try await socket.receive()
                if case let .string(str) = message, str == "test" {
                    receivedCount.modify { $0 += 1 }
                }
            }
        }
        
        for i in 0..<sendCount {
            if i == (sendCount / 2) { socket.connection.migrate() }
            try await socket.send("test")
        }
        
        // wait for all messages to be parsed
        try await Task.sleep(nanoseconds: 2_000_000_000)
        XCTAssertEqual(sendCount, receivedCount.value)
    }
    
    func testMigrationSequenceDataLoss() async throws {
        let socket = Socket(url: self.url, options: .init(allowInsecureConnections: true))
        
        try await socket.connect()
        
        let sendCount = 40
        let receivedCount = Lock(0)
        
        Task {
            for try await message in socket.messages() {
                if case let .string(str) = message, str == "test" {
                    receivedCount.modify { $0 += 1 }
                }
            }
        }
        
        for i in 0..<sendCount {
            if i == (sendCount / 2) { socket.connection.migrate() }
            try await socket.send("test")
        }
        
        // wait for all messages to be parsed
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(sendCount, receivedCount.value)
    }
    
    func testMigrationDecodableSequenceDataLoss() async throws {
        struct TestMessage: Codable {
            let value: String
        }
        let encoder = JSONEncoder()
        let socket = Socket(url: self.url, options: .init(allowInsecureConnections: true))
        
        try await socket.connect()
        
        let sendCount = 40
        let receivedCount = Lock(0)
        
        Task {
            for try await message in socket.messages(ofType: TestMessage.self) {
                if message.value == "test" {
                    receivedCount.modify { $0 += 1 }
                }
            }
        }
        
        for i in 0..<sendCount {
            if i == (sendCount / 2) { socket.connection.migrate() }
            let message = TestMessage(value: "test")
            let data = try encoder.encode(message)
            try await socket.send(data)
        }
        
        // wait for all messages to be parsed
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(sendCount, receivedCount.value)
    }
    
    func testConcurrentMigrationReceivingDataLoss() async throws {
        var sockets = [Socket]()
        
        for i in 0..<2 {
            sockets.append(Socket(url: self.url, options: .init(allowInsecureConnections: true), debugNumber: i))
        }
        
        let sendCount = 40
        let receivedCount = Lock([Int](repeating: 0, count: sockets.count))
        for (index, socket) in sockets.enumerated() {
            try await socket.connect()
        }
        
        Task {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, socket) in sockets.enumerated() {
                    group.addTask {
                        var i = 0
                        while true {
                            if i == 20 { socket.connection.migrate() }
                            let message = try await socket.receive()
                            if case let .string(str) = message {
                                receivedCount.modify { $0[index] += 1 }
                                print(str)
                            }
                            i += 1
                        }
                    }
                }
                
                try await group.waitForAll()
            }
        }
        
        try await Task.sleep(nanoseconds: 1_000_000_000)
        for (index, socket) in sockets.enumerated() {
            try await socket.send("begin")
        }
 
        // wait for all messages to be parsed
        try await Task.sleep(nanoseconds: 2_000_000_000)
        print(receivedCount.value)
        for value in receivedCount.value {
            XCTAssertEqual(value, sendCount)
        }
    }
    
    func testConcurrentMigrationSequenceDataLoss() async throws {
        let socket = Socket(url: self.url, options: .init(allowInsecureConnections: true))
        
        try await socket.connect()
        
        let sendCount = 40
        let receivedCount = Lock(0)
        
        Task {
            for try await message in socket.messages() {
                if case let .string(str) = message, str == "test" {
                    receivedCount.modify { $0 += 1 }
                }
            }
        }
        
        for i in 0..<sendCount {
            if i == (sendCount / 2) { socket.connection.migrate() }
            try await socket.send("test")
        }
        
        // wait for all messages to be parsed
        try await Task.sleep(nanoseconds: 1_000_000_000)
        XCTAssertEqual(sendCount, receivedCount.value)
    }
    
    func testConcurrentMigrationDecodableSequenceDataLoss() async throws {
        struct TestMessage: Codable {
            let value: String
        }
        let encoder = JSONEncoder()
        
        var sockets = [Socket]()
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(block: { _,_ in
            var fulfilled = true
            for socket in sockets {
                if socket.state != .connected { fulfilled = false }
            }
            return fulfilled
        }), object: socket)
        
        for _ in 0..<4 {
            sockets.append(Socket(url: self.url, options: .init(allowInsecureConnections: true)))
        }
        
        for socket in sockets {
            try await socket.connect()
        }
        
        let sendCount = 40
        let receivedCount = Lock([Int](repeating: 0, count: sockets.count))
        
        Task {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, socket) in sockets.enumerated() {
                    group.addTask {
                        for try await message in socket.messages(ofType: TestMessage.self) {
                            if message.value == "test" {
                                receivedCount.modify { $0[index] += 1 }
                            }
                        }
                    }
                }
                
                try await group.waitForAll()
            }
        }
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, socket) in sockets.enumerated() {
                group.addTask {
                    for i in 0..<sendCount {
                        if i == (sendCount / 2) {
                            socket.connection.migrate()
                            print("migrating socket number \(index)")
                        }
                        let message = TestMessage(value: "test")
                        let data = try encoder.encode(message)
                        try await socket.send(data)
                    }
                }
            }
            
            try await group.waitForAll()
        }
        
        
        // wait for all messages to be parsed
        try await Task.sleep(nanoseconds: 1_000_000_000)
        print(receivedCount.value)
        for value in receivedCount.value {
            XCTAssertEqual(value, sendCount)
        }
    }
}
