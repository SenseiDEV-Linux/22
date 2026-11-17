//
//  QMSMessageRowView.swift
//  ForPDA
//
//  Created by Ilia Lubianoi on 17.11.2026.
//

import ExyteChat
import NukeUI
import SFSafeSymbols
import SharedUI
import SwiftUI
import UIKit

struct QMSMessageRowView: View {

    // MARK: - Layout

    private enum Layout {
        static let avatarSize: CGFloat = 32
        static let screenEdgePadding: CGFloat = 12
        static let noAvatarPadding: CGFloat = 6
        static let avatarTrailingPadding: CGFloat = 8
        static let textHorizontalPadding: CGFloat = 12
        static let attachmentInset: CGFloat = 3
        static let captionedAttachmentInset: CGFloat = 4
        static let statusWidth: CGFloat = 14
        static let statusHeight: CGFloat = 10
        static let statusLeadingPadding: CGFloat = 2
        static let statusTrailingPadding: CGFloat = 6
        static let bubbleOppositePadding: CGFloat = 70
        static let selectionIconSize: CGFloat = 22
        static let selectionTrailingSpacing: CGFloat = 10
        static let selectionShift: CGFloat = selectionIconSize + selectionTrailingSpacing
        static let inlineTimestampMaxLength = 24
    }

    // MARK: - Properties

    @Environment(\.chatTheme) private var theme

    let message: ExyteChat.Message
    let positionInGroup: PositionInUserGroup
    let positionInMessagesSection: PositionInMessagesSection
    let tintColor: Color
    let isSelecting: Bool
    let isSelected: Bool
    let isInteractionDisabled: Bool
    let onToggleSelection: () -> Void
    let onShowContextMenu: () -> Void
    let onTapAttachment: (ExyteChat.Attachment) -> Void

    private var isCurrentUser: Bool {
        message.user.isCurrentUser
    }

    private var showAvatar: Bool {
        positionInGroup == .single || positionInGroup == .last
    }

    private var topPadding: CGFloat {
        let isGroupTop = positionInGroup == .first || positionInGroup == .single
        let isSectionTop = positionInMessagesSection == .first || positionInMessagesSection == .single
        return isGroupTop && !isSectionTop ? 6 : 2
    }

    private var timeText: String {
        message.createdAt.formatted(date: .omitted, time: .shortened)
    }

    private var messageFont: Font {
        Font(UIFontMetrics.default.scaledFont(for: UIFont.systemFont(ofSize: 15)))
    }

    private var shouldInlineTimestamp: Bool {
        message.attachments.isEmpty
            && !message.text.contains("\n")
            && message.text.count <= Layout.inlineTimestampMaxLength
    }

    // MARK: - Body

    var body: some View {
        if isSelecting {
            selectionRow
        } else {
            standardRow
        }
    }

