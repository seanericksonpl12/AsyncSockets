//
//  ReceiveTests.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/16/25.
//

import XCTest
@testable import AsyncSockets
import Network

final class ReceiveTests: AsyncSocketsTestCase {

    func testReceiveMessage() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        // Create a task to simulate receiving a message
        activeTasks.append(Task {
            try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second delay
            try await socket.send("Test Message")
        })
        
        // Test receiving a message
        let message = try await socket.receive()
        
        switch message {
        case .string(let text):
            XCTAssertEqual(text, "Test Message")
        case .data:
            XCTFail("Expected string message")
        }
        
        // Clean up
        try? await socket.close()
        print("test done.")
    }
    
    func testReceiveMessageConcurrent() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        let messageCount = 5
        let receivedMessages = Lock<[String]>([])
        
        // Create a task to simulate sending multiple messages
        activeTasks.append(Task {
            try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second delay
            for i in 1...messageCount {
                try await socket.send("Message \(i)")
                print("sent \(i)")
            }
        })
        
        // Receive messages concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 1...messageCount {
                group.addTask { @Sendable in
                    let message = try await socket.receive()
                    if case .string(let text) = message {
                        receivedMessages.modify { $0.append(text) }
                    }
                }
            }
            
            try await group.waitForAll()
        }
        
        // Verify we received all messages
        XCTAssertEqual(receivedMessages.value.count, messageCount)
        for i in 1...messageCount {
            XCTAssertTrue(receivedMessages.value.contains("Message \(i)"))
        }
        
        // Clean up
        try await socket.close()
    }
    
    func testReceiveDecodable() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        struct TestMessage: Codable, Sendable {
            let id: UUID
            let text: String
        }
        
        let testMessage = TestMessage(id: UUID(), text: "Hello")
        let jsonData = try JSONEncoder().encode(testMessage)
        
        // Create a task to simulate receiving a message
        activeTasks.append(Task {
            try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second delay
            try await socket.send(jsonData)
        })
        
        // Test receiving a decoded message
        let received = try await socket.receive(type: TestMessage.self)
        XCTAssertEqual(received.text, testMessage.text)
        XCTAssertEqual(received.id, testMessage.id)
        
        // Clean up
        try await socket.close()
    }
    
    func testReceiveDecodableConcurrent() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        struct TestMessage: Codable, Sendable {
            let id: Int
            let text: String
        }
        
        let messageCount = 5
        let receivedMessages: Lock<[TestMessage]> = Lock([])
        
        // Create a task to simulate sending multiple messages
        activeTasks.append(Task {
            try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second delay
            for i in 1...messageCount {
                let message = TestMessage(id: i, text: "Message \(i)")
                let data = try JSONEncoder().encode(message)
                print("sending \(i)")
                try await socket.send(data)
                print("sent \(i)")
            }
        })
        
        // Receive messages concurrently
        try await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 1...messageCount {
                group.addTask {
                    print("listening")
                    let message = try await socket.receive(type: TestMessage.self)
                    receivedMessages.modify { $0.append(message) }
                    print("received!")
                }
            }
            
            try await group.waitForAll()
        }
        
        // Verify we received all messages
        XCTAssertEqual(receivedMessages.value.count, messageCount)
        for i in 1...messageCount {
            XCTAssertTrue(receivedMessages.value.contains { $0.id == i && $0.text == "Message \(i)" })
        }
        
        // Clean up
        try await socket.close()
    }
    
    func testMessagesSequence() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        let messageCount = 3
        var receivedCount = 0
        
        // Create a task to simulate sending multiple messages
        activeTasks.append(Task {
            for i in 1...messageCount {
                try? await socket.send("Message \(i)")
            }
        })
        
        // Test receiving messages through AsyncSequence
        for try await message in socket.messages() {
            switch message {
            case .string(let text):
                receivedCount += 1
                XCTAssertEqual(text, "Message \(receivedCount)")
            case .data:
                XCTFail("Expected string message")
            }
            
            if receivedCount == messageCount {
                break
            }
        }
        
        XCTAssertEqual(receivedCount, messageCount)
        try await socket.close()
        print("test done.")
    }
    
    func testMessagesSequenceConcurrent() async throws {
        // Create multiple sockets
        let socketCount = 3
        let sockets = (0..<socketCount).map { _ in
            Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        }
        
        // Connect all sockets
        for socket in sockets {
            try await socket.connect()
        }
        
        let countLock = Lock<[Int]>([0, 0, 0])
        
        activeTasks.append(Task {
            for i in 0..<3 {
                for j in 0..<3 {
                    try? await sockets[j].send("\(i):\(j)")
                }
            }
        })

        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<3 {
                var count = 0
                group.addTask {
                    for try await message in sockets[i].messages() {
                        guard case let .string(str) = message else {
                            return
                        }
                        let messageArr = str.split(separator: ":")
                        count += 1
                        countLock.modify { count in
                            XCTAssertEqual(Int(String(messageArr[1])), i)
                            count[i] += 1
                        }
                        if count == 3 { break }
                    }
                }
            }
            try await group.waitForAll()
        }
        
        XCTAssertEqual(countLock.value, [3, 3, 3])
        
        for socket in sockets {
            try await socket.close()
        }
        
        // Clean up
        for socket in sockets {
            try await socket.close()
        }
    }
    
    func testTypedMessagesSequence() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        struct TestMessage: Codable, Sendable {
            let id: Int
            let text: String
        }
        
        let messageCount = 3
        var receivedCount = 0
        
        // Create a task to simulate sending multiple messages
        activeTasks.append(Task {
            try await Task.sleep(nanoseconds: 1_000_000_000)  // 1 second delay
            for i in 0..<messageCount {
                let message = TestMessage(id: i, text: "Message \(i)")
                let data = try? JSONEncoder().encode(message)
                try? await socket.send(data!)
                print("Sent message \(i)")
            }
            try await Task.sleep(nanoseconds: 10_000_000_000)
            try await socket.close()
        })
        
        // Test receiving typed messages through AsyncSequence
        for try await message in socket.messages(ofType: TestMessage.self) {
            print("received message \(message.id)")
            XCTAssertEqual(message.id, receivedCount)
            XCTAssertEqual(message.text, "Message \(receivedCount)")
            receivedCount += 1
            if receivedCount == messageCount {
                break
            }
        }
        
        XCTAssertEqual(receivedCount, messageCount)
    }
    
    func testTypedMessagesSequenceConcurrent() async throws {
        // Create multiple sockets
        let socketCount = 3
        let sockets = (0..<socketCount).map { _ in
            Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        }
        
        // Connect all sockets
        for socket in sockets {
            try await socket.connect()
        }

        let countLock = Lock<[Int]>([0, 0, 0])
        
        activeTasks.append(Task {
            for socket in sockets {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                try await socket.close()
            }
        })
        
        struct TestMessage: Codable, Sendable {
            let socketId: Int
            let messageId: Int
            let text: String
        }
        
        // Create tasks to send messages to each socket
        activeTasks.append(Task {
            for i in 0..<3 {
                for j in 0..<3 {
                    let message = TestMessage(socketId: j, messageId: i, text: "Message \(i)")
                    let data = try? JSONEncoder().encode(message)
                    try await sockets[j].send(data!)
                }
            }
        })
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for i in 0..<3 {
                var count = 0
                group.addTask {
                    for try await message in  sockets[i].messages(ofType: TestMessage.self) {
                        count += 1
                        countLock.modify { count in
                            XCTAssertEqual(message.socketId, i)
                            count[i] += 1
                        }
                        if count == 3 { break }
                    }
                }
            }
            try await group.waitForAll()
        }
        
        XCTAssertEqual(countLock.value, [3, 3, 3])
        
        for socket in sockets {
            try await socket.close()
        }
    }
    
    func testReceiveFailsWhenNotConnected() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        
        do {
            _ = try await socket.receive()
            XCTFail("Expected receive to fail when not connected")
        } catch {
            XCTAssertTrue(error is SocketError)
        }
        
        // Clean up
        try await socket.close()
    }
    
    func testReceiveFailsWhenNotConnectedConcurrent() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        
        // Try multiple receives concurrently without connecting
        await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 1...5 {
                let localSocket = socket // Capture socket in local constant
                group.addTask {
                    do {
                        _ = try await localSocket.receive()
                        XCTFail("Expected receive to fail when not connected")
                    } catch {
                        XCTAssertTrue(error is SocketError)
                    }
                }
            }
        }
        
        // Clean up
        try await socket.close()
    }
    
    func testReceiveFailsAfterClose() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        try await socket.close()
        
        do {
            _ = try await socket.receive()
            XCTFail("Expected receive to fail after close")
        } catch {
            XCTAssertTrue(error is SocketError)
        }
    }
    
    func testReceiveFailsAfterCloseConcurrent() async throws {
        let socket = Socket(host: self.localhost, port: self.serverport, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        try await socket.close()
        
        // Try multiple receives concurrently after closing
        await withThrowingTaskGroup(of: Void.self) { group in
            for _ in 1...5 {
                let localSocket = socket // Capture socket in local constant
                group.addTask {
                    do {
                        _ = try await localSocket.receive()
                        XCTFail("Expected receive to fail after close")
                    } catch {
                        XCTAssertTrue(error is SocketError)
                    }
                }
            }
        }
    }
}

