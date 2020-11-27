//
//  SearchUserViewController.swift
//  TwidereX
//
//  Created by Cirno MainasuK on 2020-10-30.
//  Copyright © 2020 Twidere. All rights reserved.
//

import os.log
import UIKit
import Combine
import CoreData
import CoreDataStack
import TwitterAPI

final class SearchUserViewController: UIViewController, NeedsDependency {
    
    weak var context: AppContext! { willSet { precondition(!isViewLoaded) } }
    weak var coordinator: SceneCoordinator! { willSet { precondition(!isViewLoaded) } }
    
    var disposeBag = Set<AnyCancellable>()
    var viewModel: SearchUserViewModel!
    
    lazy var tableView: UITableView = {
        let tableView = UITableView()
        tableView.register(UserBriefInfoTableViewCell.self, forCellReuseIdentifier: String(describing: UserBriefInfoTableViewCell.self))
        tableView.register(TimelineBottomLoaderTableViewCell.self, forCellReuseIdentifier: String(describing: TimelineBottomLoaderTableViewCell.self))
        tableView.rowHeight = UITableView.automaticDimension
        tableView.separatorStyle = .none
        return tableView
    }()
    
    deinit {
        os_log("%{public}s[%{public}ld], %{public}s", ((#file as NSString).lastPathComponent), #line, #function)
    }
    
}

extension SearchUserViewController {
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        tableView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(tableView)
        NSLayoutConstraint.activate([
            tableView.topAnchor.constraint(equalTo: view.topAnchor),
            tableView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            tableView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tableView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        tableView.backgroundColor = .systemBackground
        
        tableView.delegate = self
        viewModel.setupDiffableDataSource(for: tableView)
        
        viewModel.userBriefInfoTableViewCellDelegate = self
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        tableView.deselectRow(with: transitionCoordinator, animated: animated)
    }
    
}

// MARK: - UIScrollViewDelegate
extension SearchUserViewController {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === tableView else { return }
        let cells = tableView.visibleCells.compactMap { $0 as? TimelineBottomLoaderTableViewCell }
        guard let cell = cells.first else { return }
        
        if let tabBar = tabBarController?.tabBar, let window = view.window {
            let loaderCellFrameInWindow = tableView.convert(cell.frame, to: nil)
            let windowHeight = window.frame.height
            let loaderAppear = (loaderCellFrameInWindow.origin.y + 0.8 * cell.frame.height) < (windowHeight - tabBar.frame.height)
            if loaderAppear {
                viewModel.stateMachine.enter(SearchUserViewModel.State.Loading.self)
            }
        } else {
            viewModel.stateMachine.enter(SearchUserViewModel.State.Loading.self)
        }
    }
}

// MARK: - UITableViewDelegate
extension SearchUserViewController: UITableViewDelegate {
    
    func tableView(_ tableView: UITableView, estimatedHeightForRowAt indexPath: IndexPath) -> CGFloat {
        return 80
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        guard let diffableDataSource = viewModel.diffableDataSource else { return }
        guard let item = diffableDataSource.itemIdentifier(for: indexPath) else { return }
        
        guard case let .twitterUser(objectID) = item else { return }
        let twitterUser = viewModel.fetchedResultsController.managedObjectContext.object(with: objectID) as! TwitterUser
        
        let profileViewModel = ProfileViewModel(twitterUser: twitterUser)
        context.authenticationService.activeAuthenticationIndex
            .map { $0?.twitterAuthentication?.twitterUser }
            .assign(to: \.value, on: profileViewModel.currentTwitterUser)
            .store(in: &profileViewModel.disposeBag)
        navigationController?.delegate = nil
        coordinator.present(scene: .profile(viewModel: profileViewModel), from: self, transition: .show)
    }
    
}

// MARK: - UserBriefInfoTableViewCellDelegate
extension SearchUserViewController: UserBriefInfoTableViewCellDelegate {
    
    func userBriefInfoTableViewCell(_ cell: UserBriefInfoTableViewCell, followActionButtonPressed button: FollowActionButton) {
        // prepare authentication
        guard let twitterAuthenticationBox = context.authenticationService.activeTwitterAuthenticationBox.value else {
            assertionFailure()
            return
        }
        
        guard let diffableDataSource = viewModel.diffableDataSource else { return }
        guard let indexPath = tableView.indexPath(for: cell) else { return }
        guard let item = diffableDataSource.itemIdentifier(for: indexPath) else { return }
        
        guard case let .twitterUser(objectID) = item else { return }
        let twitterUser = viewModel.fetchedResultsController.managedObjectContext.object(with: objectID) as! TwitterUser
        
        let requestTwitterUserID = twitterAuthenticationBox.twitterUserID
        let isPending = (twitterUser.followRequestSentFrom ?? Set()).contains(where: { $0.id == requestTwitterUserID })
        let isFollowing = (twitterUser.followingFrom ?? Set()).contains(where: { $0.id == requestTwitterUserID })
        
        if isPending || isFollowing {
            let name = twitterUser.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = isPending ? "Cancel following request for \(name)?" : "Unfollow user \(name)?"
            let alertController = UIAlertController(title: nil, message: message, preferredStyle: .actionSheet)
            let confirmAction = UIAlertAction(title: "Confirm", style: .destructive) { [weak self] _ in
                guard let self = self else { return }
                self.toggleFollowStatue(for: item, twitterAuthenticationBox: twitterAuthenticationBox)
            }
            let cancelAction = UIAlertAction(title: "Cancel", style: .cancel, handler: nil)
            alertController.addAction(confirmAction)
            alertController.addAction(cancelAction)
            alertController.popoverPresentationController?.sourceView = cell
            present(alertController, animated: true, completion: nil)
        } else {
            toggleFollowStatue(for: item, twitterAuthenticationBox: twitterAuthenticationBox)
        }
    }
    
    private func toggleFollowStatue(for item: Item, twitterAuthenticationBox: AuthenticationService.TwitterAuthenticationBox) {
        guard let diffableDataSource = viewModel.diffableDataSource else { return }
        guard let indexPath = diffableDataSource.indexPath(for: item) else { return }
        guard case let .twitterUser(objectID) = item else { return }

        let impactFeedbackGenerator = UIImpactFeedbackGenerator(style: .light)
        let notificationFeedbackGenerator = UINotificationFeedbackGenerator()
        context.apiService.friendship(
            twitterUserObjectID: objectID,
            twitterAuthenticationBox: twitterAuthenticationBox
        )
        .receive(on: DispatchQueue.main)
        .handleEvents { _ in
            notificationFeedbackGenerator.prepare()
            impactFeedbackGenerator.prepare()
        } receiveOutput: { _ in
            impactFeedbackGenerator.impactOccurred()
        } receiveCompletion: { completion in
            switch completion {
            case .failure(let error):
                // TODO: handle error
                break
            case .finished:
                // reload item
                DispatchQueue.main.async {
                    var snapshot = diffableDataSource.snapshot()
                    snapshot.reloadItems([item])
                    diffableDataSource.defaultRowAnimation = .none
                    diffableDataSource.apply(snapshot)
                    diffableDataSource.defaultRowAnimation = .automatic
                }
            }
        }
        .map { (friendshipQueryType, targetTwitterUserID) in
            self.context.apiService.friendship(
                friendshipQueryType: friendshipQueryType,
                twitterUserID: targetTwitterUserID,
                twitterAuthenticationBox: twitterAuthenticationBox
            )
        }
        .switchToLatest()
        .receive(on: DispatchQueue.main)
        .sink { [weak self] completion in
            guard let self = self else { return }
            if self.view.window != nil, (self.tableView.indexPathsForVisibleRows ?? []).contains(indexPath) {
                notificationFeedbackGenerator.notificationOccurred(.success)
            }
            switch completion {
            case .failure(let error):
                os_log("%{public}s[%{public}ld], %{public}s: [Friendship] remote friendship query fail: %{public}s", ((#file as NSString).lastPathComponent), #line, #function, error.localizedDescription)
            case .finished:
                os_log("%{public}s[%{public}ld], %{public}s: [Friendship] remote friendship query success", ((#file as NSString).lastPathComponent), #line, #function)
            }
        } receiveValue: { response in
            
        }
        .store(in: &disposeBag)
    }
    
}