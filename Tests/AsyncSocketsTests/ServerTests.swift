//
//  ServerTests.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/22/25.
//

import XCTest
@testable import AsyncSockets

final class ServerTests: XCTestCase {
    
    var server: Server!
    
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
    
    func testSingleTextMessage() async throws {
        try await self.server.start()
        let socket = Socket(host: "localhost", port: 8000, options: .init(allowInsecureConnections: true))
        try await socket?.connect()
        
        Task {
            try await socket?.send("test")
        }
        
        if case let .string(message) = try await socket?.receive() {
            XCTAssertEqual(message, "test")
        } else {
            XCTFail()
        }
    }
    
    func testSingleDataMessage() async throws {
        try await self.server.start()
        let socket = Socket(host: "localhost", port: 8000, options: .init(allowInsecureConnections: true))
        try await socket?.connect()
        
        Task {
            let data = "test".data(using: .utf8)!
            try await socket?.send(data)
        }
        
        if case let .data(data) = try await socket?.receive(), let message = String(data: data, encoding: .utf8) {
            XCTAssertEqual(message, "test")
        } else {
            XCTFail()
        }
    }
    
    func testSinglePing() async throws {
        try await self.server.start()
        let socket = Socket(host: "localhost", port: 8000, options: .init(allowInsecureConnections: true))
        try await socket?.connect()
        
        Task {
            let data = "test".data(using: .utf8)!
            try await socket?.ping()
        }
        

    }
}
