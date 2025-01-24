//
//  AsyncSocketsTestCase.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/22/25.
//

import Foundation
import XCTest

class AsyncSocketsTestCase: XCTestCase {
    
    var activeTasks: [Task<Void, Error>]!
    var localhost: String!
    var serverport: UInt16!
    var server: Server!
    
    override func setUp() async throws {
        try await super.setUp()
        
        self.activeTasks = []
        self.localhost = "localhost"
        self.serverport = 8000
        self.server = try Server(port: serverport)
        try await server.start()
    }
    
    override func tearDown() async throws {
        self.activeTasks.forEach {
            $0.cancel()
        }
        self.activeTasks = nil
        self.localhost = nil
        self.serverport = nil
        try await self.server.stop()
        self.server = nil
        try await super.tearDown()
    }
}
