//
// Wire
// Copyright (C) 2018 Wire Swiss GmbH
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program. If not, see http://www.gnu.org/licenses/.
//

import Foundation

/**
 * Errors that can occur within the company login flow.
 */

public enum CompanyLoginError: String {

    case unknownLabel = "0"
    case missingRequiredParameter = "-2063"
    case invalidCookie = "-67700"
    case tokenNotFound = "-25346"

    // MARK: - SAML

    case unknownIdP = "server_error_SAML.UnknownIdP"
    case forbidden = "server_error_SAML.Forbidden"
    case badSAMLResponse = "server_error_SAML.BadSamlResponse"
    case badServerConfig = "server_error_SAML.BadServerConfig"
    case unknownError = "server_error_SAML.UnknownError"
    case customServant = "server_error_SAML.CustomServant"
    case sparNotFound = "server_error_SAML.SparNotFound"
    case sparNotInTeam = "server_error_SAML.SparNotInTeam"
    case sparNotTeamOwner = "server_error_SAML.SparNotTeamOwner"
    case sparNoRequestRefInResponse = "server_error_SAML.SparNoRequestRefInResponse"
    case sparCouldNotSubstituteSuccessURI = "server_error_SAML.SparCouldNotSubstituteSuccessURI"
    case sparCouldNotSubstituteFailureURI = "server_error_SAML.SparCouldNotSubstituteFailureURI"
    case sparBadInitiateLoginQueryParams = "server_error_SAML.SparBadInitiateLoginQueryParams"
    case sparBadUserName = "server_error_SAML.SparBadUserName"
    case sparNoBodyInBrigResponse = "server_error_SAML.SparNoBodyInBrigResponse"
    case sparCouldNotParseBrigResponse = "server_error_SAML.SparCouldNotParseBrigResponse"
    case sparCouldNotRetrieveCookie = "server_error_SAML.SparCouldNotRetrieveCookie"
    case sparCassandraError = "server_error_SAML.SparCassandraError"
    case sparNewIdPBadMetaUrl = "server_error_SAML.SparNewIdPBadMetaUrl"
    case sparNewIdPBadMetaSig = "server_error_SAML.SparNewIdPBadMetaSig"
    case sparNewIdPBadReqUrl = "server_error_SAML.SparNewIdPBadReqUrl"
    case sparNewIdPPubkeyMismatch = "server_error_SAML.SparNewIdPPubkeyMismatch"

    // MARK: - Metadata

    /// Parses the error label, or fallbacks to the default error if it is not known.
    init(label: String) {
        self = CompanyLoginError(rawValue: label) ?? .unknownLabel
    }

    /// The code to display to the user inside alerts.
    public var displayCode: String {
        switch self {
        case .unknownLabel, .missingRequiredParameter, .invalidCookie, .tokenNotFound:
            return rawValue

        case .unknownIdP: return "1"
        case .forbidden: return "2"
        case .badSAMLResponse: return "3"
        case .badServerConfig: return "4"
        case .unknownError: return "5"
        case .customServant: return "6"
        case .sparNotFound: return "7"
        case .sparNotInTeam: return "8"
        case .sparNotTeamOwner: return "9"
        case .sparNoRequestRefInResponse: return "10"
        case .sparCouldNotSubstituteSuccessURI: return "11"
        case .sparCouldNotSubstituteFailureURI: return "12"
        case .sparBadInitiateLoginQueryParams: return "13"
        case .sparBadUserName: return "14"
        case .sparNoBodyInBrigResponse: return "15"
        case .sparCouldNotParseBrigResponse: return "16"
        case .sparCouldNotRetrieveCookie: return "17"
        case .sparCassandraError: return "18"
        case .sparNewIdPBadMetaUrl: return "19"
        case .sparNewIdPBadMetaSig: return "20"
        case .sparNewIdPBadReqUrl: return "21"
        case .sparNewIdPPubkeyMismatch: return "22"
        }
    }

}
