//
//  UserListFetchViewModel.swift
//  TwidereX
//
//  Created by Cirno MainasuK on 2021-10-26.
//  Copyright © 2021 Twidere. All rights reserved.
//

import os.log
import Foundation
import TwitterSDK
import MastodonSDK

enum UserListFetchViewModel {
    
    static let logger = Logger(subsystem: "UserListFetchViewModel", category: "ViewModel")
    
    enum Result {
        case twitter([Twitter.Entity.User]) // v1
        case twitterV2([Twitter.Entity.V2.User]) // v2
        case mastodon([Mastodon.Entity.Account])
    }
}

extension UserListFetchViewModel {
    
    enum SearchInput {
        case twitter(SearchTwitterUserFetchContext)
        case mastodon(SearchMastodonUserFetchContext)
    }
    
    struct SearchOutput {
        let result: Result
        
        let hasMore: Bool
        let nextInput: SearchInput?
    }
    
    struct SearchTwitterUserFetchContext {
        let authenticationContext: TwitterAuthenticationContext
        let searchText: String
        let page: Int
        let count: Int?
        
        func map(page: Int) -> SearchTwitterUserFetchContext {
            return SearchTwitterUserFetchContext(
                authenticationContext: authenticationContext,
                searchText: searchText,
                page: page,
                count: count
            )
        }
    }
    
    struct SearchMastodonUserFetchContext {
        let authenticationContext: MastodonAuthenticationContext
        let searchText: String
        let offset: Int
        let count: Int?
        
        func map(offset: Int) -> SearchMastodonUserFetchContext {
            return SearchMastodonUserFetchContext(
                authenticationContext: authenticationContext,
                searchText: searchText,
                offset: offset,
                count: count
            )
        }
    }

    static func search(context: AppContext, input: SearchInput) async throws -> SearchOutput {
        switch input {
        case .twitter(let fetchContext):
            let searchText: String = try {
                let searchText = fetchContext.searchText
                guard !searchText.isEmpty, searchText.count < 512 else {
                    throw AppError.implicit(.badRequest)
                }
                return searchText
            }()
            let query = Twitter.API.Users.SearchQuery(
                q: searchText,
                page: fetchContext.page,
                count: fetchContext.count ?? 20
            )
            logger.log(level: .debug, "\((#file as NSString).lastPathComponent, privacy: .public)[\(#line, privacy: .public)], \(#function, privacy: .public): fetch at page \(query.page)")
            let response = try await context.apiService.searchTwitterUser(
                query: query,
                authenticationContext: fetchContext.authenticationContext
            )
            // here `query.count` limit to max 20 and only first 1000 users will returns
            let noMore = response.value.isEmpty || response.value.count < query.count
            let nextInput: SearchInput? = {
                if noMore { return nil }
                let fetchContext = fetchContext.map(page: query.page + 1)
                return .twitter(fetchContext)
            }()
            return SearchOutput(
                result: .twitter(response.value),
                hasMore: !noMore,
                nextInput: nextInput
            )
        case .mastodon(let fetchContext):
            let searchText: String = try {
                let searchText = fetchContext.searchText
                guard !searchText.isEmpty, searchText.count < 512 else {
                    throw AppError.implicit(.badRequest)
                }
                return searchText
            }()
            let query = Mastodon.API.V2.Search.SearchQuery(
                type: .accounts,
                accountID: nil,
                q: searchText,
                limit: fetchContext.count ?? 20,
                offset: fetchContext.offset
            )
            logger.log(level: .debug, "\((#file as NSString).lastPathComponent, privacy: .public)[\(#line, privacy: .public)], \(#function, privacy: .public): fetch at offset \(query.offset ?? -1)")
            let response = try await context.apiService.searchMastodon(
                query: query,
                authenticationContext: fetchContext.authenticationContext
            )
            let noMore = response.value.accounts.isEmpty
            let nextInput: SearchInput? = {
                if noMore { return nil }
                let count = response.value.accounts.count
                let fetchContext = fetchContext.map(offset: fetchContext.offset + count)
                return .mastodon(fetchContext)
            }()
            return SearchOutput(
                result: .mastodon(response.value.accounts),
                hasMore: !noMore,
                nextInput: nextInput
            )
        }
    }
}
