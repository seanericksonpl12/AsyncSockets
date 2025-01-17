//
//  SocketError.swift
//  AsyncSockets
//
//  Created by Sean Erickson on 1/15/25.
//

import Foundation
import Network

/// An Error enum to wrap all types of errors thrown from AsyncSockets.
///
/// SocketError wraps Network and Foundation error types, rather than
/// providing an entirely custom error implementation, mainly to allow
/// easy porting of any existing error handling code for both NSError
/// and NWError.
///
/// SocketError does also provide a Domain and Error Code for error
/// handling, however this is a custom AsyncSocket Domain and code,
/// created by mapping the information from NSErrors, NWErrors, and
/// WSErrors.
///
/// Basically an attempt at the _best of both worlds_ between NSErrors
/// and the modern enumeration style
public enum SocketError: Error {
    
    /// A wrapper around NWErrors thrown from the Network Library.
    case nwError(NWError)
    
    /// A wrapper around NSErrors thrown from the Foundation Library.
    case nsError(NSError)
    
    /// A wrapper around WSErrors thrown directly from the AsyncSockets Library.
    case wsError(WSError)
    
    /// The localizedDescription of this error
    public var localizedDescription: String {
        switch self {
        case .nwError(let nwError):
            nwError.localizedDescription
        case .nsError(let nsError):
            nsError.localizedDescription
        case .wsError(let wsError):
            wsError.localizedDescription
        }
    }
    
    public var domain: SocketErrorDomain? {
        switch self {
        case .nwError(let nwError):
            switch nwError {
            case .posix:
                return .POSIXErrorDomain
            case .dns:
                return .DNSErrorDomain
            case .tls:
                return .OSStatusErrorDomain
            @unknown default:
                return nil
            }
        case .nsError(let nsError):
            if let domain = SocketErrorDomain(rawValue: nsError.domain) {
                return domain
            }
            switch nsError.domain {
            case NSPOSIXErrorDomain:
                return .POSIXErrorDomain
            case NSOSStatusErrorDomain:
                return .OSStatusErrorDomain
            default:
                return nil
            }
        case .wsError(let wsError):
            return SocketErrorDomain(rawValue: wsError.domain.rawValue)
        }
    }
    
    public var code: Int? {
        switch self {
        case .nwError(let nwError):
            switch nwError {
            case .posix(let pOSIXErrorCode):
                return Int(pOSIXErrorCode.rawValue)
            case .dns(let dNSServiceErrorType):
                return Int(dNSServiceErrorType)
            case .tls(let oSStatus):
                return Int(oSStatus)
            @unknown default:
                return nil
            }
        case .nsError(let nsError):
            return nsError.code
        case .wsError(let wsError):
            return wsError.code.rawValue
        }
    }
    
    init?(_ error: Error?) {
        guard let error else { return nil }
        self.init(error)
    }
    
    init(_ error: Error) {
        if let nwError = error as? NWError {
            self = .nwError(nwError)
        } else if let wsError = error as? WSError {
            self = .wsError(wsError)
        } else {
            self = .nsError(error as NSError)
        }
    }
}

public enum SocketErrorDomain: String, Sendable {
    case POSIXErrorDomain
    case OSStatusErrorDomain
    case DNSErrorDomain
    case NSCocoaErrorDomain
    case NSMachErrorDomain
    case NSStreamSOCKSErrorDomain
    case NSStreamSocketSSLErrorDomain
    case WSConnectionDomain
    case WSDataDomain
}

public struct WSError: Error, @unchecked Sendable {
    public let domain: WSErrorDomain
    public let code: WSErrorCode
    public let userInfo: [String: Any]
    
    public var description: String {
        var description = "\(domain) Error - \(codeString)"
        if !userInfo.isEmpty {
            description.append("\(userInfo)")
        }
        return description
    }
    
    var codeString: String {
        switch self.code {
        case .invalidConnectionAccess:
            "Attempting to connect while connect is already running"
        case .socketNotConnected:
            "Socket is not connected"
        case .connectionNotReady:
            "Connection is not ready for data"
        case .failedToEncode:
            "Failed to encode the string as data"
        case .disconnectFailed:
            "Failed to disconnect the socket"
        case .connectFailed:
            "Failed to connect to the socket for an unknown reason"
        case .failedToDecode:
            "Failed to decode the received data"
        }
    }
    
    init(domain: WSErrorDomain, code: WSErrorCode, userInfo: [String : Any] = [:]) {
        self.domain = domain
        self.code = code
        self.userInfo = userInfo
    }
}

public enum WSErrorDomain: String, Sendable {
    case WSConnectionDomain
    case WSDataDomain
}

public enum WSErrorCode: Int, Sendable {
    // MARK: - WSConnectionDomain
    case invalidConnectionAccess = 5001
    case socketNotConnected = 5002
    case connectionNotReady = 5003
    case disconnectFailed = 5004
    case connectFailed = 5005
    
    // MARK: - WSDataDomain
    case failedToEncode = 5006
    case failedToDecode = 5007
}
