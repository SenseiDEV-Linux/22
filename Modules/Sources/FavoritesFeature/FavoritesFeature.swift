//
//  FavoritesFeature.swift
//  ForPDA
//
//  Created by Xialtal on 8.11.24.
//

import Foundation
import ComposableArchitecture
import PageNavigationFeature
import APIClient
import Models
import PersistenceKeys
import TCAExtensions
import PasteboardClient
import AnalyticsClient
import ToastClient
import NotificationsClient

@Reducer
public struct FavoritesFeature: Reducer, Sendable {
    
    public init() {}
    
    // MARK: - Cancel ID
    
    private enum CancelID: Hashable {
        case loadFavorites
    }
    
    // MARK: - Localizations
    
    public enum Localization {
        static let linkCopied = LocalizedStringResource("Link copied", bundle: .module)
        static let markAsReadSuccess = LocalizedStringResource("Marked as read", bundle: .module)
        static let notifyTypeChanged = LocalizedStringResource("Notify type changed", bundle: .module)
        static let sortFiltersChanged = LocalizedStringResource("Sort filters are changed", bundle: .module)
        static let topicPinned = LocalizedStringResource("Topic pinned", bundle: .module)
        static let topicUnpinned = LocalizedStringResource("Topic unpinned", bundle: .module)
    }
    
    // MARK: - Pinned Mutation
    
    public enum PinnedMutation: Sendable {
        case delete(topicId: Int)
        case setImportant(topicId: Int, isImportant: Bool)
        case markRead(topicId: Int)
        case markAllRead
        case setNotify(topicId: Int, type: FavoriteNotifyType)
    }
    
    // MARK: - State
    
    @ObservableState
    public struct State: Equatable {
        @Shared(.appSettings) var appSettings: AppSettings
        @Shared(.pinnedFavorites) var pinnedFavorites: PinnedFavorites
        @Shared(.userSession) var userSession: UserSession?
        @Presents var sort: SortFeature.State?
        
        public var favoritesPinned: [FavoriteInfo] = []
        public var favoritesImportant: [FavoriteInfo] = []
        public var favorites: [FavoriteInfo] = []
        var lastLoadedFavorites: [FavoriteInfo] = []
        
        public var isLoading = true
        public var isRefreshing = false
        public var shouldShowEmptyState: Bool {
            return !isLoading && favoritesPinned.isEmpty && favoritesImportant.isEmpty && favorites.isEmpty
        }
        
        public var pageNavigation = PageNavigationFeature.State(type: .forum)
        
        public var isUserAuthorized: Bool {
            return userSession != nil
        }
        
        public init(
            favorites: [FavoriteInfo] = [],
            favoritesImportant: [FavoriteInfo] = [],
            favoritesPinned: [FavoriteInfo] = [],
            sort: SortFeature.State? = nil
        ) {
            self.favorites = favorites
            self.favoritesImportant = favoritesImportant
            self.favoritesPinned = favoritesPinned
            self.lastLoadedFavorites = favoritesImportant + favorites
            self.sort = sort
        }
    }
    
    // MARK: - Action
    
    public enum Action: ViewAction {
        case pageNavigation(PageNavigationFeature.Action)
        case sort(PresentationAction<SortFeature.Action>)
        
        case view(View)
        public enum View {
            case onFirstAppear
            case onNextAppear
            case onRefresh
            case onSceneBecomeActive
            case favoriteTapped(FavoriteInfo, showUnread: Bool)
            case contextOptionMenu(FavoritesOptionContextMenuAction)
            case commonContextMenu(FavoriteContextMenuAction, Bool)
            case topicContextMenu(FavoriteTopicContextMenuAction, FavoriteInfo)
        }
        
        case `internal`(Internal)
        public enum Internal {
            case refresh
            case favoritesResponse(Result<Favorite, any Error>, offset: Int, perPage: Int, isFromRemote: Bool)
            case prunePinnedIfComplete(Favorite, offset: Int, perPage: Int)
            case applyPinnedMutation(PinnedMutation)
            case loadFavorites(offset: Int)
        }
        
