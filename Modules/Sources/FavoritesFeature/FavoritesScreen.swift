//
//  FavoritesScreen.swift
//  ForPDA
//
//  Created by Xialtal on 8.11.24.
//

import SwiftUI
import ComposableArchitecture
import PageNavigationFeature
import SFSafeSymbols
import SharedUI
import Models

@ViewAction(for: FavoritesFeature.self)
public struct FavoritesScreen: View {
    
    // MARK: - Section Kind
    
    private enum SectionKind {
        case pinned
        case important
        case regular
        
        var headerTitle: LocalizedStringKey {
            switch self {
            case .pinned: return LocalizedStringKey("Pinned")
            case .important: return LocalizedStringKey("Important")
            case .regular: return LocalizedStringKey("Topics / Forums")
            }
        }
    }
    
    // MARK: - Properties
    
    @Perception.Bindable public var store: StoreOf<FavoritesFeature>
    @State private var navigationMinimized = false
    @Environment(\.tintColor) private var tintColor
    @Environment(\.backgroundColors) private var backgroundColors
    
    private var shouldShowInlineNavigation: Bool {
        let isAnyFloatingNavigationEnabled = store.appSettings.floatingNavigation || store.appSettings.experimentalFloatingNavigation
        return store.pageNavigation.shouldShow && (!isLiquidGlass || !isAnyFloatingNavigationEnabled)
    }
    
    private var shouldShowFloatingNavigation: Bool {
        return isLiquidGlass && store.appSettings.floatingNavigation && !store.appSettings.experimentalFloatingNavigation
    }
    
    // MARK: - Init

    public init(store: StoreOf<FavoritesFeature>) {
        self.store = store
    }
    
    // MARK: - Body
    
