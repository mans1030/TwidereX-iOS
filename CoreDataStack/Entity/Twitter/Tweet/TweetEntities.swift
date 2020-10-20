//
//  TweetEntities.swift
//  CoreDataStack
//
//  Created by Cirno MainasuK on 2020-10-20.
//  Copyright © 2020 Twidere. All rights reserved.
//

import Foundation
import CoreData
import TwitterAPI

final public class TweetEntities: NSManagedObject {
        
    @NSManaged public private(set) var identifier: UUID
    
    // one-to-many relationship
    @NSManaged public private(set) var annotations: Set<TweetEntitiesAnnotation>?
    @NSManaged public private(set) var cashtags: Set<TweetEntitiesCashtag>?
    @NSManaged public private(set) var hashtags: Set<TweetEntitiesHashtag>?
    @NSManaged public private(set) var mentions: Set<TweetEntitiesMention>?
    @NSManaged public private(set) var urls: Set<TweetEntitiesURL>?
    
    // one-to-one relationship
    @NSManaged public private(set) var tweet: Tweet?
    
}

extension TweetEntities {
    
    public override func awakeFromInsert() {
        super.awakeFromInsert()
        identifier = UUID()
    }
    
}

extension TweetEntities {

}

extension TweetEntities: Managed {
    public static var defaultSortDescriptors: [NSSortDescriptor] {
        return [NSSortDescriptor(keyPath: \TweetEntities.identifier, ascending: false)]
    }
}