    private var selectionRow: some View {
        rowContent
            .allowsHitTesting(false)
            .padding(.top, topPadding)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity)
            .background(isSelected ? tintColor.opacity(0.12) : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture {
                guard !isInteractionDisabled else { return }
                UISelectionFeedbackGenerator().selectionChanged()
                onToggleSelection()
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var standardRow: some View {
        rowContent
            .padding(.top, topPadding)
            .padding(.bottom, 2)
            .frame(maxWidth: .infinity)
            .simultaneousGesture(
                TapGesture().onEnded {}
            )
            .onLongPressGesture {
                guard !isInteractionDisabled else { return }
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                onShowContextMenu()
            }
    }

    @ViewBuilder
    private var rowContent: some View {
        if isCurrentUser {
            ownMessageRow
        } else {
            partnerMessageRow
        }
    }

    private var ownMessageRow: some View {
        HStack(alignment: .center, spacing: 0) {
            if isSelecting {
                selectionIndicator
                    .padding(.leading, Layout.screenEdgePadding)
                Spacer(
                    minLength: Layout.bubbleOppositePadding
                        - Layout.screenEdgePadding
                        - Layout.selectionIconSize
                )
            } else {
                Spacer(minLength: Layout.bubbleOppositePadding)
            }

            HStack(alignment: .bottom, spacing: 0) {
                bubbleView
                if let status = message.status {
                    statusView(for: status)
                }
            }
            .padding(.trailing, Layout.noAvatarPadding)
        }
    }

    private var partnerMessageRow: some View {
        HStack(alignment: .center, spacing: 0) {
            if isSelecting {
                selectionIndicator
                    .padding(.leading, Layout.screenEdgePadding)
                    .padding(.trailing, Layout.selectionTrailingSpacing)
            }

            HStack(alignment: .bottom, spacing: 0) {
                avatarView
                    .padding(.leading, isSelecting ? 0 : Layout.screenEdgePadding)
                    .padding(.trailing, Layout.avatarTrailingPadding)
                bubbleView
            }

            Spacer(
                minLength: isSelecting
                    ? Layout.bubbleOppositePadding - Layout.selectionShift
                    : Layout.bubbleOppositePadding
            )
        }
    }

    private var selectionIndicator: some View {
        Image(systemSymbol: isSelected ? .checkmarkCircleFill : .circle)
            .font(.system(size: Layout.selectionIconSize))
            .foregroundStyle(isSelected ? tintColor : Color(.Labels.teritary))
            .frame(width: Layout.selectionIconSize, height: Layout.selectionIconSize)
    }

    // MARK: - Avatar

    @ViewBuilder
    private var avatarView: some View {
        if showAvatar {
            LazyImage(url: message.user.avatarURL) { state in
                if let image = state.image {
                    image
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(.avatarDefault)
                        .resizable()
                        .scaledToFill()
                }
            }
            .frame(width: Layout.avatarSize, height: Layout.avatarSize)
            .clipShape(Circle())
        } else {
            Color.clear
                .frame(width: Layout.avatarSize, height: Layout.avatarSize)
        }
    }

    // MARK: - Bubble

    private var attachmentPadding: CGFloat {
        if !message.text.isEmpty {
            return Layout.captionedAttachmentInset
        }
        return message.attachments.count > 1 ? Layout.attachmentInset : 0
    }

    private var attachmentsContainerWidth: CGFloat {
        guard !message.attachments.isEmpty else { return 0 }
        return QMSAttachmentsGrid.Metrics.gridWidth(for: message.attachments.count)
            + attachmentPadding * 2
    }

    private var bubbleView: some View {
        let hasAttachments = !message.attachments.isEmpty
        let hasText = !message.text.isEmpty
        let cornerRadius: CGFloat = hasAttachments ? 12 : 20
        let bubbleBackground = isCurrentUser ? theme.colors.messageMyBG : theme.colors.messageFriendBG
        let bubbleTextColor = isCurrentUser ? theme.colors.messageMyText : theme.colors.messageFriendText

        return VStack(alignment: .leading, spacing: 0) {
            if hasAttachments {
                attachmentsView
            }
            if hasText {
                textWithTimeView
                    .font(messageFont)
            } else if !hasAttachments {
                plainTimeView
                    .padding(.horizontal, Layout.textHorizontalPadding)
                    .padding(.vertical, 8)
            }
        }
        .foregroundStyle(bubbleTextColor)
        .background {
            RoundedRectangle(cornerRadius: cornerRadius)
                .fill(bubbleBackground)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var attachmentsView: some View {
        let hasText = !message.text.isEmpty
        let padding = attachmentPadding
        let showsCapsuleTimestamp = !hasText

        return QMSAttachmentsGrid(
            attachments: message.attachments,
            roundsSingleAttachment: hasText,
            onTap: onTapAttachment
        )
        .padding(.top, padding)
        .padding(.horizontal, padding)
        .padding(.bottom, hasText ? 0 : padding)
        .overlay(alignment: .bottomTrailing) {
            if showsCapsuleTimestamp {
                capsuleTimeView
                    .padding(padding + 4)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private var textWithTimeView: some View {
        if shouldInlineTimestamp {
            HStack(alignment: .lastTextBaseline, spacing: 10) {
                styledMessageText
                plainTimeView
            }
            .padding(.horizontal, Layout.textHorizontalPadding)
            .padding(.vertical, 8)
        } else {
            let minContentWidth = max(
                0,
                attachmentsContainerWidth - Layout.textHorizontalPadding * 2
            )
            VStack(alignment: .trailing, spacing: 4) {
                styledMessageText
                    .frame(
                        minWidth: message.attachments.isEmpty ? nil : minContentWidth,
                        alignment: .leading
                    )
                plainTimeView
            }
            .padding(.horizontal, Layout.textHorizontalPadding)
            .padding(.vertical, 8)
        }
    }

    private var styledMessageText: some View {
        var attributed = QMSBuilder(text: message.text, tintColor: UIColor(tintColor)).build()
        for (link, range) in attributed.runs[\.link] where link != nil {
            attributed[range].underlineStyle = Text.LineStyle.single
        }
        return Text(attributed)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var plainTimeView: some View {
        let timeColor = isCurrentUser ? theme.colors.messageMyTimeText : theme.colors.messageFriendTimeText
        return Text(timeText)
            .font(.caption)
            .foregroundStyle(timeColor)
    }

    private var capsuleTimeView: some View {
        Text(timeText)
            .font(.caption2)
            .lineLimit(1)
            .foregroundStyle(Color.white.opacity(0.9))
            .padding(.vertical, 2)
            .padding(.horizontal, 6)
            .background {
                Capsule()
                    .fill(Color.black.opacity(0.45))
            }
    }

    // MARK: - Status

    private func statusView(for status: ExyteChat.Message.Status) -> some View {
        let iconAndColor: (Image, Color) = switch status {
        case .sending:
            (theme.images.message.sending, theme.colors.statusGray)
        case .sent:
            (theme.images.message.sent, theme.colors.statusGray)
        case .delivered:
            (theme.images.message.delivered, theme.colors.statusGray)
        case .read:
            (theme.images.message.read, theme.colors.messageReadStatus)
        case .error:
            (theme.images.message.error, theme.colors.statusError)
        }

        return iconAndColor.0
            .renderingMode(.template)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .foregroundStyle(iconAndColor.1)
            .frame(width: Layout.statusWidth, height: Layout.statusHeight)
            .padding(.leading, Layout.statusLeadingPadding)
            .padding(.trailing, Layout.statusTrailingPadding)
    }
}

// MARK: - Attachments Grid

private struct QMSAttachmentsGrid: View {

    enum Metrics {
        static let maxColumns = 4
        static let maxRows = 3
        static let singleSize = CGSize(width: 132, height: 108)
        static let tileSize: CGFloat = 60
        static let spacing: CGFloat = 4
        static let tileCornerRadius: CGFloat = 8

        static var gridWidth: CGFloat {
            CGFloat(maxColumns) * tileSize + CGFloat(maxColumns - 1) * spacing
        }

        static var gridHeight: CGFloat {
            CGFloat(maxRows) * tileSize + CGFloat(maxRows - 1) * spacing
        }

        static func gridWidth(for attachmentCount: Int) -> CGFloat {
            switch attachmentCount {
            case ...0:
                return 0
            case 1:
                return singleSize.width
            case 2, 3:
                return CGFloat(attachmentCount) * tileSize
                    + CGFloat(attachmentCount - 1) * spacing
            default:
                return gridWidth
            }
        }
    }

    private let attachments: [ExyteChat.Attachment]
    private let single: ExyteChat.Attachment?
    private let roundsSingleAttachment: Bool
    private let onTap: (ExyteChat.Attachment) -> Void

    init(
        attachments: [ExyteChat.Attachment],
        roundsSingleAttachment: Bool,
        onTap: @escaping (ExyteChat.Attachment) -> Void
    ) {
        self.attachments = attachments
        self.roundsSingleAttachment = roundsSingleAttachment
        self.onTap = onTap
        self.single = attachments.count == 1 ? attachments[0] : nil
    }

    var body: some View {
        if let single {
            singleAttachmentView(single)
        } else if attachments.count <= 3 {
            HStack(spacing: Metrics.spacing) {
                ForEach(attachments, id: \.id) { attachment in
                    gridTile(attachment)
                }
            }
        } else {
            scrollableGrid
        }
    }

    private var scrollableGrid: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHGrid(
                rows: Array(
                    repeating: GridItem(.fixed(Metrics.tileSize), spacing: Metrics.spacing),
                    count: Metrics.maxRows
                ),
                spacing: Metrics.spacing
            ) {
                ForEach(attachments, id: \.id) { attachment in
                    gridTile(attachment)
                }
            }
        }
        .frame(width: Metrics.gridWidth, height: Metrics.gridHeight)
        .scrollIndicators(.hidden)
    }

    private func singleAttachmentView(_ attachment: ExyteChat.Attachment) -> some View {
        AttachmentCell(
            attachment: attachment,
            size: Metrics.singleSize,
            showCancel: false
        ) { tapped, _ in
            onTap(tapped)
        }
        .clipped()
        .clipShape(
            RoundedRectangle(
                cornerRadius: roundsSingleAttachment ? Metrics.tileCornerRadius : 0
            )
        )
    }

    private func gridTile(_ attachment: ExyteChat.Attachment) -> some View {
        AttachmentCell(
            attachment: attachment,
            size: CGSize(width: Metrics.tileSize, height: Metrics.tileSize),
            showCancel: false
        ) { tapped, _ in
            onTap(tapped)
        }
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: Metrics.tileCornerRadius))
    }
}
