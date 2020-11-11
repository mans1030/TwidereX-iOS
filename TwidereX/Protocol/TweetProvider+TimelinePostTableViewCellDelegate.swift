//
//  EntityProvider+TimelinePostTableViewCellDelegate.swift
//  TwidereX
//
//  Created by Cirno MainasuK on 2020/11/10.
//  Copyright © 2020 Twidere. All rights reserved.
//

import os.log
import UIKit
import Combine
import CoreData
import CoreDataStack
import TwitterAPI

extension TimelinePostTableViewCellDelegate where Self: TweetProvider {
    
    func timelinePostTableViewCell(_ cell: TimelinePostTableViewCell, retweetInfoLabelDidPressed label: UILabel) {
        tweet(for: cell)
            .sink { [weak self] tweet in
                guard let self = self else { return }
                guard let tweet = tweet else { return }
                let twitterUser = tweet.author
                
                let profileViewModel = ProfileViewModel(twitterUser: twitterUser)
                self.context.authenticationService.currentTwitterUser
                    .assign(to: \.value, on: profileViewModel.currentTwitterUser).store(in: &profileViewModel.disposeBag)
                DispatchQueue.main.async {
                    self.coordinator.present(scene: .profile(viewModel: profileViewModel), from: self, transition: .show)
                }
            }
            .store(in: &disposeBag)
    }
    
    func timelinePostTableViewCell(_ cell: TimelinePostTableViewCell, avatarImageViewDidPressed imageView: UIImageView) {
        tweet(for: cell)
            .sink { [weak self] tweet in
                guard let self = self else { return }
                guard let tweet = tweet?.retweet ?? tweet else { return }
                let twitterUser = tweet.author
                
                let profileViewModel = ProfileViewModel(twitterUser: twitterUser)
                self.context.authenticationService.currentTwitterUser
                    .assign(to: \.value, on: profileViewModel.currentTwitterUser).store(in: &profileViewModel.disposeBag)
                DispatchQueue.main.async {
                    self.coordinator.present(scene: .profile(viewModel: profileViewModel), from: self, transition: .show)
                }
            }
            .store(in: &disposeBag)
    }
    
    func timelinePostTableViewCell(_ cell: TimelinePostTableViewCell, quoteAvatarImageViewDidPressed imageView: UIImageView) {
        tweet(for: cell)
            .sink { [weak self] tweet in
                guard let self = self else { return }
                guard let tweet = tweet?.retweet?.quote ?? tweet?.quote else { return }
                let twitterUser = tweet.author
                
                let profileViewModel = ProfileViewModel(twitterUser: twitterUser)
                self.context.authenticationService.currentTwitterUser
                    .assign(to: \.value, on: profileViewModel.currentTwitterUser).store(in: &profileViewModel.disposeBag)
                DispatchQueue.main.async {
                    self.coordinator.present(scene: .profile(viewModel: profileViewModel), from: self, transition: .show)
                }
            }
            .store(in: &disposeBag)
    }
    
    func timelinePostTableViewCell(_ cell: TimelinePostTableViewCell, quotePostViewDidPressed quotePostView: QuotePostView) {
        tweet(for: cell)
            .sink { [weak self] tweet in
                guard let self = self else { return }
                guard let tweet = tweet?.quote else { return }
                
                let tweetPostViewModel = TweetConversationViewModel(context: self.context, tweetObjectID: tweet.objectID)
                DispatchQueue.main.async {
                    self.coordinator.present(scene: .tweetConversation(viewModel: tweetPostViewModel), from: self, transition: .show)
                }
            }
            .store(in: &disposeBag)
    }
    
    // MARK: - ActionToolbar
    
    func timelinePostTableViewCell(_ cell: TimelinePostTableViewCell, actionToolbar: TimelinePostActionToolbar, replayButtonDidPressed sender: UIButton) {
        tweet(for: cell)
            .sink { [weak self] tweet in
                guard let self = self else { return }
                guard let tweet = (tweet?.retweet ?? tweet) else { return }
                let tweetObjectID = tweet.objectID
                
                let composeTweetViewModel = ComposeTweetViewModel(context: self.context, repliedTweetObjectID: tweetObjectID)
                DispatchQueue.main.async {
                    self.coordinator.present(scene: .composeTweet(viewModel: composeTweetViewModel), from: self, transition: .modal(animated: true, completion: nil))
                }
            }
            .store(in: &disposeBag)
    }
    
