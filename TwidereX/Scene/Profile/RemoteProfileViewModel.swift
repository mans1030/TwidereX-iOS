//
//  RemoteProfileViewModel.swift
//  TwidereX
//
//  Created by MainasuK on 2021-12-8.
//  Copyright © 2021 Twidere. All rights reserved.
//

import Foundation
import CoreDataStack
import TwidereCore
import TwitterSDK
import MastodonSDK

final class RemoteProfileViewModel: ProfileViewModel {
    
    init(context: AppContext, profileContext: ProfileContext) {
        super.init(context: context)
        
        configure(profileContext: profileContext)
    }
    
    func configure(profileContext: ProfileContext) {
        switch profileContext {
        case .record(let record):
            setup(user: record)
        case .twitter(let twitterContext):
            Task {
                guard case let .twitter(authenticationContext) = context.authenticationService.activeAuthenticationContext else { return }
                do {
                    let _record = try await fetchTwitterUser(
                        twitterContext: twitterContext,
                        authenticationContext: authenticationContext
                    )
                    guard let record = _record else { return }
                    await self.setup(user: .twitter(record: record))
                } catch {
                    // do nothing
                }
            }   // end Task
        case .mastodon(let mastodonContext):
            Task {
                guard case let .mastodon(authenticationContext) = context.authenticationService.activeAuthenticationContext else { return }
                do {
                    let _record = try await fetchMastodonUser(
                        mastodonContext: mastodonContext,
                        authenticationContext: authenticationContext
                    )
                    guard let record = _record else { return }
                    await self.setup(user: .mastodon(record: record))
                } catch {
                    // do nothing
                }
            }   // end Task
        }
    }
    
}

extension RemoteProfileViewModel {
 
    enum ProfileContext {
        case record(record: UserRecord)
        case twitter(TwitterContext)
        case mastodon(MastodonContext)
        
        enum TwitterContext {
            case userID(TwitterUser.ID)
            case username(String)
        }
        
        enum MastodonContext {
            case userID(MastodonUser.ID)
            //case username(String)
        }
    }
    
    // note:
    // use sync method to force data prepared before using
    // otherwise, the UI may delay update when profile display
    func setup(user record: UserRecord) {
        let managedObjectContext = context.managedObjectContext
        managedObjectContext.performAndWait {
            switch record {
            case .twitter(let record):
                guard let object = record.object(in: managedObjectContext) else { return }
                self.user = .twitter(object: object)
            case .mastodon(let record):
                guard let object = record.object(in: managedObjectContext) else { return }
                self.user = .mastodon(object: object)
            }
        }
    }   // end func setup(user:)
    
    // async method on main queue for concurrency way call
    @MainActor
    func setup(user record: UserRecord) async {
        self.user = record.object(in: context.managedObjectContext)
    }
    
}

extension RemoteProfileViewModel {
    func findTwitterUser(userID: TwitterUser.ID) -> ManagedObjectRecord<TwitterUser>? {
        let request = TwitterUser.sortedFetchRequest
        request.predicate = TwitterUser.predicate(id: userID)
        request.fetchLimit = 1
        guard let user = try? context.managedObjectContext.fetch(request).first else { return nil }
        return .init(objectID: user.objectID)
    }
    
    func findMastodonUser(domain: String, userID: MastodonUser.ID) -> ManagedObjectRecord<MastodonUser>? {
        let request = MastodonUser.sortedFetchRequest
        request.predicate = MastodonUser.predicate(domain: domain, id: userID)
        request.fetchLimit = 1
        guard let user = try? context.managedObjectContext.fetch(request).first else { return nil }
        return .init(objectID: user.objectID)
    }
}

extension RemoteProfileViewModel {
    
    func fetchTwitterUser(
        twitterContext: ProfileContext.TwitterContext,
        authenticationContext: TwitterAuthenticationContext
    ) async throws -> ManagedObjectRecord<TwitterUser>? {
        let response: Twitter.Response.Content<Twitter.API.V2.User.Lookup.Content> = try await {
            switch twitterContext {
            case .userID(let userID):
                return try await context.apiService.twitterUsers(
                    userIDs: [userID],
                    twitterAuthenticationContext: authenticationContext
                )
            case .username(let username):
                return try await context.apiService.twitterUsers(
                    usernames: [username],
                    twitterAuthenticationContext: authenticationContext
                )
            }   // end switch
        }()
        guard let entity = response.value.data?.first else { return nil }
        let record = findTwitterUser(userID: entity.id)
        return record
    }
    
    func fetchMastodonUser(
        mastodonContext: ProfileContext.MastodonContext,
        authenticationContext: MastodonAuthenticationContext
    ) async throws -> ManagedObjectRecord<MastodonUser>? {
        let response: Mastodon.Response.Content<Mastodon.Entity.Account> = try await {
            switch mastodonContext {
            case .userID(let userID):
                return try await context.apiService.mastodonUser(
                    userID: userID,
                    mastodonAuthenticationContext: authenticationContext
                )
            }
        }()
        let entity = response.value
        let record = findMastodonUser(domain: authenticationContext.domain, userID: entity.id)
        return record
    }
    
}
