//
//  HeartbeatManager.swift
//  PhoenixSockets
//
//  Created by Sean Erickson on 1/10/25.
//

import Foundation

protocol HeartbeatDelegate: AnyObject, Sendable {
    func sendHeartbeat() async throws
    func heartbeatMissed() async
}

actor HeartbeatManager {
    
    enum Status: Sendable {
        case notStarted, received, waiting
    }
    
    private(set) var isRunning: Bool = false
    private(set) var heartbeatStatus = Status.notStarted
    
    private let mainTask: Lock<Task<Void, Never>?> = Lock(nil)
    private let receivedTask: Lock<Task<Void, Never>?> = Lock(nil)
    private let delegateLock = NSLock()
    nonisolated(unsafe) private weak var delegate: HeartbeatDelegate?
    
    init(delegate: HeartbeatDelegate) {
        self.delegate = delegate
    }

    deinit {
        self.mainTask.modify { $0?.cancel() }
        self.receivedTask.modify { $0?.cancel() }
    }
    
    func start(
        interval: TimeInterval,
        repeats: Bool = true
    ) {
        self.stop()
        self.mainTask.set(Task { [weak self] in
            guard let self = self else { return }
            await self.beat(interval: interval, repeats: repeats)
        })
    }
    
    public nonisolated func receivedHeartbeat() {
        // task delay means if you receive the heartbeat exactly at the timeinterval it won't count :(
        self.receivedTask.set( Task { await _receivedHeartbeat(.received) } )
    }
    
    private func _receivedHeartbeat(_ status: Status) {
        self.heartbeatStatus = status
    }
    
    nonisolated func stop() {
        self.mainTask.modify {
            $0?.cancel()
            $0 = nil
        }
    }
    
    func beat(interval: TimeInterval, repeats: Bool) async {
        self.isRunning = true
        defer { self.isRunning = false }
        
        while !Task.isCancelled {
            do {
                try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                guard !Task.isCancelled else { return }
                switch heartbeatStatus {
                case .notStarted, .received:
                    try await delegate?.sendHeartbeat()
                    self.heartbeatStatus = .waiting
                case .waiting:
                    await delegate?.heartbeatMissed()
                    return
                }
                
                if !repeats { break }
            } catch {
                return
            }
        }
    }
}
