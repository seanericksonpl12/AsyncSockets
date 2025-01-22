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
    var defaultUrl: URL!
    
    override func setUp() {
        super.setUp()
        self.defaultUrl = URL(string: "ws://localhost:8000")
        self.activeTasks = []
    }
    
    override func tearDown() {
        self.activeTasks.forEach {
            $0.cancel()
        }
        self.activeTasks = nil
        self.defaultUrl = nil
        super.tearDown()
    }
}
