//
//  QMSScreen.swift
//  ForPDA
//
//  Created by Ilia Lubianoi on 17.11.2024.
//

import SwiftUI
import UniformTypeIdentifiers
import UIKit
import ComposableArchitecture
import SharedUI
import SFSafeSymbols
import ExyteChat
import UploadBoxFeature
import BBPanelFeature

@ViewAction(for: QMSFeature.self)
public struct QMSScreen: View {
    
    // MARK: - Properties
    
    @Perception.Bindable public var store: StoreOf<QMSFeature>
    @Environment(\.tintColor) private var tintColor
    @Environment(\.backgroundColors) private var backgroundColors
    @FocusState private var focusedInput: Int?
    
    // MARK: - Init
    
    public init(store: StoreOf<QMSFeature>) {
        self.store = store
    }
    
    // MARK: - Body
    
    public var body: some View {
        WithPerceptionTracking {
            ZStack {
                backgroundColors.primary
                    .ignoresSafeArea()

                QMSFilePickerPresenter(
                    isPresented: Binding($store.upload.destination.fileImporter).wrappedValue,
                    onPick: { urls in
                        if urls.isEmpty {
                            store.send(.upload(.view(.fileImporterURLsRecievingFailure)))
                        } else {
                            store.send(.upload(.view(.fileImporterURLsRecieved(urls))))
                        }
                    },
                    onCancel: {
                        store.send(.upload(.destination(.dismiss)))
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

                imageExportPresenter
                chatContent
            }
            .navigationTitle(navigationTitleText)
            ._toolbarTitleDisplayMode(.inline)
            .toolbar {
                toolbarContent
            }
            .alert($store.scope(\.$alert, action: \.alert))
            .confirmationDialog(
                deleteConfirmationTitle,
                isPresented: $store.isDeleteMessageConfirmationPresented,
                titleVisibility: .visible
            ) {
                if store.pendingDeleteCanDeleteForAll {
                    Button(
                        String(localized: "qms.delete.message.forAll", bundle: .module),
                        role: .destructive
                    ) {
                        send(.deleteMessageConfirmed(forAll: true))
                    }
                }
                Button(
                    String(localized: "qms.delete.message.forMe", bundle: .module),
                    role: .destructive
                ) {
                    send(.deleteMessageConfirmed(forAll: false))
                }
                Button(String(localized: "Cancel", bundle: .module), role: .cancel) {}
            }
            .onAppear {
                send(.onAppear)
            }
        }
    }

    private var navigationTitleText: String {
        guard store.isSelectingMessages else {
            return store.title
        }
        let count = store.selectedMessageIds.count
        guard count > 0 else {
            return String(localized: "qms.selection.title.empty", bundle: .module)
        }
        return String(localized: "qms.selection.title.count \(count)", bundle: .module)
    }

    private var deleteConfirmationTitle: Text {
        let count = store.pendingDeleteMessageIds.count
        if count > 1 {
            return Text(String(localized: "qms.delete.messages.title \(count)", bundle: .module))
        }
        return Text("qms.delete.message.title", bundle: .module)
    }

    private var shouldShowSelectionToolbarItem: Bool {
        store.isSelectingMessages || (store.chat != nil && !store.selectableMessageIds.isEmpty)
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if shouldShowSelectionToolbarItem {
            ToolbarItem(placement: .topBarTrailing) {
                WithPerceptionTracking {
                    if store.isSelectingMessages {
                        Button {
                            send(.cancelSelectionButtonTapped)
                        } label: {
                            Text("Cancel", bundle: .module)
                        }
                        .disabled(store.isDeletingMessage)
                    } else {
                        Button {
                            dismissKeyboard()
                            send(.selectMessagesButtonTapped)
                        } label: {
                            Image(systemSymbol: .checkmarkCircle)
                        }
                        .disabled(store.isDeletingMessage || store.isSending)
                        .accessibilityLabel(Text("qms.message.select", bundle: .module))
                    }
                }
            }
        }
    }
    
    private var imageExportPresenter: some View {
        QMSImageExportPresenter(
            isPresented: store.isImageExportPresented,
            urls: store.imageExportFileURLs,
            onFinish: { didExport in
                store.send(.view(.imageFileExportFinished(didExport)))
            }
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .allowsHitTesting(false)
    }

    private var chatContent: AnyView {
        if store.chat != nil {
            return makeChatView()
        } else {
            return AnyView(PDALoader().frame(width: 24, height: 24))
        }
    }

    private func makeChatView() -> AnyView {
        let theme = qmsChatTheme
        let openURL = OpenURLAction(handler: handleOpenURL)
        return AnyView(
            ChatView(
                messages: store.messages,
                messageBuilder: { message, positionInGroup, positionInSection, _, showMenu, _, showAttachment in
                    makeMessageRow(
                        message: message,
                        positionInGroup: positionInGroup,
                        positionInMessagesSection: positionInSection,
                        chatTheme: theme,
                        openURL: openURL,
                        showContextMenu: showMenu,
                        showAttachment: showAttachment
                    )
                },
                inputViewBuilder: { _, _, _, inputViewStyle, _, _ in
                    makeInputView(style: inputViewStyle)
                },
                messageMenuAction: { (action: ChatAction, _, message) in
                    handleMessageMenuAction(action, message: message)
                },
                localization: qmsChatLocalization,
                didSendMessage: { _ in
                    // send(.sendMessageButtonTapped(message))
                }
            )
            .showMessageMenuOnLongPress(false)
            .keyboardDismissMode(.interactive)
            .enableLoadMore { _ in
                await send(.loadMoreTriggered)
            }
            .linkPreviewsDisabled()
            .setAvailableInputs([.text])
            .chatTheme(theme)
            .tint(tintColor)
            .environment(\.openURL, openURL)
            .id(QMSChatThemeID(tintColor: tintColor, mainBackground: backgroundColors.primary))
        )
    }

    private func makeMessageRow(
        message: ExyteChat.Message,
        positionInGroup: PositionInUserGroup,
        positionInMessagesSection: PositionInMessagesSection,
        chatTheme: ChatTheme,
        openURL: OpenURLAction,
        showContextMenu: @escaping () -> Void,
        showAttachment: @escaping (ExyteChat.Attachment) -> Void
    ) -> some View {
        let messageId = Int(message.id)
        return WithPerceptionTracking {
            let isSelecting = store.isSelectingMessages && messageId != nil
            let isSelected = messageId.map { store.selectedMessageIds.contains($0) } ?? false
            QMSMessageRowView(
                message: message,
                positionInGroup: positionInGroup,
                positionInMessagesSection: positionInMessagesSection,
                tintColor: tintColor,
                isSelecting: isSelecting,
                isSelected: isSelected,
                isInteractionDisabled: store.isDeletingMessage,
                onToggleSelection: {
                    guard let messageId else { return }
                    send(.toggleMessageSelection(messageId))
                },
                onShowContextMenu: showContextMenu,
                onTapAttachment: showAttachment
            )
            .chatTheme(chatTheme)
            .tint(tintColor)
            .environment(\.openURL, openURL)
            .animation(.easeInOut(duration: 0.18), value: isSelecting)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
    }

    private var qmsChatLocalization: ChatLocalization {
        ChatLocalization(
            inputPlaceholder: String(localized: "qms.textfield.placeholder", bundle: .module),
            signatureText: "",
            cancelButtonText: String(localized: "Cancel", bundle: .module),
            recentToggleText: "",
            waitingForNetwork: "",
            recordingText: "",
            replyToText: ""
        )
    }

    private var qmsChatTheme: ChatTheme {
        ChatTheme(
            colors: ChatTheme.Colors(
                mainBG: backgroundColors.primary,
                mainTint: tintColor,
                messageMyBG: Color(.Background.quaternary),
                messageReadStatus: tintColor,
                messageMyText: Color(.Labels.primary),
                messageMyTimeText: Color(.systemGray),
                messageFriendBG: Color(.Background.quaternary),
                messageFriendText: Color(.Labels.primary),
                messageFriendTimeText: Color(.systemGray),
                statusGray: tintColor,
                sendButtonBackground: tintColor
            )
        )
    }

    private func handleMessageMenuAction(_ action: ChatAction, message: ExyteChat.Message) {
        switch action {
        case .copy:
            UIPasteboard.general.string = message.text
        case .select:
            guard let messageId = Int(message.id) else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            dismissKeyboard()
            send(.selectMessageFromMenu(messageId: messageId))
        case .delete:
            guard let messageId = Int(message.id) else { return }
            send(.deleteMessageTapped(
                messageId: messageId,
                isOwnMessage: message.user.isCurrentUser
            ))
        case .saveToPhotos:
            send(.saveImagesToPhotos(imageURLs(in: message)))
        case .saveToFiles:
            send(.saveImagesToFiles(imageURLs(in: message)))
        }
    }

    private func dismissKeyboard() {
        focusedInput = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }

    private func imageURLs(in message: ExyteChat.Message) -> [URL] {
        message.attachments
            .filter { $0.type == .image }
            .map(\.full)
    }

    private func handleOpenURL(_ url: URL) -> OpenURLAction.Result {
        send(.urlTapped(url))
        return .handled
    }

    private func makeInputView(style: InputViewStyle) -> AnyView {
        switch style {
        case .message:
            return AnyView(
                WithPerceptionTracking {
                    if store.isSelectingMessages {
                        SelectionBarView()
                    } else {
                        InputView()
                    }
                }
            )
        case .signature:
            return AnyView(EmptyView())
        }
    }

    private var canDeleteSelectedMessages: Bool {
        !store.selectedMessageIds.isEmpty && !store.isDeletingMessage
    }

    private var selectionDeleteButtonTitle: String {
        let count = store.selectedMessageIds.count
        guard count > 0 else {
            return String(localized: "qms.message.delete", bundle: .module)
        }
        return String(localized: "qms.selection.delete.count \(count)", bundle: .module)
    }

    private func SelectionBarView() -> some View {
        VStack(spacing: 0) {
            Divider()

            HStack(spacing: 12) {
                Button {
                    send(.toggleSelectAllMessagesButtonTapped)
                } label: {
                    Text(
                        store.areAllMessagesSelected
                            ? LocalizedStringKey("qms.selection.deselectAll")
                            : LocalizedStringKey("qms.selection.selectAll"),
                        bundle: .module
                    )
                    .font(.body)
                    .foregroundStyle(
                        store.isDeletingMessage ? Color(.Labels.teritary) : tintColor
                    )
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(store.isDeletingMessage || store.selectableMessageIds.isEmpty)

                Spacer(minLength: 8)

                Button(role: .destructive) {
                    send(.deleteSelectedMessagesButtonTapped)
                } label: {
                    HStack(spacing: 6) {
                        if store.isDeletingMessage {
                            ProgressView()
                                .progressViewStyle(.circular)
                        } else {
                            Image(systemSymbol: .trash)
                        }
                        Text(selectionDeleteButtonTitle)
                            .fontWeight(.semibold)
                    }
                    .font(.body)
                    .foregroundStyle(
                        canDeleteSelectedMessages ? Color(.Main.red) : Color(.Labels.teritary)
                    )
                    .frame(minHeight: 44)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!canDeleteSelectedMessages)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(backgroundColors.primary)
        }
        .animation(.default, value: store.isDeletingMessage)
    }

    private func InputView() -> some View {
        VStack(spacing: 8) {
            UploadBoxView(
                store: store.scope(\.upload, action: \.upload),
                usesExternalFileImporter: true
            )
            .disabled(store.isSending)
            
            HStack(alignment: .bottom, spacing: 8) {
                #if DEBUG
                if ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1" {
                    Button(String("+")) { store.draftText += "text" }
                        .buttonStyle(.borderedProminent)
                }
                #endif

                Button {
                    send(.attachmentButtonTapped)
                } label: {
                    Image(systemSymbol: .paperclip)
                        .font(.title3.weight(.medium))
                        .foregroundStyle(tintColor)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("qms.attachments.add", bundle: .module))
                .disabled(store.isSending || store.upload.isAnyFileUploading)

                Field(
                    content: $store.draftText,
                    placeholder: LocalizedStringResource("qms.textfield.placeholder", bundle: .module),
                    focusEqual: store.chatId,
                    focus: $focusedInput,
                    minHeight: 96,
                    selection: $store.draftTextRange,
                    bbPanel: {
                        BBPanelView(store: store.scope(\.bbPanel, action: \.bbPanel))
                            .onTapGesture {
                                focusedInput = store.chatId
                            }
                    }
                )
                .fixedSize(horizontal: false, vertical: true)
                .frame(minWidth: 0)

                Button {
                    send(.sendMessageButtonTapped(
                        DraftMessage(text: store.draftText, medias: [], giphyMedia: nil, recording: nil, replyMessage: nil, createdAt: .now)
                    ))
                } label: {
                    Circle()
                        .fill(tintColor)
                        .frame(width: 44, height: 44)
                        .overlay {
                            if store.isSending {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.white)
                            } else {
                                Image(systemSymbol: .arrowUp)
                                    .bold()
                                    .foregroundStyle(.white)
                            }
                        }
                        .opacity(store.canSendMessage ? 1 : 0.55)
                }
                .disabled(!store.canSendMessage)
                .accessibilityLabel(Text("qms.message.send", bundle: .module))
            }
        }
        .padding()
        .animation(.default, value: store.isSending)
        .animation(.default, value: store.canSendMessage)
        .animation(.default, value: store.draftText)
        .bind($store.focus, to: $focusedInput)
    }
}

private struct QMSChatThemeID: Hashable {
    let tintColor: Color
    let mainBackground: Color
}

private struct QMSFilePickerPresenter: UIViewControllerRepresentable {
    let isPresented: Bool
    let onPick: ([URL]) -> Void
    let onCancel: () -> Void

    func makeUIViewController(context: Context) -> QMSFilePickerPresenterController {
        let controller = QMSFilePickerPresenterController()
        controller.configure(isPresented: isPresented, onPick: onPick, onCancel: onCancel)
        return controller
    }

    func updateUIViewController(
        _ uiViewController: QMSFilePickerPresenterController,
        context: Context
    ) {
        uiViewController.configure(isPresented: isPresented, onPick: onPick, onCancel: onCancel)
    }
}

private final class QMSFilePickerPresenterController: UIViewController,
    UIDocumentPickerDelegate,
    UIAdaptivePresentationControllerDelegate
{
    private var shouldPresentPicker = false
    private var didPresentPickerForCurrentRequest = false
    private var documentPicker: UIDocumentPickerViewController?
    private var onPick: ([URL]) -> Void = { _ in }
    private var onCancel: () -> Void = {}

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentPickerIfNeeded()
    }

    func configure(
        isPresented: Bool,
        onPick: @escaping ([URL]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onPick = onPick
        self.onCancel = onCancel

        if isPresented {
            shouldPresentPicker = true
            presentPickerIfNeeded()
        } else {
            shouldPresentPicker = false
            didPresentPickerForCurrentRequest = false
            dismissPickerIfNeeded()
        }
    }

    private func presentPickerIfNeeded() {
        guard shouldPresentPicker,
              !didPresentPickerForCurrentRequest,
              viewIfLoaded?.window != nil,
              documentPicker == nil,
              presentedViewController == nil
        else { return }

        didPresentPickerForCurrentRequest = true
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.item],
            // QMS uploads file bytes; import a sandbox copy instead of opening the provider file in place.
            asCopy: true
        )
        picker.allowsMultipleSelection = true
        picker.modalPresentationStyle = .fullScreen
        picker.delegate = self
        documentPicker = picker
        present(picker, animated: true) { [weak self, weak picker] in
            picker?.presentationController?.delegate = self
        }
    }

    private func dismissPickerIfNeeded() {
        guard let picker = documentPicker else { return }
        documentPicker = nil
        guard picker.presentingViewController != nil, !picker.isBeingDismissed else { return }
        picker.dismiss(animated: true)
    }

    private func finishPicker(
        _ picker: UIDocumentPickerViewController,
        completion: @escaping () -> Void
    ) {
        guard documentPicker === picker else { return }
        documentPicker = nil

        if picker.presentingViewController != nil, !picker.isBeingDismissed {
            picker.dismiss(animated: true, completion: completion)
        } else {
            completion()
        }
    }

    func documentPicker(
        _ controller: UIDocumentPickerViewController,
        didPickDocumentsAt urls: [URL]
    ) {
        finishPicker(controller) { [weak self] in
            self?.onPick(urls)
        }
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finishPicker(controller) { [weak self] in
            self?.onCancel()
        }
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let picker = documentPicker else { return }
        finishPicker(picker) { [weak self] in
            self?.onCancel()
        }
    }
}

private struct QMSImageExportPresenter: UIViewControllerRepresentable {
    let isPresented: Bool
    let urls: [URL]
    let onFinish: (Bool) -> Void

    func makeUIViewController(context: Context) -> QMSImageExportPresenterController {
        let controller = QMSImageExportPresenterController()
        controller.configure(isPresented: isPresented, urls: urls, onFinish: onFinish)
        return controller
    }

    func updateUIViewController(
        _ uiViewController: QMSImageExportPresenterController,
        context: Context
    ) {
        uiViewController.configure(isPresented: isPresented, urls: urls, onFinish: onFinish)
    }
}

private final class QMSImageExportPresenterController: UIViewController,
    UIDocumentPickerDelegate,
    UIAdaptivePresentationControllerDelegate
{
    private var shouldPresentPicker = false
    private var didPresentPicker = false
    private var documentPicker: UIDocumentPickerViewController?
    private var fileURLs: [URL] = []
    private var onFinish: (Bool) -> Void = { _ in }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        presentPickerIfNeeded()
    }

    func configure(isPresented: Bool, urls: [URL], onFinish: @escaping (Bool) -> Void) {
        self.fileURLs = urls
        self.onFinish = onFinish
        if isPresented {
            shouldPresentPicker = true
            presentPickerIfNeeded()
        } else {
            shouldPresentPicker = false
            didPresentPicker = false
            dismissPickerIfNeeded()
        }
    }

    private func presentPickerIfNeeded() {
        guard shouldPresentPicker,
              !didPresentPicker,
              !fileURLs.isEmpty,
              viewIfLoaded?.window != nil,
              documentPicker == nil,
              presentedViewController == nil
        else { return }

        didPresentPicker = true
        let picker = UIDocumentPickerViewController(forExporting: fileURLs, asCopy: true)
        picker.modalPresentationStyle = .fullScreen
        picker.delegate = self
        documentPicker = picker
        present(picker, animated: true) { [weak self, weak picker] in
            picker?.presentationController?.delegate = self
        }
    }

    private func dismissPickerIfNeeded() {
        guard let picker = documentPicker else { return }
        documentPicker = nil
        guard picker.presentingViewController != nil, !picker.isBeingDismissed else { return }
        picker.dismiss(animated: true)
    }

    private func finishPicker(_ picker: UIDocumentPickerViewController, didExport: Bool) {
        guard documentPicker === picker else { return }
        documentPicker = nil
        shouldPresentPicker = false
        let completion: () -> Void = { [weak self] in
            guard let self else { return }
            self.onFinish(didExport)
        }
        if picker.presentingViewController != nil, !picker.isBeingDismissed {
            picker.dismiss(animated: true, completion: completion)
        } else {
            completion()
        }
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        finishPicker(controller, didExport: true)
    }

    func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
        finishPicker(controller, didExport: false)
    }

    func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
        guard let picker = documentPicker else { return }
        finishPicker(picker, didExport: false)
    }
}

// MARK: - Previews

#Preview {
    @Shared(.userSession) var userSession
    $userSession.withLock { $0 = .init(userId: 1, token: "", isHidden: false) }
    
    return NavigationStack {
        QMSScreen(
            store: Store(
                initialState: QMSFeature.State(chatId: 0)
            ) {
                QMSFeature()
            } withDependencies: { _ in
                
            }
        )
    }
    .environment(\.tintColor, Color(.Theme.primary))
    .environment(\.locale, Locale(identifier: "en"))
}

#Preview("Error On Send") {
    @Shared(.userSession) var userSession
    $userSession.withLock { $0 = .init(userId: 1, token: "", isHidden: false) }
    
    return QMSScreen(
        store: Store(initialState: QMSFeature.State(chatId: 0)) {
            QMSFeature()
        } withDependencies: {
            $0.qmsClient = .errorOnSend
        }
    )
    .environment(\.tintColor, Color(.Theme.primary))
    .environment(\.locale, Locale(identifier: "en"))
}
