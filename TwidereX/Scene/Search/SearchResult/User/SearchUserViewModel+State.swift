//
//  SearchUserViewModel+State.swift
//  TwidereX
//
//  Created by Cirno MainasuK on 2020-10-30.
//  Copyright © 2020 Twidere. All rights reserved.
//

import os.log
import Foundation
import GameplayKit
import TwitterSDK

extension SearchUserViewModel {
    class State: GKState {
        weak var viewModel: SearchUserViewModel?
        
        init(viewModel: SearchUserViewModel) {
            self.viewModel = viewModel
        }
        
        override func didEnter(from previousState: GKState?) {
            os_log("%{public}s[%{public}ld], %{public}s: enter %s, previous: %s", ((#file as NSString).lastPathComponent), #line, #function, self.debugDescription, previousState.debugDescription)
        }
    }
}

extension SearchUserViewModel.State {
    class Initial: SearchUserViewModel.State {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return stateClass == Idle.self || stateClass == Reset.self || stateClass == Loading.self
        }
    }
    
    class Idle: SearchUserViewModel.State {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return stateClass == Reset.self || stateClass == Loading.self
        }
    }
    
    class Reset: SearchUserViewModel.State {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return stateClass == Loading.self
        }
        
        override func didEnter(from previousState: GKState?) {
            super.didEnter(from: previousState)
            
            viewModel?.userRecordFetchedResultController.reset()
            stateMachine?.enter(Loading.self)
        }
    }
    
    class Loading: SearchUserViewModel.State {
        let logger = Logger(subsystem: "SearchUserViewModel.State", category: "StateMachine")
        
        var nextInput: UserListFetchViewModel.SearchInput?
        
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return stateClass == Fail.self
                || stateClass == Reset.self
                || stateClass == Idle.self
                || stateClass == NoMore.self
        }
        
        override func didEnter(from previousState: GKState?) {
            super.didEnter(from: previousState)
            
            if previousState is Reset {
                nextInput = nil
            }
            
            guard let viewModel = viewModel, let stateMachine = stateMachine else { return }
            guard let authenticationContext = viewModel.context.authenticationService.activeAuthenticationContext.value
            else {
                stateMachine.enter(Fail.self)
                return
            }
            
            let searchText = viewModel.searchText
            if nextInput == nil {
                nextInput = {
                    switch authenticationContext {
                    case .twitter(let authenticationContext):
                        return UserListFetchViewModel.SearchInput.twitter(.init(
                            authenticationContext: authenticationContext,
                            searchText: searchText,
                            page: 1,    // count from 1
                            count: 50
                        ))
                    case .mastodon(let authenticationContext):
                        return UserListFetchViewModel.SearchInput.mastodon(.init(
                            authenticationContext: authenticationContext,
                            searchText: searchText,
                            offset: 0,
                            count: 50)
                        )
                    }
                }()
            }
            
            guard let input = nextInput else {
                stateMachine.enter(Fail.self)
                return
            }
            
            Task {
                do {
                    logger.log(level: .debug, "\((#file as NSString).lastPathComponent, privacy: .public)[\(#line, privacy: .public)], \(#function, privacy: .public): fetch…")
                    
                    let output = try await UserListFetchViewModel.search(
                        context: viewModel.context,
                        input: input
                    )
                    
                    // check task needs cancel
                    guard viewModel.searchText == searchText else {
                        return
                    }
                    
                    nextInput = output.nextInput
                    if output.hasMore {
                        stateMachine.enter(Idle.self)
                    } else {
                        stateMachine.enter(NoMore.self)
                    }
                    
                    switch output.result {
                    case .twitter(let users):
                        let userIDs = users.map { $0.idStr }
                        viewModel.userRecordFetchedResultController.twitterUserFetchedResultsController.append(userIDs: userIDs)
                    case .twitterV2(let users):
                        let userIDs = users.map { $0.id }
                        viewModel.userRecordFetchedResultController.twitterUserFetchedResultsController.append(userIDs: userIDs)
                    case .mastodon(let users):
                        let userIDs = users.map { $0.id }
                        viewModel.userRecordFetchedResultController.mastodonUserFetchedResultController.append(userIDs: userIDs)
                    }
                } catch {
                    // logger.log(level: .debug, "\((#file as NSString).lastPathComponent, privacy: .public)[\(#line, privacy: .public)], \(#function, privacy: .public): fetch failure: \(error.localizedDescription)")
                    stateMachine.enter(Fail.self)
                }
            }   // end currentTask = Task { … }
//            if searchText != previoursSearchText {
//                page = 1
//                previoursSearchText = searchText
//                viewModel.searchTwitterUserIDs.value = []
//                viewModel.items.value = []
//            }
//
//            let count = 20
//            viewModel.context.apiService.userSearch(
//                searchText: searchText,
//                page: page,
//                count: count,
//                twitterAuthenticationBox: twitterAuthenticationBox
//            )
//            .receive(on: DispatchQueue.main)
//            .sink { [weak self] completion in
//                guard let self = self else { return }
//                switch completion {
//                case .failure(let error):
//                    os_log("%{public}s[%{public}ld], %{public}s: search %s fail: %s", ((#file as NSString).lastPathComponent), #line, #function, searchText, error.localizedDescription)
//                    debugPrint(error)
//                    self.error = error
//                    stateMachine.enter(Fail.self)
//                case .finished:
//                    break
//                }
//            } receiveValue: { [weak self] response in
//                guard let self = self else { return }
//                let entities = response.value
//                self.page += 1
//                os_log("%{public}s[%{public}ld], %{public}s: search %s success. results count %ld", ((#file as NSString).lastPathComponent), #line, #function, searchText, entities.count)
//
//                guard entities.count > 0 else {
//                    stateMachine.enter(NoMore.self)
//                    return
//                }
//
//                let newTwitterUsers = entities
//                let oldTwitterUserIDs = viewModel.searchTwitterUserIDs.value
//
//                var twitterUserIDs: [Twitter.Entity.Tweet.ID] = []
//                for twitterUserID in oldTwitterUserIDs {
//                    guard !twitterUserIDs.contains(twitterUserID) else { continue }
//                    twitterUserIDs.append(twitterUserID)
//                }
//
//                for twitterUser in newTwitterUsers {
//                    guard !twitterUserIDs.contains(twitterUser.idStr) else { continue }
//                    twitterUserIDs.append(twitterUser.idStr)
//                }
//
//                viewModel.searchTwitterUserIDs.value = twitterUserIDs
//
//                if entities.count < count {
//                    stateMachine.enter(NoMore.self)
//                } else {
//                    stateMachine.enter(Idle.self)
//                }
//            }
//            .store(in: &viewModel.disposeBag)
        }
    }
    
    class Fail: SearchUserViewModel.State {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return stateClass == Reset.self || stateClass == Loading.self
        }
    }
    
    class NoMore: SearchUserViewModel.State {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return stateClass == Reset.self
        }
        
        override func didEnter(from previousState: GKState?) {
            super.didEnter(from: previousState)
//            guard let viewModel = viewModel else { return }
//            guard let diffableDataSource = viewModel.diffableDataSource else { return }
//            var snapshot = diffableDataSource.snapshot()
//            if snapshot.itemIdentifiers.contains(.bottomLoader) {
//                snapshot.deleteItems([.bottomLoader])
//                diffableDataSource.apply(snapshot, animatingDifferences: false)
//            }
        }
    }
    
}
