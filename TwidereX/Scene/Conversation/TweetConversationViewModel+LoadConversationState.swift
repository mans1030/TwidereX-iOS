//
//  TweetConversationViewModel+LoadConversationState.swift
//  TwidereX
//
//  Created by Cirno MainasuK on 2020-10-15.
//  Copyright © 2020 Twidere. All rights reserved.
//

import os.log
import Foundation
import GameplayKit
import CoreDataStack
import TwitterAPI

extension TweetConversationViewModel {
    class LoadConversationState: GKState {
        weak var viewModel: TweetConversationViewModel?
        
        var prepareFailCount = 0
        
        init(viewModel: TweetConversationViewModel) {
            self.viewModel = viewModel
        }
        
        override func didEnter(from previousState: GKState?) {
            os_log("%{public}s[%{public}ld], %{public}s: enter %s, previous: %s", ((#file as NSString).lastPathComponent), #line, #function, self.debugDescription, previousState.debugDescription)
            guard let viewModel = viewModel, let stateMachine = stateMachine else { return }
        }
    }
}

extension TweetConversationViewModel.LoadConversationState {
    class Initial: TweetConversationViewModel.LoadConversationState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return stateClass == Prepare.self
        }
    }
    
    class Prepare: TweetConversationViewModel.LoadConversationState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return stateClass == Idle.self || stateClass == Loading.self || stateClass == PrepareFail.self
        }
        
        override func didEnter(from previousState: GKState?) {
            super.didEnter(from: previousState)
            
            guard let viewModel = viewModel, let stateMachine = stateMachine else { return }
            guard case let .root(tweetObjectID)  = viewModel.rootItem else {
                assertionFailure()
                stateMachine.enter(PrepareFail.self)
                return
            }

            var _tweetID: Twitter.Entity.V2.Tweet.ID?
            var _authorID: Twitter.Entity.V2.User.ID?
            var _conversationID: Twitter.Entity.V2.Tweet.ConversationID?
            viewModel.context.managedObjectContext.perform {
                let tweet = viewModel.context.managedObjectContext.object(with: tweetObjectID) as! Tweet
                _tweetID = tweet.id
                _authorID = tweet.author.id
                _conversationID = tweet.conversationID
             
                DispatchQueue.main.async {
                    guard let tweetID = _tweetID, let authorID = _authorID else {
                        assertionFailure()
                        stateMachine.enter(PrepareFail.self)
                        return
                    }
                    
                    if let conversationID = _conversationID {
                        viewModel.conversationMeta.value = .init(
                            tweetID: tweetID,
                            authorID: authorID,
                            conversationID: conversationID
                        )
                        stateMachine.enter(Loading.self)
                    } else {
                        guard let authentication = viewModel.currentTwitterAuthentication.value,
                              let authorization = try? authentication.authorization(appSecret: AppSecret.shared) else
                        {
                            assertionFailure()
                            stateMachine.enter(PrepareFail.self)
                            return
                        }
                        viewModel.context.apiService.tweets(tweetIDs: [tweetID], authorization: authorization, twitterUserID: authentication.userID)
                            .receive(on: DispatchQueue.main)
                            .sink { completion in
                                switch completion {
                                case .failure(let error):
                                    os_log("%{public}s[%{public}ld], %{public}s: fetch tweet conversationID fail: %s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
                                    debugPrint(error)
                                    stateMachine.enter(PrepareFail.self)
                                case .finished:
                                    break
                                }
                            } receiveValue: { response in
                                let content = response.value
                                guard let entity = content.data?.first,
                                      let conversationID = entity.conversationID else
                                {
                                    stateMachine.enter(PrepareFail.self)
                                    return
                                }
                                os_log("%{public}s[%{public}ld], %{public}s: fetch tweet %s conversationID: %s", ((#file as NSString).lastPathComponent), #line, #function, tweetID, entity.conversationID ?? "<nil>")
                                
                                viewModel.conversationMeta.value = .init(
                                    tweetID: tweetID,
                                    authorID: authorID,
                                    conversationID: conversationID
                                )
                                stateMachine.enter(Loading.self)
                            }
                            .store(in: &viewModel.disposeBag)
                    }
                }   // end DispatchQueue.main.async
            }   // end viewModel.context.managedObjectContext.perform
        }
    }
    
    class PrepareFail: TweetConversationViewModel.LoadConversationState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return stateClass == Prepare.self
        }
        
        override func didEnter(from previousState: GKState?) {
            super.didEnter(from: previousState)
            
            // retry 3 times
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
                guard let self = self else { return }
                guard let stateMachine = self.stateMachine else { return }

                guard self.prepareFailCount < 3 else { return }
                self.prepareFailCount += 1
                stateMachine.enter(Prepare.self)
            }
        }
    }
    
    class Idle: TweetConversationViewModel.LoadConversationState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return stateClass == Loading.self
        }
    }
    
    class Loading: TweetConversationViewModel.LoadConversationState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return stateClass == Idle.self || stateClass == Fail.self || stateClass == NoMore.self
        }
        
        override func didEnter(from previousState: GKState?) {
            super.didEnter(from: previousState)
            
            guard let viewModel = viewModel, let stateMachine = stateMachine else { return }
            guard let conversationMeta = viewModel.conversationMeta.value else {
                assertionFailure()
                stateMachine.enter(Fail.self)
                return
            }
            
            guard let authentication = viewModel.currentTwitterAuthentication.value,
                  let authorization = try? authentication.authorization(appSecret: AppSecret.shared) else
            {
                assertionFailure()
                stateMachine.enter(Fail.self)
                return
            }
            
            viewModel.context.apiService.tweetsRecentSearch(
                conversationID: conversationMeta.conversationID,
                authorID: conversationMeta.authorID,
                authorization: authorization,
                requestTwitterUserID: authentication.userID
            )
            .receive(on: DispatchQueue.main)
            .sink { completion in
                switch completion {
                case .failure(let error):
                    os_log("%{public}s[%{public}ld], %{public}s: fetch conversation %s fail: %s", ((#file as NSString).lastPathComponent), #line, #function, conversationMeta.conversationID, error.localizedDescription)
                    debugPrint(error)
                    stateMachine.enter(Idle.self)
                case .finished:
                    break
                }
            } receiveValue: { response in
                let content = response.value
                os_log("%{public}s[%{public}ld], %{public}s: fetch conversation %s success. results count %ld", ((#file as NSString).lastPathComponent), #line, #function, conversationMeta.conversationID, content.meta.resultCount)

                guard content.meta.resultCount > 0 else {
                    stateMachine.enter(NoMore.self)
                    return
                }
                
                // handle data
                // TODO:
                stateMachine.enter(Idle.self)

            }
            .store(in: &viewModel.disposeBag)

        }
    }
    
    class Fail: TweetConversationViewModel.LoadConversationState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return stateClass == Loading.self
        }
    }
    
    class NoMore: TweetConversationViewModel.LoadConversationState {
        override func isValidNextState(_ stateClass: AnyClass) -> Bool {
            return false
        }
    }
    
}