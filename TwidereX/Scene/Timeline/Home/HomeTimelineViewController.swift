//
//  HomeTimelineViewController.swift
//  TwidereX
//
//  Created by Cirno MainasuK on 2020-9-1.
//  Copyright © 2020 Twidere. All rights reserved.
//

import os.log
import UIKit
import Combine
import TwidereUI
import TwidereLocalization

final class HomeTimelineViewController: ListTimelineViewController {
    
    static var unreadIndicatorViewTopMargin: CGFloat { 16 }
    let unreadIndicatorView = UnreadIndicatorView()

    // ref: https://medium.com/@Mos6yCanSwift/swift-ios-determine-scroll-direction-d48a2327a004
    var lastVelocityYSign = 0
    var lastContentOffset: CGPoint?
    
    deinit {
        os_log(.info, log: .debug, "%{public}s[%{public}ld], %{public}s:", ((#file as NSString).lastPathComponent), #line, #function)
    }
    
}

extension HomeTimelineViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        title = L10n.Scene.Timeline.title
        
        // setup unreadIndicatorView
        unreadIndicatorView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(unreadIndicatorView)
        NSLayoutConstraint.activate([
            unreadIndicatorView.topAnchor.constraint(equalTo: view.layoutMarginsGuide.topAnchor, constant: 16),
            view.layoutMarginsGuide.trailingAnchor.constraint(equalTo: unreadIndicatorView.trailingAnchor),
            unreadIndicatorView.widthAnchor.constraint(greaterThanOrEqualToConstant: 36).priority(.required - 1),
            unreadIndicatorView.heightAnchor.constraint(greaterThanOrEqualToConstant: 36).priority(.required - 1),
        ])
        unreadIndicatorView.isUserInteractionEnabled = false
        unreadIndicatorView.alpha = 0
        viewModel.didLoadLatest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                guard let self = self else { return }
                self.unreadIndicatorView.translationY = .zero
            }
            .store(in: &disposeBag)

        #if DEBUG
        navigationItem.rightBarButtonItem = debugActionBarButtonItem
        #endif
        
        guard let viewModel = self.viewModel as? HomeTimelineViewModel else {
            assertionFailure()
            return
        }
        
        viewModel.setupDiffableDataSource(
            tableView: tableView,
            statusViewTableViewCellDelegate: self,
            timelineMiddleLoaderTableViewCellDelegate: self
        )
        
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(HomeTimelineViewController.homeTimelineLoadNotificationHandler(_:)),
            name: APIService.homeTimelineLoadNotification,
            object: nil
        )
        
        viewModel.didLoadLatest
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in
                guard let self = self else { return }
                guard let viewModel = self.viewModel as? HomeTimelineViewModel else { return }
                viewModel.loadItemCount = 0
            }
            .store(in: &disposeBag)
        
        Publishers.CombineLatest(
            viewModel.$unreadItemCount,
            viewModel.$loadItemCount
        )
        .receive(on: DispatchQueue.main)
        .sink { [weak self] unreadItemCount, loadItemCount in
            guard let self = self else { return }

            let count = max(0, loadItemCount) + max(0, unreadItemCount)
            self.unreadIndicatorView.count = count
            self.logger.log(level: .debug, "\((#file as NSString).lastPathComponent, privacy: .public)[\(#line, privacy: .public)], \(#function, privacy: .public): update unread indicator count: \(count)")
            
            let animator = UIViewPropertyAnimator(duration: 0.33, timingParameters: UICubicTimingParameters(animationCurve: .easeInOut))
            animator.addAnimations {
                self.unreadIndicatorView.alpha = count > 0 ? 1 : 0
            }
            animator.startAnimation()
        }
        .store(in: &disposeBag)
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        unreadIndicatorView.startDisplayLink()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        
        unreadIndicatorView.stopDisplayLink()
    }
    
}

extension HomeTimelineViewController {
    @objc private func homeTimelineLoadNotificationHandler(_ notification: Notification) {
        logger.log(level: .debug, "\((#file as NSString).lastPathComponent, privacy: .public)[\(#line, privacy: .public)], \(#function, privacy: .public)")
        
        Task { @MainActor in
            assert(Thread.isMainThread)
            
            guard let viewModel = self.viewModel as? HomeTimelineViewModel else {
                assertionFailure()
                return
            }
            
            guard let userInfo = notification.userInfo,
                  let sinceID = userInfo["sinceID"] as? String,
                  let currentSinceID = viewModel.sinceID,
                  currentSinceID == sinceID,
                  let count = userInfo["count"] as? Int
            else { return }
            
            viewModel.loadItemCount += count
        }   // end Task
    }
}

// MARK: - UIScrollViewDelegate
extension HomeTimelineViewController {
    
    // update home timeline unread indicator position
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        defer {
            lastContentOffset = scrollView.contentOffset
        }

        let currentVelocityY = scrollView.panGestureRecognizer.velocity(in: scrollView.superview).y
        let currentVelocityYSign = Int(currentVelocityY).signum()
        
        if currentVelocityYSign != lastVelocityYSign && currentVelocityYSign != .zero {
            lastVelocityYSign = currentVelocityYSign
        }
        
        let lastContentOffset = self.lastContentOffset ?? scrollView.contentOffset
        let offsetY = scrollView.contentOffset.y - lastContentOffset.y
        
        let translationThrottle = -(HomeTimelineViewController.unreadIndicatorViewTopMargin + unreadIndicatorView.frame.height)
        let translationY = min(max(unreadIndicatorView.translationY - offsetY, translationThrottle), 0)
        
        if lastVelocityYSign < 0 {
            // down
            guard offsetY > 0 else { return }
            unreadIndicatorView.translationY = translationY
        } else if lastVelocityYSign > 0 {
            // up
            guard offsetY < 0 else { return }
            unreadIndicatorView.translationY = translationY
        }
    }
    
}

// MARK: - UITableViewDelegate
extension HomeTimelineViewController {
 
    // update home timeline unread indicator count
    override func tableView(_ tableView: UITableView, willDisplay cell: UITableViewCell, forRowAt indexPath: IndexPath) {
        super.tableView(tableView, willDisplay: cell, forRowAt: indexPath)
        
        guard let viewModel = self.viewModel as? HomeTimelineViewModel else {
            assertionFailure()
            return
        }
        
        guard !viewModel.isUpdaingDataSource else { return }
        
        guard let diffableDataSource = viewModel.diffableDataSource else { return }
        guard let item = diffableDataSource.itemIdentifier(for: indexPath) else { return }

        guard let oldItem = viewModel.latestUnreadStatusItem else {
            viewModel.latestUnreadStatusItem = item
            return
        }

        guard let oldIndexPath = diffableDataSource.indexPath(for: oldItem) else {
            viewModel.latestUnreadStatusItem = item
            return
        }

        guard indexPath.row < oldIndexPath.row else {
            return
        }

        viewModel.latestUnreadStatusItem = item
        viewModel.unreadItemCount = indexPath.row
    }
    
}