        case delegate(Delegate)
        public enum Delegate {
            case openForum(id: Int, name: String)
            case openTopic(id: Int, name: String, goTo: GoTo)
        }
    }
    
    // MARK: - Dependencies
    
    @Dependency(\.apiClient) private var apiClient
    @Dependency(\.toastClient) private var toastClient
    @Dependency(\.analyticsClient) private var analyticsClient
    @Dependency(\.pasteboardClient) private var pasteboardClient
    @Dependency(\.notificationCenter) private var notificationCenter
    @Dependency(\.notificationsClient) private var notificationsClient
    @Dependency(\.continuousClock) private var clock
    
    // MARK: - Body
    
    public var body: some Reducer<State, Action> {
        Scope(\.pageNavigation, action: \.pageNavigation) {
            PageNavigationFeature()
        }
        
        Reduce<State, Action> { state, action in
            switch action {
            case let .pageNavigation(.offsetChanged(to: newOffset)):
                return .send(.internal(.loadFavorites(offset: newOffset)))
                
            case .sort(.presented(.saveButtonTapped)):
                return .run { send in
                    await toastClient.showToast(ToastMessage(text: Localization.sortFiltersChanged, haptic: .success))
                    await send(.internal(.refresh))
                    await send(.sort(.presented(.cancelButtonTapped)))
                }
                
            case .sort(.presented(.cancelButtonTapped)):
                state.sort = nil
                return .none
                
            case .pageNavigation, .sort:
                return .none
                
            case .view(.onFirstAppear):
                return .merge([
                    updatePageNavigation(&state, offset: 0),
                    .send(.internal(.loadFavorites(offset: 0))),
                    .run { send in
                        for await _ in notificationCenter.notifications(named: .favoritesUpdated) {
                            await send(.internal(.refresh))
                        }
                    },
                    .run { send in
                        for await _ in notificationCenter.notifications(named: .sceneBecomeActive) {
                            await send(.view(.onSceneBecomeActive))
                        }
                    },
                    .run { send in
                        for await notification in notificationsClient.eventPublisher().values {
                            guard notification.isTopic else { continue }
                            await send(.internal(.refresh))
                        }
                    }
                ])
                
            case .view(.onNextAppear):
                return .send(.internal(.refresh))
                
            case .view(.onRefresh):
                guard !state.isLoading else { return .none }
                return .send(.internal(.refresh))
                
            case .view(.onSceneBecomeActive):
                if !state.isLoading {
                    return .send(.internal(.refresh))
                }
                return .none
                
            case let .view(.favoriteTapped(favorite, showUnread)):
                guard !showUnread else {
                    return .send(.delegate(.openTopic(id: favorite.topic.id, name: favorite.topic.name, goTo: .unread)))
                }
                
                if favorite.isForum {
                    return .send(.delegate(.openForum(id: favorite.topic.id, name: favorite.topic.name)))
                } else {
                    let goTo = state.appSettings.topicOpeningStrategy.asGoTo
                    return .send(.delegate(.openTopic(id: favorite.topic.id, name: favorite.topic.name, goTo: goTo)))
                }
                
            case let .view(.contextOptionMenu(action)):
                return handleOptionContextMenu(action, state: &state)
                
            case let .view(.commonContextMenu(action, isForum)):
                return handleCommonContextMenu(action, isForum: isForum)
                
            case let .view(.topicContextMenu(action, favorite)):
                return handleTopicContextMenu(action, favorite: favorite, state: &state)
                
            case .internal(.refresh):
                if !state.isLoading {
                    rebuildSections(&state)
                }
                state.isRefreshing = true
                return .run { [offset = state.pageNavigation.offset] send in
                    await send(.internal(.loadFavorites(offset: offset)))
                }
                
            case let .internal(.loadFavorites(offset)):
                return loadFavorites(offset: offset, state: &state)
                
            case let .internal(.favoritesResponse(.success(response), offset, perPage, isFromRemote)):
                if response.favorites.isEmpty && offset > 0 {
                    return .send(.pageNavigation(.firstPageTapped))
                }
                
                if let userId = state.userSession?.userId {
                    let shouldPrune = isFromRemote && isCompleteFirstPage(response, offset: offset, perPage: perPage)
                    state.$pinnedFavorites.withLock {
                        $0.sync(with: response.favorites, pruneMissing: shouldPrune, userId: userId)
                    }
                }
                
                state.lastLoadedFavorites = response.favorites
                rebuildSections(&state)
                
                state.isLoading = false
                state.isRefreshing = false
                
                analyticsClient.reportFullyDisplayed()
                
                return updatePageNavigation(&state, count: response.favoritesCount)
                
            case let .internal(.prunePinnedIfComplete(response, offset, perPage)):
                guard let userId = state.userSession?.userId,
                      isCompleteFirstPage(response, offset: offset, perPage: perPage)
                else { return .none }
                
                state.$pinnedFavorites.withLock {
                    $0.sync(with: response.favorites, pruneMissing: true, userId: userId)
                }
                rebuildSections(&state)
                return .none
                
            case let .internal(.applyPinnedMutation(mutation)):
                applyPinnedMutation(mutation, state: &state)
                return .none
                
            case let .internal(.favoritesResponse(.failure(error), _, _, _)):
                print("FAVORITES RESPONSE FAILURE: \(error)")
                state.isRefreshing = false
                if state.isLoading {
                    rebuildSections(&state)
                    if !state.favoritesPinned.isEmpty {
                        state.isLoading = false
                    }
                }
                analyticsClient.reportFullyDisplayed()
                return .run { _ in
                    await toastClient.showToast(.whoopsSomethingWentWrong)
                }
                
            case .delegate:
                return .none
            }
        }
        .ifLet(\.$sort, action: \.sort) {
            SortFeature()
        }
        
        Analytics()
    }
    
