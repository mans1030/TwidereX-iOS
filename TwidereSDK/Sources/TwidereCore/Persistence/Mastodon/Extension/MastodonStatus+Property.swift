//
//  MastodonStatus+Property.swift
//  MastodonStatus+Property
//
//  Created by Cirno MainasuK on 2021-8-27.
//  Copyright © 2021 Twidere. All rights reserved.
//

import Foundation
import CoreData
import CoreDataStack
import CoreGraphics
import MastodonSDK

extension MastodonStatus.Property {
    public init(
        entity: Mastodon.Entity.Status,
        domain: String,
        networkDate: Date
    ) {
        self.init(
            id: entity.id,
            domain: domain,
            uri: entity.uri,
            content: entity.content ?? "",
            likeCount: Int64(entity.favouritesCount),
            replyCount: entity.repliesCount.flatMap(Int64.init) ?? 0,
            repostCount: Int64(entity.reblogsCount),
            visibility: entity.mastodonVisibility,
            isMediaSensitive: entity.sensitive ?? false,
            spoilerText: entity.spoilerText,
            url: entity.url,
            text: entity.text,
            language: entity.language,
            source: entity.application?.name,
            replyToStatusID: entity.inReplyToID,
            replyToUserID: entity.inReplyToAccountID,
            createdAt: entity.createdAt,
            updatedAt: networkDate,
            attachments: entity.mastodonAttachments,
            emojis: entity.mastodonEmojis,
            mentions: entity.mastodonMentions
        )
    }
}

extension Mastodon.Entity.Status {
    public var mastodonAttachments: [MastodonAttachment] {
        guard let mediaAttachments = mediaAttachments else { return [] }
        
        let attachments = mediaAttachments.compactMap { media -> MastodonAttachment? in
            guard let kind = media.attachmentKind,
                  let meta = media.meta,
                  let original = meta.original
            else { return nil }

            // audio may not has width & height
            let width = original.width ?? 100
            let height = original.height ?? 100
            
            let durationMS: Int? = original.duration.flatMap { Int($0 * 1000) }
            return MastodonAttachment(
                id: media.id,
                kind: kind,
                size: CGSize(width: width, height: height),
                focus: nil,    // TODO:
                blurhash: media.blurhash,
                assetURL: media.url,
                previewURL: media.previewURL,
                textURL: media.textURL,
                durationMS: durationMS,
                altDescription: media.description
            )
        }
        
        return attachments
    }
}

extension Mastodon.Entity.Status: MastodonEmojiContainer { }

extension Mastodon.Entity.Attachment {
    public var attachmentKind: MastodonAttachment.Kind? {
        switch type {
        case .unknown:  return nil
        case .image:    return .image
        case .gifv:     return .gifv
        case .video:    return .video
        case .audio:    return .audio
        case ._other:   return nil
        }
    }
}

extension Mastodon.Entity.Status {
    public var mastodonVisibility: MastodonVisibility {
        let rawValue = visibility?.rawValue ?? ""
        return MastodonVisibility(rawValue: rawValue) ?? ._other(rawValue)
    }
}
