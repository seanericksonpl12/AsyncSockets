//
//  Weak.swift
//  PhoenixSockets
//
//  Created by Sean Erickson on 1/11/25.
//

extension Weak : Sendable where Value: Sendable {}

struct Weak<Value: AnyObject> {
    weak var value: Value?
}
