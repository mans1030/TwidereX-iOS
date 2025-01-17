//
//  UserSection.swift
//  UserSection
//
//  Created by Cirno MainasuK on 2021-8-25.
//  Copyright © 2021 Twidere. All rights reserved.
//

import UIKit
import Combine
import CoreDataStack
import TwidereUI

enum UserSection {
    case main
}

extension UserSection {
    
    struct Configuration {
        weak var userViewTableViewCellDelegate: UserViewTableViewCellDelegate?
        let userViewConfigurationContext: UserView.ConfigurationContext
    }
    
    static func diffableDataSource(
        tableView: UITableView,
        context: AppContext,
        configuration: Configuration
    ) -> UITableViewDiffableDataSource<UserSection, UserItem> {
        let cellTypes = [
            UserAccountStyleTableViewCell.self,
            UserRelationshipStyleTableViewCell.self,
            UserFriendshipStyleTableViewCell.self,
            UserMentionPickStyleTableViewCell.self,
            UserNotificationStyleTableViewCell.self,
            UserListMemberStyleTableViewCell.self,
            UserAddListMemberStyleTableViewCell.self,
            TimelineBottomLoaderTableViewCell.self,
        ]
            
        cellTypes.forEach { type in
            tableView.register(type, forCellReuseIdentifier: String(describing: type))
        }
        
        return UITableViewDiffableDataSource<UserSection, UserItem>(tableView: tableView) { tableView, indexPath, item in
            // data source should dispatch in main thread
            assert(Thread.isMainThread)
            
            // configure cell with item
            switch item {
            case .authenticationIndex(let record):
                let cell = tableView.dequeueReusableCell(withIdentifier: String(describing: UserAccountStyleTableViewCell.self), for: indexPath) as! UserAccountStyleTableViewCell
                context.managedObjectContext.performAndWait {
                    guard let authenticationIndex = record.object(in: context.managedObjectContext) else { return }
                    guard let me = authenticationIndex.user else { return }
                    let viewModel = UserTableViewCell.ViewModel(
                        user: me,
                        me: me,
                        notification: nil
                    )
                    configure(
                        cell: cell,
                        viewModel: viewModel,
                        configuration: configuration
                    )
                }
                return cell
            case .user(let record, let style):
                let cell = dequeueReusableCell(tableView: tableView, indexPath: indexPath, style: style)
                context.managedObjectContext.performAndWait {
                    guard let user = record.object(in: context.managedObjectContext) else { return }
                    let authenticationContext = context.authenticationService.activeAuthenticationContext
                    let me = authenticationContext?.user(in: context.managedObjectContext)
                    let viewModel = UserTableViewCell.ViewModel(
                        user: user,
                        me: me,
                        notification: nil
                    )
                    configure(
                        cell: cell,
                        viewModel: viewModel,
                        configuration: configuration
                    )
                }
                return cell
            case .bottomLoader:
                let cell = tableView.dequeueReusableCell(withIdentifier: String(describing: TimelineBottomLoaderTableViewCell.self), for: indexPath) as! TimelineBottomLoaderTableViewCell
                cell.activityIndicatorView.startAnimating()
                return cell
            }
        }
    }
    
}

extension UserSection {
    
    static func dequeueReusableCell(
        tableView: UITableView,
        indexPath: IndexPath,
        style: UserView.Style
    ) -> UserTableViewCell {
        switch style {
        case .account:
            return tableView.dequeueReusableCell(withIdentifier: String(describing: UserAccountStyleTableViewCell.self), for: indexPath) as! UserAccountStyleTableViewCell
        case .relationship:
            return tableView.dequeueReusableCell(withIdentifier: String(describing: UserRelationshipStyleTableViewCell.self), for: indexPath) as! UserRelationshipStyleTableViewCell
        case .friendship:
            return tableView.dequeueReusableCell(withIdentifier: String(describing: UserFriendshipStyleTableViewCell.self), for: indexPath) as! UserFriendshipStyleTableViewCell
        case .notification:
            return tableView.dequeueReusableCell(withIdentifier: String(describing: UserNotificationStyleTableViewCell.self), for: indexPath) as! UserNotificationStyleTableViewCell
        case .mentionPick:
            return tableView.dequeueReusableCell(withIdentifier: String(describing: UserMentionPickStyleTableViewCell.self), for: indexPath) as! UserMentionPickStyleTableViewCell
        case .listMember:
            return tableView.dequeueReusableCell(withIdentifier: String(describing: UserListMemberStyleTableViewCell.self), for: indexPath) as! UserListMemberStyleTableViewCell
        case .addListMember:
            return tableView.dequeueReusableCell(withIdentifier: String(describing: UserAddListMemberStyleTableViewCell.self), for: indexPath) as! UserAddListMemberStyleTableViewCell
        }
    }
    
    static func configure(
        cell: UserTableViewCell,
        viewModel: UserTableViewCell.ViewModel,
        configuration: Configuration
    ) {
        cell.configure(
            viewModel: viewModel,
            configurationContext: configuration.userViewConfigurationContext,
            delegate: configuration.userViewTableViewCellDelegate
        )
    }
}
