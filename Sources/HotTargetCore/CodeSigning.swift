import Foundation
import Security

public enum CodeSigningRequirementError: Error, Equatable, Sendable {
    case invalidIdentifier
    case invalidTeamID
}

public struct CodeSigningRequirement: Equatable, Sendable {
    public let text: String

    public init(identifier: String, teamID: String) throws {
        guard identifier.range(of: #"^[A-Za-z0-9.-]+$"#, options: .regularExpression) != nil else {
            throw CodeSigningRequirementError.invalidIdentifier
        }
        guard teamID.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil else {
            throw CodeSigningRequirementError.invalidTeamID
        }
        text = "anchor apple generic and identifier \"\(identifier)\" and certificate leaf[subject.OU] = \"\(teamID)\""
    }
}

public enum CurrentCodeSignatureError: Error, Equatable, Sendable {
    case copySelfFailed(OSStatus)
    case codeInvalid(OSStatus)
    case copyStaticCodeFailed(OSStatus)
    case copySigningInformationFailed(OSStatus)
    case missingSigningInformation
    case missingTeamIdentifier
    case invalidTeamIdentifier
}

public enum CurrentCodeSignature {
    public static func teamIdentifier() throws -> String {
        var currentCode: SecCode?
        let copySelfStatus = SecCodeCopySelf([], &currentCode)
        guard copySelfStatus == errSecSuccess, let currentCode else {
            throw CurrentCodeSignatureError.copySelfFailed(copySelfStatus)
        }

        let validityStatus = SecCodeCheckValidity(currentCode, [], nil)
        guard validityStatus == errSecSuccess else {
            throw CurrentCodeSignatureError.codeInvalid(validityStatus)
        }

        var staticCode: SecStaticCode?
        let staticStatus = SecCodeCopyStaticCode(currentCode, [], &staticCode)
        guard staticStatus == errSecSuccess, let staticCode else {
            throw CurrentCodeSignatureError.copyStaticCodeFailed(staticStatus)
        }

        var signingInformation: CFDictionary?
        let signingStatus = SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &signingInformation
        )
        guard signingStatus == errSecSuccess else {
            throw CurrentCodeSignatureError.copySigningInformationFailed(signingStatus)
        }
        guard let information = signingInformation as? [String: Any] else {
            throw CurrentCodeSignatureError.missingSigningInformation
        }
        guard let teamID = information[kSecCodeInfoTeamIdentifier as String] as? String else {
            throw CurrentCodeSignatureError.missingTeamIdentifier
        }
        guard teamID.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil else {
            throw CurrentCodeSignatureError.invalidTeamIdentifier
        }
        return teamID
    }
}
