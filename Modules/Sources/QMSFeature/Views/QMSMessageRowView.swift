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
        static let mediaWidth: CGFloat = 204
        static let screenEdgePadding: CGFloat = 12
        static let noAvatarPadding: CGFloat = 6
        static let avatarTrailingPadding: CGFloat = 8
        static let textHorizontalPadding: CGFloat = 12
        static let multiAttachmentPadding: CGFloat = 1
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

    private var bubbleView: some View {
        let hasAttachments = !message.attachments.isEmpty
        let cornerRadius: CGFloat = hasAttachments ? 12 : 20
        let mediaInset: CGFloat = message.attachments.count > 1 ? Layout.multiAttachmentPadding * 2 : 0
        let bubbleBackground = isCurrentUser ? theme.colors.messageMyBG : theme.colors.messageFriendBG
        let bubbleTextColor = isCurrentUser ? theme.colors.messageMyText : theme.colors.messageFriendText

        return VStack(alignment: .leading, spacing: 0) {
            if hasAttachments {
                attachmentsView
            }
            if !message.text.isEmpty {
                textWithTimeView
                    .font(messageFont)
            } else if !hasAttachments {
                plainTimeView
                    .padding(.horizontal, Layout.textHorizontalPadding)
                    .padding(.vertical, 8)
            }
        }
        .frame(width: hasAttachments ? Layout.mediaWidth + mediaInset : nil)
        .foregroundStyle(bubbleTextColor)
        .background {
            if !message.text.isEmpty || !hasAttachments {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(bubbleBackground)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var attachmentsView: some View {
        let padding: CGFloat = message.attachments.count > 1 ? Layout.multiAttachmentPadding : 0
        return QMSAttachmentsGrid(
            attachments: message.attachments,
            onTap: onTapAttachment
        )
        .padding(.top, padding)
        .padding(.horizontal, padding)
        .overlay(alignment: .bottomTrailing) {
            if message.text.isEmpty {
                capsuleTimeView
                    .padding(4)
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
            VStack(alignment: .trailing, spacing: 4) {
                styledMessageText
                    .frame(
                        maxWidth: message.attachments.isEmpty ? nil : .infinity,
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
            .font(.caption)
            .foregroundStyle(Color.white.opacity(0.8))
            .padding(.vertical, 4)
            .padding(.horizontal, 8)
            .background {
                Capsule()
                    .fill(Color.black.opacity(0.4))
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

    private struct Pair: Identifiable {
        let left: ExyteChat.Attachment
        let right: ExyteChat.Attachment

        var id: String {
            left.id + "+" + right.id
        }
    }

    private static let maxVisibleCount = 4

    private let single: ExyteChat.Attachment?
    private let pairs: [Pair]
    private let isOnlyOne: Bool
    private let hiddenCountText: String?
    private let hiddenOverlayAttachmentId: String?
    private let onTap: (ExyteChat.Attachment) -> Void

    init(
        attachments: [ExyteChat.Attachment],
        onTap: @escaping (ExyteChat.Attachment) -> Void
    ) {
        let visible = Array(attachments.prefix(Self.maxVisibleCount))
        if attachments.count > Self.maxVisibleCount {
            self.hiddenCountText = "+\(attachments.count - (Self.maxVisibleCount - 1))"
            self.hiddenOverlayAttachmentId = visible.last?.id
        } else {
            self.hiddenCountText = nil
            self.hiddenOverlayAttachmentId = nil
        }

        let gridItems: [ExyteChat.Attachment]
        if visible.count.isMultiple(of: 2) {
            self.single = nil
            gridItems = visible
        } else {
            self.single = visible.first
            gridItems = Array(visible.dropFirst())
        }

        self.pairs = stride(from: 0, to: gridItems.count, by: 2).compactMap { index in
            guard index + 1 < gridItems.count else { return nil }
            return Pair(left: gridItems[index], right: gridItems[index + 1])
        }
        self.isOnlyOne = attachments.count == 1
        self.onTap = onTap
    }

    var body: some View {
        VStack(spacing: 4) {
            if let single {
                AttachmentCell(
                    attachment: single,
                    size: CGSize(width: 204, height: pairs.isEmpty ? 200 : 100),
                    showCancel: false
                ) { tapped, _ in
                    onTap(tapped)
                }
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: isOnlyOne ? 0 : 12))
            }

            ForEach(pairs) { pair in
                pairRow(pair)
            }
        }
    }

    private func pairRow(_ pair: Pair) -> some View {
        HStack(spacing: 4) {
            AttachmentCell(
                attachment: pair.left,
                size: CGSize(width: 100, height: 100),
                showCancel: false
            ) { tapped, _ in
                onTap(tapped)
            }
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 12))

            AttachmentCell(
                attachment: pair.right,
                size: CGSize(width: 100, height: 100),
                showCancel: false
            ) { tapped, _ in
                onTap(tapped)
            }
            .clipped()
            .overlay {
                if pair.right.id == hiddenOverlayAttachmentId, let hiddenCountText {
                    moreCountOverlay(hiddenCountText)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }

    private func moreCountOverlay(_ text: String) -> some View {
        ZStack {
            RadialGradient(
                colors: [.black.opacity(0.8), .black.opacity(0.6)],
                center: .center,
                startRadius: 0,
                endRadius: 90
            )
            Text(text)
                .font(.body.bold())
                .foregroundStyle(.white)
        }
        .allowsHitTesting(false)
    }
}
