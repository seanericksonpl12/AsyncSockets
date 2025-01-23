//
//  ServerTests.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/22/25.
//

import XCTest
@testable import AsyncSockets

final class ServerTests: AsyncSocketsTestCase {
    
    override func setUp() async throws {
        try await super.setUp()
        self.server = try Server(port: 8000)
    }
    
    override func tearDown() async throws {
        try await self.server.stop()
        self.server = nil
        try await super.tearDown()
    }
    
    func testStart() async throws {
        try await server.start()
        try await server.stop()
    }
    
    func testConnect() async throws {
        try await self.server.start()
        let socket = Socket(host: "localhost", port: 8000, options: .init(allowInsecureConnections: true))
        try await socket.connect()
    }
    
    func testMultipleConnect() async throws {
        try await self.server.start()
        let socketCount = 10
        let sockets = (0..<socketCount).map { _ in
            Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        }
        for socket in sockets {
            try await socket.connect()
        }
        
        for socket in sockets {
            XCTAssertEqual(socket.state, .connected)
        }
    }
    
    func testConnectConcurrent() async throws {
        try await self.server.start()
        let socketCount = 10
        let sockets = (0..<socketCount).map { _ in
            Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        }
        try await withThrowingTaskGroup(of: Void.self) { group in
            for socket in sockets {
                group.addTask {
                    try await socket.connect()
                }
            }
            try await group.waitForAll()
        }
        
        for socket in sockets {
            XCTAssertEqual(socket.state, .connected)
        }
    }
    
    func testSingleTextMessage() async throws {
        try await self.server.start()
        let socket = Socket(host: "localhost", port: 8000, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        activeTasks.append(Task {
            try await socket.send("test")
        })
        
        if case let .string(message) = try await socket.receive() {
            XCTAssertEqual(message, "test")
        } else {
            XCTFail()
        }
    }
    
    func testSingleDataMessage() async throws {
        try await self.server.start()
        let socket = Socket(host: "localhost", port: 8000, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        
        activeTasks.append(Task {
            let data = "test".data(using: .utf8)!
            try await socket.send(data)
        })
        
        if case let .data(data) = try await socket.receive(), let message = String(data: data, encoding: .utf8) {
            XCTAssertEqual(message, "test")
        } else {
            XCTFail()
        }
    }
    
    func testSinglePing() async throws {
        try await self.server.start()
        let socket = Socket(host: "localhost", port: 8000, options: .init(allowInsecureConnections: true))
        let expectation = XCTestExpectation(description: "Pong received")
        
        try await socket.connect()
        activeTasks.append(Task { for try await _ in socket.messages() {} })
        activeTasks.append(Task {
            for await event in socket.events() {
                print(event)
                if case .pong = event {
                    expectation.fulfill()
                }
            }
        })
        
        try await socket.ping()
        
        await fulfillment(of: [expectation], timeout: 2.0)
    }
    
    func testConcurrentSingleTextMessage() async throws {
        try await self.server.start()
        let socketCount = 10
        let sockets = (0..<socketCount).map { _ in
            Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        }
        for socket in sockets {
            try await socket.connect()
        }
        
        activeTasks.append(Task {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, socket) in sockets.enumerated() {
                    group.addTask {
                        try await socket.send("\(index)")
                    }
                }
                try await group.waitForAll()
            }
        })
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, socket) in sockets.enumerated() {
                group.addTask {
                    if case let .string(message) = try await socket.receive() {
                        XCTAssertEqual(message, "\(index)")
                    } else {
                        XCTFail()
                    }
                }
            }
            try await group.waitForAll()
        }
    }
    
    func testConcurrentSingleDataMessage() async throws {
        try await self.server.start()
        let socketCount = 10
        let sockets = (0..<socketCount).map { _ in
            Socket(url: URL(string: "ws://localhost:8000")!, options: .init(allowInsecureConnections: true))
        }
        for socket in sockets {
            try await socket.connect()
        }
        
        activeTasks.append(Task {
            try await withThrowingTaskGroup(of: Void.self) { group in
                for (index, socket) in sockets.enumerated() {
                    group.addTask {
                        let data = "test".data(using: .utf8)!
                        try await socket.send(data)
                    }
                }
                try await group.waitForAll()
            }
        })
        
        try await withThrowingTaskGroup(of: Void.self) { group in
            for (index, socket) in sockets.enumerated() {
                group.addTask {
                    if case let .data(data) = try await socket.receive(), let message = String(data: data, encoding: .utf8) {
                        XCTAssertEqual(message, "test")
                    } else {
                        XCTFail()
                    }
                }
            }
            try await group.waitForAll()
        }
    }
    
    func testMultipleTextMessage() async throws {
        try await self.server.start()
        let socket = Socket(host: "localhost", port: 8000, options: .init(allowInsecureConnections: true))
        try await socket.connect()
        var count = 0
        
        activeTasks.append(Task {
            for i in 0..<20 {
                try await socket.send("\(i)")
                print("sent \(i)")
            }
        })
        
        activeTasks.append(Task {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            XCTFail("Timeout")
        })
        
        for try await message in socket.messages() {
            count += 1
            if case let .string(string) = message {
                print("received: \(string)")
                if string == "19" {
                    break
                }
            }
        }
        
        XCTAssertEqual(count, 20)
    }
}
