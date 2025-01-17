//
//  HashableCheckedContinuation.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/17/25.
//

import Foundation

struct HashableCheckedContinuation<Element, Failure: Error>: Hashable {
    
    let id = UUID()
    let continuation: CheckedContinuation<Element, Failure>
    
    static func == (lhs: HashableCheckedContinuation<Element, Failure>, rhs: HashableCheckedContinuation<Element, Failure>) -> Bool {
        lhs.id == rhs.id
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