    public var body: some View {
        WithPerceptionTracking {
            ZStack {
                backgroundColors.primary
                    .ignoresSafeArea()

                if store.shouldShowEmptyState {
                    EmptyFavorites()
                } else if !store.isLoading {
                    List {
                        if !store.favoritesPinned.isEmpty {
                            FavoritesSection(favorites: store.favoritesPinned, kind: .pinned)
                        }
                        
                        if !store.favoritesImportant.isEmpty {
                            FavoritesSection(favorites: store.favoritesImportant, kind: .important)
                        }
                        
                        if !store.favorites.isEmpty || shouldShowInlineNavigation {
                            FavoritesSection(favorites: store.favorites, kind: .regular)
                        }
                    }
                    .scrollContentBackground(.hidden)
                    ._inScrollContentDetector(isEnabled: shouldShowFloatingNavigation, state: $navigationMinimized)
                    .refreshable {
                        await send(.onRefresh).finish()
                    }
                } else {
                    PDALoader()
                        .frame(width: 24, height: 24)
                }
            }
            .navigationTitle(Text("Favorites", bundle: .module))
            ._toolbarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) {
                if shouldShowFloatingNavigation {
                    PageNavigation(
                        store: store.scope(\.pageNavigation, action: \.pageNavigation),
                        minimized: $navigationMinimized
                    )
                    .padding(.horizontal, 16)
                    .padding(.bottom, 8)
                }
            }
            .animation(.default, value: store.favoritesPinned)
            .animation(.default, value: store.favoritesImportant)
            .animation(.default, value: store.favorites)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    if store.isUserAuthorized {
                        Menu {
                            ContextButton(
                                text: LocalizedStringResource("Sort", bundle: .module),
                                symbol: .line3HorizontalDecrease
                            ) {
                                send(.contextOptionMenu(.sort))
                            }
                            
                            ContextButton(
                                text: LocalizedStringResource("Read All", bundle: .module),
                                symbol: .checkmarkCircle
                            ) {
                                send(.contextOptionMenu(.markAllAsRead))
                            }
                        } label: {
                            Image(systemSymbol: .ellipsisCircle)
                        }
                    }
                }
            }
            .fittedSheet(
                item: $store.scope(\.$sort, action: \.sort),
                embedIntoNavStack: true
            ) { store in
                SortView(store: store)
            }
            .onFirstAppear {
                send(.onFirstAppear)
            } onNextAppear: {
                send(.onNextAppear)
            }
        }
    }
    
    // MARK: - Options Menu
    
    private func CommonContextMenu(favorite: FavoriteInfo) -> some View {
        VStack(spacing: 0) {
            Section {
                ContextButton(
                    text: favorite.isImportant
                    ? LocalizedStringResource("From Important", bundle: .module)
                    : LocalizedStringResource("To Important", bundle: .module),
                    symbol: favorite.isImportant ? .heartFill : .heart
                ) {
                    send(.commonContextMenu(
                        .setImportant(favorite.topic.id, favorite.isImportant ? false : true),
                        favorite.isForum
                    ))
                }
                
                if favorite.topic.isUnread {
                    ContextButton(
                        text: LocalizedStringResource("Mark As Read", bundle: .module),
                        symbol: .checkmarkCircle
                    ) {
                        send(.commonContextMenu(.markRead(favorite.id), favorite.isForum))
                    }
                }
            }
            
            Section {
                ContextButton(text: LocalizedStringResource("Copy Link", bundle: .module), symbol: .docOnDoc) {
                    send(.commonContextMenu(.copyLink(favorite.topic.id), favorite.isForum))
                }
                
                ContextButton(text: LocalizedStringResource("Delete", bundle: .module), symbol: .trash) {
                    send(.commonContextMenu(.delete(favorite.topic.id), favorite.isForum))
                }
            }
        }
    }
    
    // MARK: - Topic Context Menu
    
    private func TopicContextMenu(favorite: FavoriteInfo, isPinned: Bool) -> some View {
        VStack(spacing: 0) {
            Section {
                ContextButton(
                    text: isPinned
                    ? LocalizedStringResource("Unpin", bundle: .module)
                    : LocalizedStringResource("Pin", bundle: .module),
                    symbol: isPinned ? .pinSlash : .pin
                ) {
                    send(.topicContextMenu(.setPinned(!isPinned), favorite))
                }
                
                switch store.appSettings.topicOpeningStrategy {
                case .first:
                    ContextButton(
                        text: LocalizedStringResource("Go To End", bundle: .module),
                        symbol: .chevronRight2
                    ) {
                        send(.topicContextMenu(.goToEnd, favorite))
                    }
                case .last, .unread:
                    ContextButton(
                        text: LocalizedStringResource("Go To First", bundle: .module),
                        symbol: .chevronRight2
                    ) {
                        send(.topicContextMenu(.goToFirst, favorite))
                    }
                }
                
                ContextButton(
                    text: LocalizedStringResource("Notify Hat Update", bundle: .module),
                    symbol: favorite.isNotifyHatUpdate ? .flagFill : .flag
                ) {
                    send(.topicContextMenu(.notifyHatUpdate(favorite.flag), favorite))
                }
                
                Menu {
                    ContextButton(
                        text: LocalizedStringResource("Always", bundle: .module),
                        symbol: favorite.notify == .always ? .bellFill : .bell
                    ) {
                        send(.topicContextMenu(.notify(favorite.flag, .always), favorite))
                    }
                    
                    ContextButton(
                        text: LocalizedStringResource("Once", bundle: .module),
                        symbol: favorite.notify == .once ? .bellBadgeFill : .bellBadge
                    ) {
                        send(.topicContextMenu(.notify(favorite.flag, .once), favorite))
                    }
                    
                    ContextButton(
                        text: LocalizedStringResource("Do Not", bundle: .module),
                        symbol: favorite.notify == .doNot ? .bellSlashFill : .bellSlash
                    ) {
                        send(.topicContextMenu(.notify(favorite.flag, .doNot), favorite))
                    }
                } label: {
                    HStack {
                        Text("Notify Type", bundle: .module)
                        NotifyTypeIcon(type: favorite.notify)
                    }
                }
            }
        }
    }
    
    // MARK: - Favorites Section
    
    @ViewBuilder
    private func FavoritesSection(favorites: [FavoriteInfo], kind: SectionKind) -> some View {
        let isPinned = kind == .pinned
        Section {
            if shouldShowInlineNavigation {
                Navigation(isShown: kind == .regular)
            }
            
            ForEach(Array(favorites.enumerated()), id: \.element) { index, favorite in
                FavoriteRow(
                    favorite: favorite,
                    isPinned: isPinned,
                    isFirst: index == 0,
                    isLast: index == favorites.count - 1
                )
            }
            .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
            
            if shouldShowInlineNavigation, !favorites.isEmpty {
                Navigation(isShown: kind == .regular)
            }
        } header: {
            if !favorites.isEmpty {
                Header(title: kind.headerTitle)
            }
        }
        .listRowBackground(backgroundColors.tertiary)
    }
    
    // MARK: - Favorite Row
    
    @ViewBuilder
    private func FavoriteRow(
        favorite: FavoriteInfo,
        isPinned: Bool,
        isFirst: Bool,
        isLast: Bool
    ) -> some View {
        let radius: CGFloat = isLiquidGlass ? 24 : 10
        let swipeTitle: LocalizedStringKey = isPinned ? "Unpin" : "Pin"
        Group {
            if favorite.isForum {
                ForumRow(
                    title: favorite.topic.name,
                    isUnread: favorite.topic.isUnread,
                    onAction: {
                        send(.favoriteTapped(favorite, showUnread: false))
                    }
                )
            } else {
                TopicRow(
                    title: .plain(favorite.topic.name),
                    date: favorite.topic.lastPost.date,
                    username: favorite.topic.lastPost.username,
                    isPinned: isPinned,
                    isClosed: favorite.topic.isClosed,
                    isUnread: favorite.topic.isUnread,
                    isHatUpdated: favorite.isHatUpdated,
                    hasHatUpdateTracking: favorite.isNotifyHatUpdate,
                    onAction: { unreadTapped in
                        send(.favoriteTapped(favorite, showUnread: unreadTapped))
                    }
                )
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if !favorite.isForum {
                Button {
                    send(.topicContextMenu(.setPinned(!isPinned), favorite))
                } label: {
                    Label {
                        Text(swipeTitle, bundle: .module)
                    } icon: {
                        Image(systemSymbol: isPinned ? .pinSlashFill : .pinFill)
                    }
                }
                .tint(isPinned ? .gray : tintColor)
            }
        }
        .contextMenu {
            if !favorite.isForum {
                TopicContextMenu(favorite: favorite, isPinned: isPinned)
            }
            
            Section {
                CommonContextMenu(favorite: favorite)
            }
        }
        .listRowBackground(
            backgroundColors.tertiary
                .clipShape(
                    .rect(
                        topLeadingRadius: isFirst ? radius : 0,
                        bottomLeadingRadius: isLast ? radius : 0,
                        bottomTrailingRadius: isLast ? radius : 0,
                        topTrailingRadius: isFirst ? radius : 0
                    )
                )
        )
    }
    
    // MARK: - Navigation
    
    @ViewBuilder
    private func Navigation(isShown: Bool) -> some View {
        if isShown, store.pageNavigation.shouldShow {
            PageNavigation(store: store.scope(\.pageNavigation, action: \.pageNavigation))
                .listRowBackground(Color.clear)
                .padding(.bottom, 4)
        }
    }
    
    // MARK: - Notify Type Icon
    
    @ViewBuilder
    private func NotifyTypeIcon(type: FavoriteInfo.Notify) -> some View {
        let icon: SFSymbol = switch type {
        case .always: .bellFill
        case .once: .bellBadgeFill
        case .doNot: .bellSlashFill
        }

        Image(systemSymbol: icon)
    }
    
    // MARK: - Header
    
    @ViewBuilder
    private func Header(title: LocalizedStringKey) -> some View {
        Text(title, bundle: .module)
            .font(.subheadline)
            .foregroundStyle(Color(.Labels.teritary))
            .textCase(nil)
            .offset(x: -16)
            .padding(.bottom, 4)
    }
    
    // MARK: - Empty View
    
    @ViewBuilder
    private func EmptyFavorites() -> some View {
        VStack(spacing: 0) {
            Image(systemSymbol: .bookmark)
                .font(.title)
                .foregroundStyle(tintColor)
                .frame(width: 48, height: 48)
                .padding(.bottom, 8)
            
            Text("No favorites", bundle: .module)
                .font(.title3)
                .bold()
                .foregroundColor(Color(.Labels.primary))
                .padding(.bottom, 6)
            
            Text("Save something from the forum here", bundle: .module)
                .font(.footnote)
                .multilineTextAlignment(.center)
                .foregroundStyle(Color(.Labels.teritary))
                .frame(maxWidth: UIScreen.main.bounds.width * 0.7)
                .padding(.horizontal, 55)
        }
    }
}

// MARK: - Previews

#Preview {
    @Shared(.userSession) var userSession
    $userSession.withLock { $0 = .mock }
    
    return NavigationStack {
        FavoritesScreen(
            store: Store(
                initialState: FavoritesFeature.State(
                    favorites: [.mock, .mockUnread]
                )
            ) {
                FavoritesFeature()
            }
        )
    }
    .environment(\.tintColor, Color(.Theme.primary))
    .tint(Color(.Theme.primary))
}
