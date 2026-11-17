//
//  PinnedFavorites.swift
//  ForPDA
//
//  Created by SenseiDEV on 17.11.2026.
//

public struct PinnedFavorites: Codable, Equatable, Sendable {
    public var byUser: [Int: [FavoriteInfo]]
    
    private enum CodingKeys: String, CodingKey {
        case byUser
    }
    
    public init(byUser: [Int: [FavoriteInfo]] = [:]) {
        self.byUser = byUser
    }
    
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.byUser = try container.decodeIfPresent([Int: [FavoriteInfo]].self, forKey: .byUser) ?? [:]
    }
    
    public func topics(for userId: Int) -> [FavoriteInfo] {
        return (byUser[userId] ?? []).filter { !$0.isForum }
    }
    
    public func isPinned(topicId: Int, userId: Int) -> Bool {
        return byUser[userId]?.contains(where: { !$0.isForum && $0.id == topicId }) ?? false
    }
    
    public mutating func pin(_ favorite: FavoriteInfo, userId: Int) {
        guard !favorite.isForum else { return }
        var list = byUser[userId] ?? []
        if let index = list.firstIndex(where: { !$0.isForum && $0.id == favorite.id }) {
            list[index] = favorite
        } else {
            list.append(favorite)
        }
        byUser[userId] = list
    }
    
    public mutating func unpin(topicId: Int, userId: Int) {
        guard var list = byUser[userId] else { return }
        list.removeAll { !$0.isForum && $0.id == topicId }
        if list.isEmpty {
            byUser.removeValue(forKey: userId)
        } else {
            byUser[userId] = list
        }
    }
    
    public mutating func sync(
        with favorites: [FavoriteInfo],
        pruneMissing: Bool,
        userId: Int
    ) {
        guard let existing = byUser[userId], !existing.isEmpty else { return }
        let topicsById = Dictionary(
            favorites.lazy.filter { !$0.isForum }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        
        var updated: [FavoriteInfo] = []
        updated.reserveCapacity(existing.count)
        
        for item in existing where !item.isForum {
            if let fresh = topicsById[item.id] {
                updated.append(fresh)
            } else if !pruneMissing {
                updated.append(item)
            }
        }
        
        if updated.isEmpty {
            byUser.removeValue(forKey: userId)
        } else {
            byUser[userId] = updated
        }
    }
    
    public mutating func markRead(topicId: Int, userId: Int) {
        updateTopic(topicId: topicId, userId: userId) { $0.markingRead() }
    }
    
    public mutating func markAllRead(userId: Int) {
        guard var list = byUser[userId], !list.isEmpty else { return }
        for index in list.indices where !list[index].isForum {
            list[index] = list[index].markingRead()
        }
        byUser[userId] = list
    }
    
    public mutating func setImportant(topicId: Int, isImportant: Bool, userId: Int) {
        updateTopic(topicId: topicId, userId: userId) { $0.settingImportant(isImportant) }
    }
    
    public mutating func setNotify(topicId: Int, type: FavoriteNotifyType, userId: Int) {
        updateTopic(topicId: topicId, userId: userId) { $0.withNotify(type) }
    }
    
    public mutating func updateFromReadTopic(
        topicId: Int,
        name: String,
        description: String,
        isClosed: Bool,
        postsCount: Int,
        lastPost: TopicInfo.LastPost?,
        userId: Int
    ) {
        updateTopic(topicId: topicId, userId: userId) { item in
            var topicFlag = item.topic.flag
            topicFlag.remove(.updated)
            topicFlag.remove(.marker)
            if isClosed {
                topicFlag.insert(.closed)
            } else {
                topicFlag.remove(.closed)
            }
            return FavoriteInfo(
                flag: item.flag,
                topic: TopicInfo(
                    id: item.topic.id,
                    name: name,
                    description: description,
                    flag: topicFlag,
                    postsCount: postsCount,
                    lastPost: lastPost ?? item.topic.lastPost
                ),
                isForum: false
            )
        }
    }
    
    private mutating func updateTopic(
        topicId: Int,
        userId: Int,
        transform: (FavoriteInfo) -> FavoriteInfo
    ) {
        guard var list = byUser[userId],
              let index = list.firstIndex(where: { !$0.isForum && $0.id == topicId })
        else { return }
        list[index] = transform(list[index])
        byUser[userId] = list
    }
}

public extension PinnedFavorites {
    static let `default` = PinnedFavorites()
}