    // MARK: - Context Menu Handlers
    
    private func handleOptionContextMenu(
        _ action: FavoritesOptionContextMenuAction,
        state: inout State
    ) -> Effect<Action> {
        switch action {
        case .sort:
            state.sort = SortFeature.State()
            return .none
            
        case .markAllAsRead:
            return .run { send in
                let status = try await apiClient.readAllFavorites()
                if status {
                    await send(.internal(.applyPinnedMutation(.markAllRead)))
                }
                let success = ToastMessage(text: Localization.markAsReadSuccess, haptic: .success)
                await toastClient.showToast(status ? success : .whoopsSomethingWentWrong)
                await send(.internal(.refresh))
                
                let unread = try await apiClient.getUnread(type: .all)
                await notificationsClient.showUnreadNotifications(unread)
            }
        }
    }
    
    private func handleCommonContextMenu(
        _ action: FavoriteContextMenuAction,
        isForum: Bool
    ) -> Effect<Action> {
        switch action {
        case .copyLink(let id):
            let show = isForum ? "showforum" : "showtopic"
            pasteboardClient.copy("https://4pda.to/forum/index.php?\(show)=\(id)")
            return .run { _ in
                await toastClient.showToast(ToastMessage(text: Localization.linkCopied, haptic: .success))
            }
            
        case .delete(let id):
            return .run { send in
                let request = SetFavoriteRequest(id: id, action: .delete, type: isForum ? .forum : .topic)
                let status = try await apiClient.setFavorite(request)
                if status, !isForum {
                    await send(.internal(.applyPinnedMutation(.delete(topicId: id))))
                }
                await toastClient.showToast(status ? .actionCompleted : .whoopsSomethingWentWrong)
                await send(.internal(.refresh))
            }
            
        case .setImportant(let id, let pin):
            return .run { send in
                let request = SetFavoriteRequest(id: id, action: pin ? .pin : .unpin, type: isForum ? .forum : .topic)
                let status = try await apiClient.setFavorite(request)
                if status, !isForum {
                    await send(.internal(.applyPinnedMutation(.setImportant(topicId: id, isImportant: pin))))
                }
                await toastClient.showToast(status ? .actionCompleted : .whoopsSomethingWentWrong)
                await send(.internal(.refresh))
            }
            
        case .markRead(let id):
            return .run { [id, isForum] send in
                let status = try await apiClient.markRead(id: id, isTopic: !isForum)
                if status, !isForum {
                    await send(.internal(.applyPinnedMutation(.markRead(topicId: id))))
                }
                await toastClient.showToast(status ? .actionCompleted : .whoopsSomethingWentWrong)
                await send(.internal(.refresh))
            }
        }
    }
    
