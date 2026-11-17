//
//  FavoriteInfo.swift
//  ForPDA
//
//  Created by Xialtal on 8.11.24.
//

public struct FavoriteInfo: Codable, Identifiable, Hashable, Sendable {
    public var id: Int {
        return topic.id
    }
    public let flag: Int
    public let topic: TopicInfo
    public let isForum: Bool
    
    public enum Notify {
        case always
        case once
        case doNot
    }
    
    public var notify: Notify {
        return switch (flag & 3) {
            case 2: .doNot
            case 1: .once
            default: .always
        }
    }

    public var isHatUpdated: Bool {
        return (flag & 4 != 0) && topic.flag.contains(.marker)
    }
    
    public var isNotifyHatUpdate: Bool {
        return (flag & 4) > 0
    }
    
    public var isImportant: Bool {
        return topic.flag.contains(.pinned)
    }
    
    public init(
        flag: Int,
        topic: TopicInfo,
        isForum: Bool
    ) {
        self.flag = flag
        self.topic = topic
        self.isForum = isForum
    }
    
    public func with(
        flag: Int? = nil,
        topicFlag: ForumFlag? = nil
    ) -> FavoriteInfo {
        return FavoriteInfo(
            flag: flag ?? self.flag,
            topic: TopicInfo(
                id: topic.id,
                name: topic.name,
                description: topic.description,
                flag: topicFlag ?? topic.flag,
                postsCount: topic.postsCount,
                lastPost: topic.lastPost
            ),
            isForum: isForum
        )
    }
    
    public func markingRead() -> FavoriteInfo {
        var updatedFlag = topic.flag
        updatedFlag.remove(.updated)
        updatedFlag.remove(.marker)
        return with(topicFlag: updatedFlag)
    }
    
    public func settingImportant(_ isImportant: Bool) -> FavoriteInfo {
        var updatedFlag = topic.flag
        if isImportant {
            updatedFlag.insert(.pinned)
        } else {
            updatedFlag.remove(.pinned)
        }
        return with(topicFlag: updatedFlag)
    }
    
    public func withNotify(_ type: FavoriteNotifyType) -> FavoriteInfo {
        let newFlag: Int = switch type {
        case .always:
            flag & ~3
        case .once:
            (flag & ~3) | 1
        case .doNot:
            (flag & ~3) | 2
        case .hatUpdate:
            flag ^ 4
        }
        return with(flag: newFlag)
    }
}

public extension FavoriteInfo {
    static let mock = FavoriteInfo(
        flag: 0,
        topic: .mockToday,
        isForum: false
    )
    
    static let mockUnread = FavoriteInfo(
        flag: 0,
        topic: .mockTodayUnread,
        isForum: false
    )
}
