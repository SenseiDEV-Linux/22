//
//  FavoriteTopicContextMenuAction.swift
//  ForPDA
//
//  Created by Xialtal on 2.01.25.
//

import Models

public enum FavoriteTopicContextMenuAction: Sendable {
    case setPinned(Bool)
    case goToFirst
    case goToEnd
    case notify(Int, FavoriteNotifyType)
    case notifyHatUpdate(Int)
}
