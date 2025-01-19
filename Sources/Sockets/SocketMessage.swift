//
//  SocketMessage.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/14/25.
//
import Foundation

/// Message received from a SocketConnection, either as a `String` or binary `Data`
public enum SocketMessage: Sendable, Decodable {
    case string(String)
    case data(Data)
}