    func timelinePostTableViewCell(_ cell: TimelinePostTableViewCell, actionToolbar: TimelinePostActionToolbar, retweetButtonDidPressed sender: UIButton) {
        // prepare authentication
        guard let twitterAuthentication = context.authenticationService.currentActiveTwitterAutentication.value,
              let authorization = try? twitterAuthentication.authorization(appSecret: AppSecret.shared) else {
            assertionFailure()
            return
        }
        
        // prepare current user infos
        guard let _currentTwitterUser = context.authenticationService.currentTwitterUser.value else {
            assertionFailure()
            return
        }
        let twitterUserID = twitterAuthentication.userID
        assert(_currentTwitterUser.id == twitterUserID)
        let twitterUserObjectID = _currentTwitterUser.objectID
        
        guard let context = self.context else { return }
        
        // haptic feedback generator
        let generator = UIImpactFeedbackGenerator(style: .light)
        let responseFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)
        
        tweet(for: cell)
            .compactMap { tweet -> (NSManagedObjectID, Twitter.API.Statuses.RetweetKind)? in
                guard let tweet = tweet else { return nil }
                let retweetKind: Twitter.API.Statuses.RetweetKind = {
                    let targetTweet = (tweet.retweet ?? tweet)
                    let isRetweeted = targetTweet.retweetBy.flatMap { $0.contains(where: { $0.id == twitterUserID }) } ?? false
                    return isRetweeted ? .unretweet : .retweet
                }()
                return (tweet.objectID, retweetKind)
            }
            .map { tweetObjectID, retweetKind -> AnyPublisher<(Tweet.ID, Twitter.API.Statuses.RetweetKind), Error>  in
                return context.apiService.retweet(
                    tweetObjectID: tweetObjectID,
                    twitterUserObjectID: twitterUserObjectID,
                    retweetKind: retweetKind,
                    authorization: authorization,
                    twitterUserID: twitterUserID
                )
                .map { tweetID in (tweetID, retweetKind) }
                .eraseToAnyPublisher()
            }
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
            .switchToLatest()
            .receive(on: DispatchQueue.main)
            .handleEvents { _ in
                generator.prepare()
                responseFeedbackGenerator.prepare()
            } receiveOutput: { _, retweetKind in
                generator.impactOccurred()
                os_log("%{public}s[%{public}ld], %{public}s: [Retweet] update local tweet retweet status to: %s", ((#file as NSString).lastPathComponent), #line, #function, retweetKind == .retweet ? "retweet" : "unretweet")
            } receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    // TODO: handle error
                    break
                case .finished:
                    break
                }
            }
            .map { tweetID, retweetKind in
                return context.apiService.retweet(
                    tweetID: tweetID,
                    retweetKind: retweetKind,
                    authorization: authorization,
                    twitterUserID: twitterUserID
                )
            }
            .switchToLatest()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self = self else { return }
                if self.view.window != nil {
                    responseFeedbackGenerator.impactOccurred()
                }
                switch completion {
                case .failure(let error):
                    os_log("%{public}s[%{public}ld], %{public}s: [Retweet] remote retweet request fail: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
                case .finished:
                    os_log("%{public}s[%{public}ld], %{public}s: [Retweet] remote retweet request success", ((#file as NSString).lastPathComponent), #line, #function)
                }
            } receiveValue: { response in
                // do nothing
            }
            .store(in: &disposeBag)
    }
    
    func timelinePostTableViewCell(_ cell: TimelinePostTableViewCell, actionToolbar: TimelinePostActionToolbar, favoriteButtonDidPressed sender: UIButton) {
        // prepare authentication
        guard let twitterAuthentication = context.authenticationService.currentActiveTwitterAutentication.value,
              let authorization = try? twitterAuthentication.authorization(appSecret: AppSecret.shared) else {
            assertionFailure()
            return
        }
        
        // prepare current user infos
        guard let _currentTwitterUser = context.authenticationService.currentTwitterUser.value else {
            assertionFailure()
            return
        }
        let twitterUserID = twitterAuthentication.userID
        assert(_currentTwitterUser.id == twitterUserID)
        let twitterUserObjectID = _currentTwitterUser.objectID
        
        guard let context = self.context else { return }
        
        // haptic feedback generator
        let generator = UIImpactFeedbackGenerator(style: .light)
        let responseFeedbackGenerator = UIImpactFeedbackGenerator(style: .medium)

        tweet(for: cell)
            .compactMap { tweet -> (NSManagedObjectID, Twitter.API.Favorites.FavoriteKind)? in
                guard let tweet = tweet else { return nil }
                let favoriteKind: Twitter.API.Favorites.FavoriteKind = {
                    let targetTweet = (tweet.retweet ?? tweet)
                    let isLiked = targetTweet.likeBy.flatMap { $0.contains(where: { $0.id == twitterUserID }) } ?? false
                    return isLiked ? .destroy : .create
                }()
                return (tweet.objectID, favoriteKind)
            }
            .map { tweetObjectID, favoriteKind -> AnyPublisher<(Tweet.ID, Twitter.API.Favorites.FavoriteKind), Error>  in
                return context.apiService.like(
                    tweetObjectID: tweetObjectID,
                    twitterUserObjectID: twitterUserObjectID,
                    favoriteKind: favoriteKind,
                    authorization: authorization,
                    twitterUserID: twitterUserID
                )
                .map { tweetID in (tweetID, favoriteKind) }
                .eraseToAnyPublisher()
            }
            .setFailureType(to: Error.self)
            .eraseToAnyPublisher()
            .switchToLatest()
            .receive(on: DispatchQueue.main)
            .handleEvents { _ in
                generator.prepare()
                responseFeedbackGenerator.prepare()
            } receiveOutput: { _, favoriteKind in
                generator.impactOccurred()
                os_log("%{public}s[%{public}ld], %{public}s: [Like] update local tweet like status to: %s", ((#file as NSString).lastPathComponent), #line, #function, favoriteKind == .create ? "like" : "unlike")
            } receiveCompletion: { completion in
                switch completion {
                case .failure(let error):
                    // TODO: handle error
                    break
                case .finished:
                    break
                }
            }
            .map { tweetID, favoriteKind in
                return context.apiService.like(
                    tweetID: tweetID,
                    favoriteKind: favoriteKind,
                    authorization: authorization,
                    twitterUserID: twitterUserID
                )
            }
            .switchToLatest()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] completion in
                guard let self = self else { return }
                if self.view.window != nil {
                    responseFeedbackGenerator.impactOccurred()
                }
                switch completion {
                case .failure(let error):
                    os_log("%{public}s[%{public}ld], %{public}s: [Like] remote like request fail: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
                case .finished:
                    os_log("%{public}s[%{public}ld], %{public}s: [Like] remote like request success", ((#file as NSString).lastPathComponent), #line, #function)
                }
            } receiveValue: { response in
                // do nothing
            }
            .store(in: &disposeBag)
    }
    
    func timelinePostTableViewCell(_ cell: TimelinePostTableViewCell, actionToolbar: TimelinePostActionToolbar, shareButtonDidPressed sender: UIButton) {
        tweet(for: cell)
            .compactMap { $0?.activityItems }
            .sink { [weak self] activityItems in
                guard let self = self else { return }
                let activityViewController = UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
                activityViewController.popoverPresentationController?.sourceView = sender
                self.present(activityViewController, animated: true, completion: nil)
            }
            .store(in: &disposeBag)
    }
    
}

extension TimelinePostTableViewCellDelegate where Self: TweetProvider & MediaPreviewableViewController {
    // MARK: - MosaicImageViewDelegate
    func timelinePostTableViewCell(_ cell: TimelinePostTableViewCell, mosaicImageView: MosaicImageView, didTapImageView imageView: UIImageView, atIndex index: Int) {
        tweet(for: cell)
            .sink { [weak self] tweet in
                guard let self = self else { return }
                guard let tweet = tweet else { return }
                
                let root = MediaPreviewViewModel.Root(
                    tweetObjectID: tweet.objectID,
                    initialIndex: index,
                    preloadThumbnailImages: mosaicImageView.imageViews.map { $0.image }
                )
                let mediaPreviewViewModel = MediaPreviewViewModel(context: self.context, root: root)
                DispatchQueue.main.async {
                    self.coordinator.present(scene: .mediaPreview(viewModel: mediaPreviewViewModel), from: self, transition: .custom(transitioningDelegate: self.mediaPreviewTransitionController))
                }
            }
            .store(in: &disposeBag)
    }
}
