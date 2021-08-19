//
//  FeedFetchedResultsController.swift
//  FeedFetchedResultsController
//
//  Created by Cirno MainasuK on 2021-8-19.
//  Copyright © 2021 Twidere. All rights reserved.
//

import os.log
import Foundation
import UIKit
import Combine
import CoreData
import CoreDataStack
import TwitterSDK

final class FeedFetchedResultsController: NSObject {
    
    var disposeBag = Set<AnyCancellable>()
    
    let fetchedResultsController: NSFetchedResultsController<Feed>
    
    // input
    let predicate: CurrentValueSubject<NSPredicate?, Never>
    
    // output
    let objectIDs = CurrentValueSubject<[NSManagedObjectID], Never>([])
    
    init(managedObjectContext: NSManagedObjectContext) {
        self.fetchedResultsController = {
            let fetchRequest = Feed.sortedFetchRequest
            // make sure initial query return empty results
            fetchRequest.returnsObjectsAsFaults = false
            fetchRequest.fetchBatchSize = 15
            let controller = NSFetchedResultsController(
                fetchRequest: fetchRequest,
                managedObjectContext: managedObjectContext,
                sectionNameKeyPath: nil,
                cacheName: nil
            )
            
            return controller
        }()
        self.predicate = CurrentValueSubject(Feed.predicate(kind: .home, acct: Feed.Acct.twitter(userID: "")))
        super.init()
        
        fetchedResultsController.delegate = self
        
        predicate.removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] predicate in
                guard let self = self else { return }
                self.fetchedResultsController.fetchRequest.predicate = predicate
                do {
                    try self.fetchedResultsController.performFetch()
                } catch {
                    assertionFailure(error.localizedDescription)
                }
            }
            .store(in: &disposeBag)
    }
    
}

// MARK: - NSFetchedResultsControllerDelegate
extension FeedFetchedResultsController: NSFetchedResultsControllerDelegate {
    func controller(
        _ controller: NSFetchedResultsController<NSFetchRequestResult>,
        didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference
    ) {
        os_log("%{public}s[%{public}ld], %{public}s", ((#file as NSString).lastPathComponent), #line, #function)
        let snapshot = snapshot as NSDiffableDataSourceSnapshot<String, NSManagedObjectID>
        self.objectIDs.value = snapshot.itemIdentifiers
    }
}

