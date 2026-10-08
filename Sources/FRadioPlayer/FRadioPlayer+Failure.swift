//
//  FRadioPlayer+Failure.swift
//  FRadioPlayer
//
//  Classification of the failure behind the `.error` state, so a host can
//  tell a transient network problem from a stream that is gone.
//

import AVFoundation

public extension FRadioPlayer {

    /// Why playback failed. Delivered by `radioPlayer(_:didFail:)` just
    /// before the `.error` state, and kept in `lastFailure`. Since 0.5.0.
    struct Failure: Sendable, Equatable {

        public enum Kind: Sendable {
            /// HTTP 404/410, or a missing local file
            case notFound
            /// HTTP 403, or no permission to read a local file
            case forbidden
            /// HTTP 401/407, or authentication or authorization required
            case unauthorized
            /// No connection, connection lost, host unreachable, HTTP 5xx
            case network
            /// The request or connection timed out (HTTP 408/504 included)
            case timeout
            /// The data arrived but could not be parsed or decoded
            case decode
            /// The built-in recovery ladder (`RecoveryPolicy.automatic`)
            /// gave up on a stall
            case stalledExhausted
            /// Anything not recognised above
            case unknown
        }

        public let kind: Kind
        /// Domain of the reported error (the item error, else the last
        /// error-log event), `"FRadioPlayer"` for library failures
        public let domain: String
        /// Code of the reported error, matching `domain`
        public let code: Int
        /// HTTP status, when the error or the error log carries one
        public let httpStatus: Int?
        /// Human-readable description, for logs
        public let message: String

        public init(kind: Kind, domain: String, code: Int, httpStatus: Int?, message: String) {
            self.kind = kind
            self.domain = domain
            self.code = code
            self.httpStatus = httpStatus
            self.message = message
        }
    }
}

// MARK: - Classification

extension FRadioPlayer {

    /// The fields of an `AVPlayerItemErrorLogEvent` the classifier reads,
    /// as a value so tests can supply them
    struct ErrorLogEntry: Sendable, Equatable {
        let statusCode: Int
        let domain: String
        let comment: String?

        init(statusCode: Int, domain: String, comment: String?) {
            self.statusCode = statusCode
            self.domain = domain
            self.comment = comment
        }

        init(_ event: AVPlayerItemErrorLogEvent) {
            self.init(statusCode: event.errorStatusCode, domain: event.errorDomain, comment: event.errorComment)
        }
    }
}

extension FRadioPlayer.Failure {

    static let libraryDomain = "FRadioPlayer"

    static func stalledExhausted(attempts: Int) -> Self {
        Self(kind: .stalledExhausted, domain: libraryDomain, code: 1, httpStatus: nil,
             message: "Stall recovery gave up after \(attempts) attempts")
    }

    /// Classifies a failed item. An HTTP status (from the error log, else
    /// from the error chain's text) decides first; otherwise the first
    /// recognised error in the chain, from the reported error down through
    /// `NSUnderlyingErrorKey`.
    static func classify(error: Error?, errorLog: FRadioPlayer.ErrorLogEntry?) -> Self {
        let chain = errorChain(error)
        let status = errorLog.flatMap(httpStatus(in:)) ?? chain.lazy.compactMap(httpStatus(in:)).first

        let kind = status.flatMap(kind(forHTTPStatus:))
            ?? chain.lazy.compactMap(kind(for:)).first
            ?? .unknown

        if let top = chain.first {
            return Self(kind: kind, domain: top.domain, code: top.code, httpStatus: status, message: top.localizedDescription)
        }
        if let log = errorLog {
            return Self(kind: kind, domain: log.domain, code: log.statusCode, httpStatus: status,
                        message: log.comment ?? "Playback failed (\(log.domain) \(log.statusCode))")
        }
        return Self(kind: kind, domain: libraryDomain, code: 0, httpStatus: nil, message: "Playback failed")
    }

    private static func errorChain(_ error: Error?) -> [NSError] {
        var chain: [NSError] = []
        var next = error.map { $0 as NSError }
        while let current = next, chain.count < 8 {
            chain.append(current)
            next = current.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return chain
    }

    private static func httpStatus(in entry: FRadioPlayer.ErrorLogEntry) -> Int? {
        if (400...599).contains(entry.statusCode) { return entry.statusCode }
        return entry.comment.flatMap(httpStatus(inText:))
    }

    private static func httpStatus(in error: NSError) -> Int? {
        let texts = [error.localizedDescription, error.localizedFailureReason].compactMap { $0 }
        return texts.lazy.compactMap(httpStatus(inText:)).first
    }

    /// Finds "HTTP 404" style statuses, the form CoreMedia uses
    private static func httpStatus(inText text: String) -> Int? {
        guard let range = text.range(of: #"HTTP (\d{3})"#, options: .regularExpression) else { return nil }
        let code = Int(text[range].dropFirst(5))
        return code.flatMap { (400...599).contains($0) ? $0 : nil }
    }

    private static func kind(forHTTPStatus status: Int) -> Kind? {
        switch status {
        case 404, 410: return .notFound
        case 403: return .forbidden
        case 401, 407: return .unauthorized
        case 408, 504: return .timeout
        case 500...599: return .network
        default: return nil
        }
    }

    private static func kind(for error: NSError) -> Kind? {
        switch error.domain {
        case NSURLErrorDomain:
            switch error.code {
            case NSURLErrorTimedOut:
                return .timeout
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost,
                 NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed,
                 NSURLErrorInternationalRoamingOff, NSURLErrorCallIsActive, NSURLErrorDataNotAllowed,
                 NSURLErrorSecureConnectionFailed, NSURLErrorBadServerResponse, NSURLErrorResourceUnavailable:
                return .network
            case NSURLErrorFileDoesNotExist:
                return .notFound
            case NSURLErrorNoPermissionsToReadFile:
                return .forbidden
            case NSURLErrorUserAuthenticationRequired, NSURLErrorUserCancelledAuthentication:
                return .unauthorized
            case NSURLErrorCannotDecodeContentData, NSURLErrorCannotDecodeRawData, NSURLErrorCannotParseResponse:
                return .decode
            default:
                return nil
            }
        case AVFoundationErrorDomain:
            switch AVError.Code(rawValue: error.code) {
            case .decodeFailed, .fileFormatNotRecognized, .failedToParse, .undecodableMediaData, .decoderNotFound:
                return .decode
            case .contentIsNotAuthorized:
                return .unauthorized
            default:
                return nil
            }
        case NSCocoaErrorDomain:
            switch error.code {
            case NSFileReadNoSuchFileError, NSFileNoSuchFileError:
                return .notFound
            case NSFileReadNoPermissionError:
                return .forbidden
            default:
                return nil
            }
        case NSPOSIXErrorDomain:
            switch Int32(truncatingIfNeeded: error.code) {
            case ENOENT: return .notFound
            case EACCES, EPERM: return .forbidden
            case ETIMEDOUT: return .timeout
            case ECONNREFUSED, ECONNRESET, ENETDOWN, ENETUNREACH, EHOSTUNREACH, EHOSTDOWN, ENOTCONN:
                return .network
            default: return nil
            }
        default:
            return nil
        }
    }
}