    private func handleTopicContextMenu(
        _ action: FavoriteTopicContextMenuAction,
        favorite: FavoriteInfo,
        state: inout State
    ) -> Effect<Action> {
        switch action {
        case .setPinned(let isPinned):
            guard !favorite.isForum, let userId = state.userSession?.userId else { return .none }
            state.$pinnedFavorites.withLock { pinned in
                if isPinned {
                    pinned.pin(favorite, userId: userId)
                } else {
                    pinned.unpin(topicId: favorite.id, userId: userId)
                }
            }
            rebuildSections(&state)
            let toast = ToastMessage(
                text: isPinned ? Localization.topicPinned : Localization.topicUnpinned,
                haptic: .success
            )
            return .run { _ in
                await toastClient.showToast(toast)
            }
            
        case .goToFirst:
            return .send(.delegate(.openTopic(id: favorite.topic.id, name: favorite.topic.name, goTo: .first)))
            
        case .goToEnd:
            return .send(.delegate(.openTopic(id: favorite.topic.id, name: favorite.topic.name, goTo: .last)))
            
        case .notifyHatUpdate(let flag):
            return .run { send in
                await send(.view(.topicContextMenu(.notify(flag, .hatUpdate), favorite)))
            }
            
        case .notify(let flag, let notify):
            return .run { send in
                let request = NotifyFavoriteRequest(id: favorite.topic.id, flag: flag, type: notify)
                let status = try await apiClient.notifyFavorite(request)
                if status {
                    await send(.internal(.applyPinnedMutation(.setNotify(topicId: favorite.topic.id, type: notify))))
                }
                let notifyTypeChangedToast = ToastMessage(text: Localization.notifyTypeChanged, haptic: .success)
                await toastClient.showToast(status ? notifyTypeChangedToast : .whoopsSomethingWentWrong)
                await send(.internal(.refresh))
            }
        }
    }
    
    // MARK: - Loading & Sections
    
    private func loadFavorites(offset: Int, state: inout State) -> Effect<Action> {
        if !state.isRefreshing {
            state.isLoading = true
        }
        let perPage = state.appSettings.forumPerPage
        let favoritesSettings = state.appSettings.favorites
        let isRefreshing = state.isRefreshing
        let cachePolicy: CachePolicy = (isRefreshing || offset > 0) ? .skipCache : .cacheAndLoad
        return .run { send in
            let startTime = Date()
            var emissionCount = 0
            var lastResponse: Favorite?
            for try await favorites in try await apiClient.getFavorites(
                FavoritesRequest(
                    offset: offset,
                    perPage: perPage,
                    isSortByName: favoritesSettings.isSortByName,
                    isSortReverse: favoritesSettings.isReverseOrder,
                    isUnreadFirst: favoritesSettings.isUnreadFirst
                ),
                cachePolicy
            ) {
                emissionCount += 1
                lastResponse = favorites
                let isFromRemote = cachePolicy == .skipCache || emissionCount > 1
                if isRefreshing { await delayUntilTimePassed(1.0, since: startTime) }
                await send(
                    .internal(
                        .favoritesResponse(
                            .success(favorites),
                            offset: offset,
                            perPage: perPage,
                            isFromRemote: isFromRemote
                        )
                    )
                )
            }
            if cachePolicy == .cacheAndLoad,
               emissionCount == 1,
               let lastResponse,
               !Task.isCancelled {
                await send(.internal(.prunePinnedIfComplete(lastResponse, offset: offset, perPage: perPage)))
            }
        } catch: { error, send in
            await send(.internal(.favoritesResponse(.failure(error), offset: offset, perPage: perPage, isFromRemote: true)))
        }
        .cancellable(id: CancelID.loadFavorites, cancelInFlight: true)
    }
    
