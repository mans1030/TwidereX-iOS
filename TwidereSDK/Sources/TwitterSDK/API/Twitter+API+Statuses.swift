//
//  Twitter+API+Statuses.swift
//  
//
//  Created by Cirno MainasuK on 2020-10-15.
//

import Foundation
import Combine

extension Twitter.API.Statuses {
    
    static let updateEndpointURL = Twitter.API.endpointURL
        .appendingPathComponent("statuses")
        .appendingPathComponent("update.json")
    
    public static func update(
        session: URLSession,
        query: UpdateQuery,
        authorization: Twitter.API.OAuth.Authorization
    ) async throws -> Twitter.Response.Content<Twitter.Entity.Tweet> {
        let request = Twitter.API.request(
            url: updateEndpointURL,
            method: .POST,
            query: query,
            authorization: authorization
        )
        let (data, response) = try await session.data(for: request, delegate: nil)
        let value = try Twitter.API.decode(type: Twitter.Entity.Tweet.self, from: data, response: response)
        return Twitter.Response.Content(value: value, response: response)
    }
    
    public struct UpdateQuery: Query {
        public let status: String
        public let inReplyToStatusID: Twitter.Entity.Tweet.ID?
        public let autoPopulateReplyMetadata: Bool?
        public let excludeReplyUserIDs: String?
        public let mediaIDs: String?
        public let latitude: Double?
        public let longitude: Double?
        public let placeID: String?
        
        public init(
            status: String,
            inReplyToStatusID: Twitter.Entity.Tweet.ID?,
            autoPopulateReplyMetadata: Bool?,
            excludeReplyUserIDs: String?,
            mediaIDs: String?,
            latitude: Double?,
            longitude: Double?,
            placeID: String?
        ) {
            self.status = status
            self.inReplyToStatusID = inReplyToStatusID
            self.autoPopulateReplyMetadata = autoPopulateReplyMetadata
            self.excludeReplyUserIDs = excludeReplyUserIDs
            self.mediaIDs = mediaIDs
            self.latitude = latitude
            self.longitude = longitude
            self.placeID = placeID
        }
        
        var queryItems: [URLQueryItem]? {
            var items: [URLQueryItem] = []
            inReplyToStatusID.flatMap { items.append(URLQueryItem(name: "in_reply_to_status_id", value: $0)) }
            autoPopulateReplyMetadata.flatMap { items.append(URLQueryItem(name: "auto_populate_reply_metadata", value: $0 ? "true" : "false")) }
            excludeReplyUserIDs.flatMap { items.append(URLQueryItem(name: "exclude_reply_user_ids", value: $0)) }
            mediaIDs.flatMap { items.append(URLQueryItem(name: "media_ids", value: $0)) }
            latitude.flatMap { items.append(URLQueryItem(name: "lat", value: String($0))) }
            longitude.flatMap { items.append(URLQueryItem(name: "long", value: String($0))) }
            placeID.flatMap { items.append(URLQueryItem(name: "place_id", value: $0)) }
            guard !items.isEmpty else { return nil }
            return items
        }
        var encodedQueryItems: [URLQueryItem]? {
            var items: [URLQueryItem] = []
            items.append(URLQueryItem(name: "status", value: status.urlEncoded))
            guard !items.isEmpty else { return nil }
            return items
        }
        var formQueryItems: [URLQueryItem]? { nil }
        var contentType: String? { nil }
        var body: Data? { nil }
    }
    
}

extension Twitter.API.Statuses {

    static func retweetEndpointURL(tweetID: Twitter.Entity.Tweet.ID) -> URL { return Twitter.API.endpointURL.appendingPathComponent("statuses/retweet/\(tweetID).json") }
    static func unretweetEndpointURL(tweetID: Twitter.Entity.Tweet.ID) -> URL { return Twitter.API.endpointURL.appendingPathComponent("statuses/unretweet/\(tweetID).json") }
    static func destroyEndpointURL(tweetID: Twitter.Entity.Tweet.ID) -> URL { return Twitter.API.endpointURL.appendingPathComponent("statuses/destroy/\(tweetID).json") }
    
    public static func retweet(session: URLSession, authorization: Twitter.API.OAuth.Authorization, retweetKind: RetweetKind, query: RetweetQuery) -> AnyPublisher<Twitter.Response.Content<Twitter.Entity.Tweet>, Error> {
        let url: URL = {
            switch retweetKind {
            case .retweet: return retweetEndpointURL(tweetID: query.id)
            case .unretweet: return unretweetEndpointURL(tweetID: query.id)
            }
        }()
        var request = Twitter.API.request(url: url, httpMethod: "POST", authorization: authorization, queryItems: query.queryItems)
        request.httpMethod = "POST"
        return session.dataTaskPublisher(for: request)
            .tryMap { data, response in
                let value = try Twitter.API.decode(type: Twitter.Entity.Tweet.self, from: data, response: response)
                return Twitter.Response.Content(value: value, response: response)
            }
            .eraseToAnyPublisher()
    }
    
    public static func destroy(session: URLSession, authorization: Twitter.API.OAuth.Authorization, query: DestroyQuery) -> AnyPublisher<Twitter.Response.Content<Twitter.Entity.Tweet>, Error> {
        let url = destroyEndpointURL(tweetID: query.id)
        var request = Twitter.API.request(url: url, httpMethod: "POST", authorization: authorization, queryItems: query.queryItems)
        request.httpMethod = "POST"
        return session.dataTaskPublisher(for: request)
            .tryMap { data, response in
                let value = try Twitter.API.decode(type: Twitter.Entity.Tweet.self, from: data, response: response)
                return Twitter.Response.Content(value: value, response: response)
            }
            .eraseToAnyPublisher()
    }
    
}

extension Twitter.API.Statuses {

    public enum RetweetKind {
        case retweet
        case unretweet
    }
    
    public struct RetweetQuery {
        public let id: Twitter.Entity.Tweet.ID
        
        public init(id: Twitter.Entity.Tweet.ID) {
            self.id = id
        }
        
        var queryItems: [URLQueryItem]? {
            var items: [URLQueryItem] = []
            items.append(URLQueryItem(name: "id", value: id))
            guard !items.isEmpty else { return nil }
            return items
        }
    }
    
    public struct DestroyQuery {
        public let id: Twitter.Entity.Tweet.ID
        
        public init(id: Twitter.Entity.Tweet.ID) {
            self.id = id
        }
        
        var queryItems: [URLQueryItem]? {
            var items: [URLQueryItem] = []
            items.append(URLQueryItem(name: "id", value: id))
            guard !items.isEmpty else { return nil }
            return items
        }
    }
    
}
