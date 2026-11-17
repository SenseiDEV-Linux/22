//
//  TopicRow.swift
//  SharedUI
//
//  Created by Ilia Lubianoi on 26.05.2025.
//

import SwiftUI
import SFSafeSymbols
import RichTextKit

public struct TopicRow: View {
    
    // MARK: - Properties
    
    @Environment(\.tintColor) private var tintColor
    
    public let title: UITitleType
    public let date: Date
    public let username: String
    public let isPinned: Bool
    public let isMoved: Bool
    public let isClosed: Bool
    public let isUnread: Bool
    public let isHatUpdated: Bool
    public let hasHatUpdateTracking: Bool
    public let onAction: (_ unreadTapped: Bool) -> Void
    
    // MARK: - Init
    
    public init(
        title: UITitleType,
        date: Date,
        username: String,
        isPinned: Bool = false,
        isMoved: Bool = false,
        isClosed: Bool,
        isUnread: Bool,
        isHatUpdated: Bool = false,
        hasHatUpdateTracking: Bool = false,
        onAction: @escaping (_ unreadTapped: Bool) -> Void
    ) {
        self.title = title
        self.date = date
        self.username = username
        self.isPinned = isPinned
        self.isMoved = isMoved
        self.isClosed = isClosed
        self.isUnread = isUnread
        self.isHatUpdated = isHatUpdated
        self.hasHatUpdateTracking = hasHatUpdateTracking
        self.onAction = onAction
    }
    
    // MARK: - Body
    
    public var body: some View {
        Button {
            onAction(false)
        } label: {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(date.formattedDate(), bundle: .module)
                        .font(.caption)
                        .foregroundStyle(Color(.Labels.teritary))
                    
                    switch title {
                    case .plain(let title):
                        Text(verbatim: title)
                            .font(.body)
                            .foregroundStyle(Color(.Labels.primary))
                    case .render(let attributedTitle):
                        RichText(text: attributedTitle, isSelectable: false)
                    }
                    
                    HStack(spacing: 4) {
                        Image(systemSymbol: .personCircle)
                            .font(.caption)
                            .foregroundStyle(Color(.Labels.secondary))
                        
                        RichText(
                            text: AttributedString(username),
                            isSelectable: false,
                            font: .caption,
                            foregroundStyle: Color(.Labels.secondary)
                        )
                    }
                }
                
                Spacer(minLength: 0)
                
                HStack(spacing: 0) {
                    if isPinned {
                        Image(systemSymbol: .pinFill)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 14, height: 14)
                            .foregroundStyle(tintColor)
                            .padding(.trailing, iconTrailingPadding(hasNextIcon: hasHatUpdateTracking || isClosed || isMoved))
                    }
                    
                    if hasHatUpdateTracking {
                        Image(systemSymbol: .bellFill)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(isHatUpdated ? .green : Color(.Main.greyAlpha))
                            .padding(.trailing, iconTrailingPadding(hasNextIcon: isClosed || isMoved))
                    }
                    
                    if isClosed {
                        Image(systemSymbol: .lock)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(Color(.Labels.secondary))
                            .padding(.trailing, iconTrailingPadding(hasNextIcon: isMoved))
                    }
                    
                    if isMoved {
                        Image(systemSymbol: .arrowRightCircle)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 16, height: 16)
                            .foregroundStyle(Color(.Labels.secondary))
                            .padding(.trailing, iconTrailingPadding(hasNextIcon: false))
                    }
                    
                    if isUnread {
                        Button {
                            onAction(true)
                        } label: {
                            Image(systemSymbol: .circleFill)
                                .resizable()
                                .scaledToFit()
                                .frame(width: 10, height: 10)
                                .foregroundStyle(tintColor)
                                .frame(maxWidth: 42, maxHeight: .infinity)
                                .padding(.vertical, -8)
                                .contentShape(.rect)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .listRowInsets(EdgeInsets(top: 0, leading: 16, bottom: 0, trailing: 0))
        .buttonStyle(.plain)
        .frame(minHeight: 60)
    }
    
    // MARK: - Helpers
    
    private func iconTrailingPadding(hasNextIcon: Bool) -> CGFloat {
        if hasNextIcon {
            return 8
        }
        return isUnread ? -2 : 12
    }
}

// MARK: - Previews

#Preview {
    List {
        TopicRow(
            title: .plain("Обсуждение клиента"),
            date: .now,
            username: "qwerty",
            isClosed: false,
            isUnread: true,
            onAction: { print($0 ? "Unread tapped" : "Row tapped") }
        )
        
        TopicRow(
            title: .plain("ForPDA [iOS]"),
            date: .now,
            username: "subvertd",
            isPinned: true,
            isClosed: false,
            isUnread: false,
            onAction: { print($0 ? "Unread tapped" : "Row tapped") }
        )
        
        TopicRow(
            title: .plain("Moved topic example"),
            date: .now,
            username: "qwerty",
            isMoved: true,
            isClosed: false,
            isUnread: false,
            onAction: { print($0 ? "Unread badge is unsupported in this case" : "Moved tapped") }
        )
        
        TopicRow(
            title: .plain("За особые достижения отмечены"),
            date: .now,
            username: "asdf",
            isClosed: true,
            isUnread: false,
            onAction: { print($0 ? "Unread tapped" : "Row tapped") }
        )
        
        TopicRow(
            title: .plain("Что нового было, пока вас не было?"),
            date: .now,
            username: "123456789",
            isClosed: true,
            isUnread: true,
            onAction: { print($0 ? "Unread tapped" : "Row tapped") }
        )
    }
    .environment(\.tintColor, Color(.Theme.primary))
}