    private func applyPinnedMutation(_ mutation: PinnedMutation, state: inout State) {
        guard let userId = state.userSession?.userId else { return }
        switch mutation {
        case let .delete(topicId):
            state.$pinnedFavorites.withLock { $0.unpin(topicId: topicId, userId: userId) }
            state.lastLoadedFavorites.removeAll { !$0.isForum && $0.id == topicId }
            
        case let .setImportant(topicId, isImportant):
            state.$pinnedFavorites.withLock {
                $0.setImportant(topicId: topicId, isImportant: isImportant, userId: userId)
            }
            updateLoadedTopic(topicId: topicId, in: &state.lastLoadedFavorites) {
                $0.settingImportant(isImportant)
            }
            
        case let .markRead(topicId):
            state.$pinnedFavorites.withLock { $0.markRead(topicId: topicId, userId: userId) }
            updateLoadedTopic(topicId: topicId, in: &state.lastLoadedFavorites) {
                $0.markingRead()
            }
            
        case .markAllRead:
            state.$pinnedFavorites.withLock { $0.markAllRead(userId: userId) }
            for index in state.lastLoadedFavorites.indices where !state.lastLoadedFavorites[index].isForum {
                state.lastLoadedFavorites[index] = state.lastLoadedFavorites[index].markingRead()
            }
            
        case let .setNotify(topicId, type):
            state.$pinnedFavorites.withLock { $0.setNotify(topicId: topicId, type: type, userId: userId) }
            updateLoadedTopic(topicId: topicId, in: &state.lastLoadedFavorites) {
                $0.withNotify(type)
            }
        }
        rebuildSections(&state)
    }
    
    private func updateLoadedTopic(
        topicId: Int,
        in favorites: inout [FavoriteInfo],
        transform: (FavoriteInfo) -> FavoriteInfo
    ) {
        guard let index = favorites.firstIndex(where: { !$0.isForum && $0.id == topicId }) else { return }
        favorites[index] = transform(favorites[index])
    }
    
    private func rebuildSections(_ state: inout State) {
        let pinned: [FavoriteInfo]
        if let userId = state.userSession?.userId {
            pinned = state.pinnedFavorites.topics(for: userId)
        } else {
            pinned = []
        }
        let pinnedIds = Set(pinned.map(\.id))
        
        var important: [FavoriteInfo] = []
        var regular: [FavoriteInfo] = []
        
        for favorite in state.lastLoadedFavorites {
            if !favorite.isForum && pinnedIds.contains(favorite.id) {
                continue
            }
            if favorite.isImportant {
                important.append(favorite)
            } else {
                regular.append(favorite)
            }
        }
        
        state.favoritesPinned = pinned
        state.favoritesImportant = important
        state.favorites = regular
    }
    
    private func isCompleteFirstPage(_ response: Favorite, offset: Int, perPage: Int) -> Bool {
        guard offset == 0, perPage > 0 else { return false }
        return response.favoritesCount < perPage && response.favorites.count >= response.favoritesCount
    }
    
    private func updatePageNavigation(
        _ state: inout State,
        count: Int = 0,
        offset: Int? = nil
    ) -> Effect<Action> {
        return .send(.pageNavigation(.update(count: count, offset: offset)))
    }
}
