//
//  Twitter+API+OAuth.swift
//  TwitterAPI
//
//  Created by Cirno MainasuK on 2020-9-1.
//

import os.log
import Foundation
import CryptoKit
import Combine

public protocol OAuthExchangeProvider: class {
    func oauthExcahnge() -> Twitter.API.OAuth.OAuthExchange
}

extension Twitter.API.OAuth {
    
    static let authorizeEndpointURL = URL(string: "https://api.twitter.com/oauth/authorize")!
    static let requestTokenEndpointURL = URL(string: "https://api.twitter.com/oauth/request_token")!
    
    public static func requestToken(session: URLSession, oauthExchangeProvider: OAuthExchangeProvider) -> AnyPublisher<OAuthRequestTokenExchange, Error> {
        let oauthExchange = oauthExchangeProvider.oauthExcahnge()
        switch oauthExchange {
        case .pin(let consumerKey, let consumerKeySecret):
            fatalError("TODO:")
//            let request = URLRequest(url: Twitter.API.OAuth.requestTokenEndpointURL, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: Twitter.API.timeoutInterval)
//            return session.dataTaskPublisher(for: request)
//                .tryMap { data, response -> OAuthRequestTokenExchange in
//                    try Twitter.API.decode(type: RequestTokenResponse.self, from: data, response: response)
//                }
//                .eraseToAnyPublisher()
            
        case .custom(let consumerKey, let hostPublicKey, let oauthEndpoint):
            os_log("%{public}s[%{public}ld], %{public}s: request token %s", ((#file as NSString).lastPathComponent), #line, #function, oauthEndpoint)

            let clientEphemeralPrivateKey = Curve25519.KeyAgreement.PrivateKey()
            let clientEphemeralPublicKey = clientEphemeralPrivateKey.publicKey
            do {
                let sharedSecret = try clientEphemeralPrivateKey.sharedSecretFromKeyAgreement(with: hostPublicKey)
                let salt = clientEphemeralPublicKey.rawRepresentation + sharedSecret.withUnsafeBytes { Data($0) }
                let wrapKey = sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("request token exchange".utf8), outputByteCount: 32)
                let consumerKeyBox = try ChaChaPoly.seal(Data(consumerKey.utf8), using: wrapKey)
                let requestTokenRequest = RequestTokenRequest(exchangePublicKey: clientEphemeralPublicKey, consumerKeyBox: consumerKeyBox)
                
                var request = URLRequest(url: URL(string: oauthEndpoint + "/oauth/request_token")!, cachePolicy: .reloadIgnoringLocalAndRemoteCacheData, timeoutInterval: Twitter.API.timeoutInterval)
                request.httpMethod = "POST"
                request.addValue("application/json; charset=UTF-8", forHTTPHeaderField: "Content-Type")
                request.httpBody = try JSONEncoder().encode(requestTokenRequest)

                return session.dataTaskPublisher(for: request)
                    .tryMap { data, _ -> OAuthRequestTokenExchange in
                        os_log("%{public}s[%{public}ld], %{public}s: request token response data: %s", ((#file as NSString).lastPathComponent), #line, #function, String(data: data, encoding: .utf8) ?? "<nil>")
                        let response = try JSONDecoder().decode(CustomRequestTokenResponse.self, from: data)
                        os_log("%{public}s[%{public}ld], %{public}s: request token response: %s", ((#file as NSString).lastPathComponent), #line, #function, String(describing: response))

                        guard let exchangePublicKeyData = Data(base64Encoded: response.exchangePublicKey),
                              let exchangePublicKey = try? Curve25519.KeyAgreement.PublicKey(rawRepresentation: exchangePublicKeyData),
                              let sharedSecret = try? clientEphemeralPrivateKey.sharedSecretFromKeyAgreement(with: exchangePublicKey),
                              let combinedData = Data(base64Encoded: response.requestTokenBox) else
                        {
                            throw Twitter.API.APIError.internal(message: "invalid requestToken response")
                        }
                        do {
                            let salt = exchangePublicKey.rawRepresentation + sharedSecret.withUnsafeBytes { Data($0) }
                            let wrapKey = sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("request token response exchange".utf8), outputByteCount: 32)
                            let sealedbox = try ChaChaPoly.SealedBox(combined: combinedData)
                            let requestTokenData = try ChaChaPoly.open(sealedbox, using: wrapKey)
                            guard let requestToken = String(data: requestTokenData, encoding: .utf8) else {
                                throw Twitter.API.APIError.internal(message: "invalid requestToken response")
                            }
                            let append = CustomRequestTokenResponseAppend(
                                requestToken: requestToken,
                                clientExchangePrivateKey: clientEphemeralPrivateKey,
                                hostExchangePublicKey: exchangePublicKey
                            )
                            return .customRequestTokenResponse(response, append: append)
                        } catch {
                            assertionFailure(error.localizedDescription)
                            throw Twitter.API.APIError.internal(message: "process requestToken response fail")
                        }
                    }
                    .eraseToAnyPublisher()
            } catch {
                assertionFailure(error.localizedDescription)
                return Fail(error: error).eraseToAnyPublisher()
            }
        }
    }
    
    public static func autenticateURL(requestToken: String) -> URL {
        var urlComponents = URLComponents(string: authorizeEndpointURL.absoluteString)!
        urlComponents.queryItems = [
            URLQueryItem(name: "oauth_token", value: requestToken),
        ]
        return urlComponents.url!
    }
    
}

extension Twitter.API.OAuth {
    
    public struct RequestTokenRequest: Codable {
        public let exchangePublicKey: String
        public let consumerKeyBox: String
        
        public enum CodingKeys: String, CodingKey {
            case exchangePublicKey = "exchange_public_key"
            case consumerKeyBox = "consumer_key_box"
        }

        init(exchangePublicKey: Curve25519.KeyAgreement.PublicKey, consumerKeyBox: ChaChaPoly.SealedBox) {
            self.exchangePublicKey = exchangePublicKey.rawRepresentation.base64EncodedString()
            self.consumerKeyBox = consumerKeyBox.combined.base64EncodedString()
        }
    }
    
    public struct RequestTokenResponse: Codable {
        public let oauthToken: String
        public let oauthTokenSecret: String
        public let oauthCallbackConfirmed: Bool
        
        public enum CodingKeys: String, CodingKey {
            case oauthToken = "oauth_token"
            case oauthTokenSecret = "oauth_token_secret"
            case oauthCallbackConfirmed = "oauth_callback_confirmed"
        }
    }
    
    public struct CustomRequestTokenResponse: Codable {
        let exchangePublicKey: String
        let requestTokenBox: String
                
        enum CodingKeys: String, CodingKey, CaseIterable {
            case exchangePublicKey = "exchange_public_key"
            case requestTokenBox = "request_token_box"
        }
    }
    
    public struct CustomRequestTokenResponseAppend {
        public let requestToken: String
        public let clientExchangePrivateKey: Curve25519.KeyAgreement.PrivateKey
        public let hostExchangePublicKey: Curve25519.KeyAgreement.PublicKey
    }
    
    public struct OAuthCallbackResponse: Codable {
        
        let exchangePublicKey: String
        let authenticationBox: String
        
        enum CodingKeys: String, CodingKey, CaseIterable {
            case exchangePublicKey = "exchange_public_key"
            case authenticationBox = "authentication_box"
        }
        
        public init?(callbackURL url: URL) {
            guard let urlComponents = URLComponents(string: url.absoluteString) else { return nil }
            guard let queryItems = urlComponents.queryItems,
                  let exchangePublicKey = queryItems.first(where: { $0.name == CodingKeys.exchangePublicKey.rawValue })?.value,
                  let authenticationBox = queryItems.first(where: { $0.name == CodingKeys.authenticationBox.rawValue })?.value else
            {
                return nil
            }
            self.exchangePublicKey = exchangePublicKey
            self.authenticationBox = authenticationBox
        }
        
        public func authentication(privateKey: Curve25519.KeyAgreement.PrivateKey) throws -> Authentication {
            do {
                guard let exchangePublicKeyData = Data(base64Encoded: exchangePublicKey),
                      let sealedBoxData = Data(base64Encoded: authenticationBox) else {
                    throw Twitter.API.APIError.internal(message: "invalid callback")
                }
                let exchangePublicKey = try Curve25519.KeyAgreement.PublicKey(rawRepresentation: exchangePublicKeyData)
                let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: exchangePublicKey)
                let salt = exchangePublicKey.rawRepresentation + sharedSecret.withUnsafeBytes { Data($0) }
                let wrapKey = sharedSecret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: salt, sharedInfo: Data("authentication exchange".utf8), outputByteCount: 32)
                let sealedBox = try ChaChaPoly.SealedBox(combined: sealedBoxData)
                
                let authenticationData = try ChaChaPoly.open(sealedBox, using: wrapKey)
                let authentication = try JSONDecoder().decode(Authentication.self, from: authenticationData)
                return authentication
                
            } catch {
                if let error = error as? Twitter.API.APIError {
                    throw error
                } else {
                    throw Twitter.API.APIError.internal(message: error.localizedDescription)
                }
            }
        }
        
    }
    
    public struct Authentication: Codable {
        public let accessToken: String
        public let accessTokenSecret: String
        public let userID: String
        public let screenName: String
        public let consumerKey: String
        public let consumerSecret: String
        
        public enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case accessTokenSecret = "access_token_secret"
            case userID = "uesr_id"
            case screenName = "screen_name"
            case consumerKey = "consumer_key"
            case consumerSecret = "consumer_secret"
        }
    }
    
    public struct Authorization {
        public let consumerKey: String
        public let consumerSecret: String
        public let accessToken: String
        public let accessTokenSecret: String
                
        public init(consumerKey: String, consumerSecret: String, accessToken: String, accessTokenSecret: String) {
            self.consumerKey = consumerKey
            self.consumerSecret = consumerSecret
            self.accessToken = accessToken
            self.accessTokenSecret = accessTokenSecret
        }
        
        func authorizationHeader(requestURL url: URL, httpMethod: String) -> String {
            return Twitter.API.OAuth.authorizationHeader(
                requestURL: url,
                httpMethod: httpMethod,
                callbackURL: nil,
                consumerKey: consumerKey,
                consumerSecret: consumerSecret,
                oauthToken: accessToken,
                oauthTokenSecret: accessTokenSecret
            )
        }
    }
    
}

extension Twitter.API.OAuth {
    
    static var authorizationField = "Authorization"
    
    static func authorizationHeader(requestURL url: URL, httpMethod: String, callbackURL: URL?, consumerKey: String, consumerSecret: String, oauthToken: String?, oauthTokenSecret: String?) -> String {
        var authorizationParameters = Dictionary<String, String>()
        authorizationParameters["oauth_version"] = "1.0"
        authorizationParameters["oauth_callback"] = callbackURL?.absoluteString
        authorizationParameters["oauth_consumer_key"] = consumerKey
        authorizationParameters["oauth_signature_method"] = "HMAC-SHA1"
        authorizationParameters["oauth_timestamp"] = String(Int(Date().timeIntervalSince1970))
        authorizationParameters["oauth_nonce"] = UUID().uuidString
        
        authorizationParameters["oauth_token"] = oauthToken
        
        authorizationParameters["oauth_signature"] = oauthSignature(requestURL: url, httpMethod: httpMethod, consumerSecret: consumerSecret, parameters: authorizationParameters, oauthTokenSecret: oauthTokenSecret)
        
        
        var parameterComponents = authorizationParameters.urlEncodedQuery.components(separatedBy: "&") as [String]
        parameterComponents.sort { $0 < $1 }
        
        var headerComponents = [String]()
        for component in parameterComponents {
            let subcomponent = component.components(separatedBy: "=") as [String]
            if subcomponent.count == 2 {
                headerComponents.append("\(subcomponent[0])=\"\(subcomponent[1])\"")
            }
        }
        
        return "OAuth " + headerComponents.joined(separator: ", ")
    }
    
    static func oauthSignature(requestURL url: URL, httpMethod: String, consumerSecret: String, parameters: Dictionary<String, String>, oauthTokenSecret: String?) -> String {
        let encodedConsumerSecret = consumerSecret.urlEncoded
        let encodedTokenSecret = oauthTokenSecret?.urlEncoded ?? ""
        let signingKey = "\(encodedConsumerSecret)&\(encodedTokenSecret)"
        
        var parameters = parameters
        
        var components = URLComponents(string: url.absoluteString)!
        for item in components.queryItems ?? [] {
            parameters[item.name] = item.value
        }
        components.queryItems = nil
        let baseURL = components.url!
        
        var parameterComponents = parameters.urlEncodedQuery.components(separatedBy: "&")
        parameterComponents.sort {
            let p0 = $0.components(separatedBy: "=")
            let p1 = $1.components(separatedBy: "=")
            if p0.first == p1.first { return p0.last ?? "" < p1.last ?? "" }
            return p0.first ?? "" < p1.first ?? ""
        }
        
        let parameterString = parameterComponents.joined(separator: "&")
        let encodedParameterString = parameterString.urlEncoded
        
        let encodedURL = baseURL.absoluteString.urlEncoded
        
        let signatureBaseString = "\(httpMethod)&\(encodedURL)&\(encodedParameterString)"
        let message = Data(signatureBaseString.utf8)
        
        let key = SymmetricKey(data: Data(signingKey.utf8))
        var hmac: HMAC<Insecure.SHA1> = HMAC(key: key)
        hmac.update(data: message)
        let mac = hmac.finalize()
        
        let base64EncodedMac = Data(mac).base64EncodedString()
        return base64EncodedMac
    }
    
}

extension Twitter.API.OAuth {
    public enum OAuthExchange {
        case pin(consumerKey: String, consumerKeySecret: String)
        case custom(consumerKey: String, hostPublicKey: Curve25519.KeyAgreement.PublicKey, oauthEndpoint: String)
    }
    
    public enum OAuthRequestTokenExchange {
        case requestTokenResponse(RequestTokenResponse)
        case customRequestTokenResponse(CustomRequestTokenResponse, append: CustomRequestTokenResponseAppend)
    }
}

// MARK: - Helper

extension String {
    
    var urlEncoded: String {
        let customAllowedSet = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return self.addingPercentEncoding(withAllowedCharacters: customAllowedSet)!
    }
    
}

extension Dictionary {
    
    var queryString: String {
        var parts = [String]()
        
        for (key, value) in self {
            let query: String = "\(key)=\(value)"
            parts.append(query)
        }
        
        return parts.joined(separator: "&")
    }
    
    var urlEncodedQuery: String {
        var parts = [String]()
        
        for (key, value) in self {
            let keyString = "\(key)".urlEncoded
            let valueString = "\(value)".urlEncoded
            let query = "\(keyString)=\(valueString)"
            parts.append(query)
        }
        
        return parts.joined(separator: "&")
    }
    
}