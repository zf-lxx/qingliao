# 轻聊客户端适配覆盖

`app/` 是当前发行用的 Flutter 客户端（BSD-3-Clause，版权声明见 `NOTICE` 与 `LICENSE`）。Dart 包名为 `qingliao`。Android **applicationId** 与 Kotlin **namespace** 均为 `xyz.qingliao.app`，可覆盖安装既有轻聊 0.x。

此前的 0.2 Flutter 树仍在 `client/`，仅作对照，不是本分支的构建入口。在 `app/` 下执行 `source ~/sdk/env.sh` 与 `flutter build apk --release --target-platform android-arm64`。没有 `android/key.properties` 时，发行签名回退到 `~/.android/debug.keystore`，与既有内测包一致。

arm64 发行包不包含 `libtdjson`、FVP/FFmpeg 或额外 CPU ABI，体积控制在约 50 MB 以内（当前制品：`/workspace/qingliao-0.4.1-arm64.apk`，版本 0.4.1+8）。

原生 `libtdjson` 不再随包提供。`TdBindings` 是纯 Dart 实现，把请求交给 `QlTdEngine`，由它对接轻聊后端（`REST` + `WS /v1/ws`，带 seq/ack 与增量同步）。尚未支持的方法返回 TDLib 风格的 `error`（`QL_UNSUPPORTED: <method>`），不会崩溃，也不会假装成功。一小份白名单（`qlEmptyResultMethods`）对后端确实没有的列表查询返回真实的空集合（登录设备/通行密钥、自定义表情包、直播动态专辑、社区等）。

## 设置

设置页保留搜索和原有分组。本地即可工作的页面包括：主题、外观/界面、聊天行为、解锁/密码、内容过滤（本机关键词）、数据与存储（本地缓存）、语言、关于，以及可选的桌面快捷键。

仍没有真实轻聊接口的服务端页面会留在列表里，带「暂未开放 / Not yet」标签并打开占位页：

- 代理。通话和厂商推送保持隐藏/暂未开放（需要 coturn/SFU 以及小米推送/FCM 凭证）。隐私与安全里的两步验证、登录设备、通行密钥、注销账号也尚未实现；可见性规则本身已接通。

已接通贴纸（内置「轻聊」PNG 包与用户包包，非外部素材；`.tgs` / `.webm` 因体积暂缓）、投票、清单、链接预览、联系人、聊天文件夹、通知范围、隐私规则、已读回执开关、动态（24 小时图片/视频，查看、回应、举报；没有直播）、更完整的富文本实体、本机会话备份与恢复，以及多账号槽位。应用内更新只读取 `zf-lxx/qingliao` 的发行，并能从历史标签或 `v0.4.1` 这类版本号解析出版本。输入栏回复引用的 X 在键盘保持打开时也可以取消回复。

「已屏蔽用户」此前已经接通，不会标成暂未开放。

## 覆盖摘要

客户端 UI 会调用 **457** 个互不相同的 TDLib 风格方法（对 `TdClient` / 界面查询点的静态盘点）。当前状态：

- 已实现：约 **120**（含贴纸、投票、清单、文件夹、联系人、隐私、通知范围、链接预览、动态及相关写入）
- 空结果（真实空集合）：约 **20**（登录设备、自定义表情包、动态专辑、社区等）
- 未支持（`QL_UNSUPPORTED`）：约 **317**

直播动态、通话、Bot API 和厂商推送仍未支持或已隐藏。

轻聊自有方法（`qlLogin`、`qlRegister`、`qlGetServer`）已实现，供登录页使用，并排在方法表最前。

## Method table

| Method | Endpoint / notes | Status |
| --- | --- | --- |
| `qlLogin` | POST /v1/auth/login | implemented |
| `qlRegister` | POST /v1/auth/register | implemented |
| `qlGetServer` | — (local) | implemented |
| `acceptCall` | QL_UNSUPPORTED | unsupported |
| `acceptOauthRequest` | QL_UNSUPPORTED | unsupported |
| `activateStoryStealthMode` | QL_UNSUPPORTED | unsupported |
| `addChatFolderByInviteLink` | QL_UNSUPPORTED | unsupported |
| `addChatMembers` | POST /v1/conversations/{id}/members | implemented |
| `addChatToList` | PATCH /v1/conversations/{id} (archived) | implemented |
| `addChecklistTasks` | QL_UNSUPPORTED | unsupported |
| `addContact` | QL_UNSUPPORTED | unsupported |
| `addFavoriteSticker` | QL_UNSUPPORTED | unsupported |
| `addFileToDownloads` | GET /v1/media/{id} | implemented |
| `addLoginPasskey` | QL_UNSUPPORTED | unsupported |
| `addMessageReaction` | PUT /v1/messages/{id}/reactions | implemented |
| `addOffer` | QL_UNSUPPORTED | unsupported |
| `addPollOption` | QL_UNSUPPORTED | unsupported |
| `addProxy` | QL_UNSUPPORTED | unsupported |
| `addQuickReplyShortcutMessage` | QL_UNSUPPORTED | unsupported |
| `addStickerToSet` | QL_UNSUPPORTED | unsupported |
| `addTextCompositionStyle` | QL_UNSUPPORTED | unsupported |
| `allowBotToSendMessages` | QL_UNSUPPORTED | unsupported |
| `answerGuestQuery` | QL_UNSUPPORTED | unsupported |
| `applyPremiumGiftCode` | QL_UNSUPPORTED | unsupported |
| `approveSuggestedPost` | QL_UNSUPPORTED | unsupported |
| `assignStoreTransaction` | QL_UNSUPPORTED | unsupported |
| `canBotSendMessages` | QL_UNSUPPORTED | unsupported |
| `canPostStory` | QL_UNSUPPORTED | unsupported |
| `canPurchaseFromStore` | QL_UNSUPPORTED | unsupported |
| `canSendMessageToUser` | QL_UNSUPPORTED | unsupported |
| `canTransferOwnership` | QL_UNSUPPORTED | unsupported |
| `cancelDownloadFile` | — (local) | implemented |
| `cancelRecoveryEmailAddressVerification` | QL_UNSUPPORTED | unsupported |
| `changeStickerSet` | QL_UNSUPPORTED | unsupported |
| `checkAuthenticationCode` | QL_UNSUPPORTED | unsupported |
| `checkAuthenticationEmailCode` | QL_UNSUPPORTED | unsupported |
| `checkAuthenticationPasskey` | QL_UNSUPPORTED | unsupported |
| `checkAuthenticationPassword` | QL_UNSUPPORTED | unsupported |
| `checkAuthenticationPremiumPurchase` | QL_UNSUPPORTED | unsupported |
| `checkChatFolderInviteLink` | QL_UNSUPPORTED | unsupported |
| `checkChatInviteLink` | QL_UNSUPPORTED | unsupported |
| `checkOauthRequestMatchCode` | QL_UNSUPPORTED | unsupported |
| `checkPhoneNumberCode` | QL_UNSUPPORTED | unsupported |
| `checkPremiumGiftCode` | QL_UNSUPPORTED | unsupported |
| `checkQuickReplyShortcutName` | QL_UNSUPPORTED | unsupported |
| `checkRecoveryEmailAddressCode` | QL_UNSUPPORTED | unsupported |
| `checkStickerSetName` | QL_UNSUPPORTED | unsupported |
| `checkWebAppFileDownload` | QL_UNSUPPORTED | unsupported |
| `closeChat` | — (local) | implemented |
| `closeStory` | QL_UNSUPPORTED | unsupported |
| `closeWebApp` | QL_UNSUPPORTED | unsupported |
| `composeRichMessageWithAi` | QL_UNSUPPORTED | unsupported |
| `composeTextWithAi` | QL_UNSUPPORTED | unsupported |
| `confirmBusinessConnectedBot` | QL_UNSUPPORTED | unsupported |
| `confirmQrCodeAuthentication` | QL_UNSUPPORTED | unsupported |
| `createBot` | QL_UNSUPPORTED | unsupported |
| `createBusinessChatLink` | QL_UNSUPPORTED | unsupported |
| `createCall` | QL_UNSUPPORTED | unsupported |
| `createChatFolder` | QL_UNSUPPORTED | unsupported |
| `createChatFolderInviteLink` | QL_UNSUPPORTED | unsupported |
| `createChatInviteLink` | QL_UNSUPPORTED | unsupported |
| `createForumTopic` | QL_UNSUPPORTED | unsupported |
| `createNewBasicGroupChat` | POST /v1/conversations (group) | implemented |
| `createNewSecretChat` | QL_UNSUPPORTED | unsupported |
| `createNewStickerSet` | QL_UNSUPPORTED | unsupported |
| `createNewSupergroupChat` | POST /v1/conversations (kind=channel or group) | implemented |
| `createPrivateChat` | POST /v1/conversations (direct, on first send) | implemented |
| `createRichMessageWithAi` | QL_UNSUPPORTED | unsupported |
| `createStoryAlbum` | QL_UNSUPPORTED | unsupported |
| `createTemporaryPassword` | QL_UNSUPPORTED | unsupported |
| `createTextCompositionStyle` | QL_UNSUPPORTED | unsupported |
| `createVideoChat` | QL_UNSUPPORTED | unsupported |
| `declineOauthRequest` | QL_UNSUPPORTED | unsupported |
| `declineSuggestedPost` | QL_UNSUPPORTED | unsupported |
| `deleteAccount` | QL_UNSUPPORTED | unsupported |
| `deleteBusinessChatLink` | QL_UNSUPPORTED | unsupported |
| `deleteBusinessConnectedBot` | QL_UNSUPPORTED | unsupported |
| `deleteChat` | QL_UNSUPPORTED | unsupported |
| `deleteChatBackground` | QL_UNSUPPORTED | unsupported |
| `deleteChatFolder` | QL_UNSUPPORTED | unsupported |
| `deleteChatFolderInviteLink` | QL_UNSUPPORTED | unsupported |
| `deleteChatHistory` | POST /v1/conversations/{id}/clear | implemented |
| `deleteChatMessagesBySender` | QL_UNSUPPORTED | unsupported |
| `deleteDefaultBackground` | QL_UNSUPPORTED | unsupported |
| `deleteDirectMessagesChatTopicHistory` | QL_UNSUPPORTED | unsupported |
| `deleteDirectMessagesChatTopicMessagesByDate` | QL_UNSUPPORTED | unsupported |
| `deleteFile` | — (local) | implemented |
| `deleteForumTopic` | QL_UNSUPPORTED | unsupported |
| `deleteGroupCallMessages` | QL_UNSUPPORTED | unsupported |
| `deleteGroupCallMessagesBySender` | QL_UNSUPPORTED | unsupported |
| `deleteMessages` | DELETE /v1/messages/{id} | implemented |
| `deleteProfilePhoto` | PATCH /v1/me | implemented |
| `deleteQuickReplyShortcut` | QL_UNSUPPORTED | unsupported |
| `deleteQuickReplyShortcutMessages` | QL_UNSUPPORTED | unsupported |
| `deleteStickerSet` | QL_UNSUPPORTED | unsupported |
| `deleteStory` | QL_UNSUPPORTED | unsupported |
| `deleteStoryAlbum` | QL_UNSUPPORTED | unsupported |
| `deleteTextCompositionStyle` | QL_UNSUPPORTED | unsupported |
| `disableProxy` | — (noop) | implemented |
| `discardCall` | QL_UNSUPPORTED | unsupported |
| `downloadFile` | GET /v1/media/{id} | implemented |
| `editBusinessChatLink` | QL_UNSUPPORTED | unsupported |
| `editChatFolder` | QL_UNSUPPORTED | unsupported |
| `editChatFolderInviteLink` | QL_UNSUPPORTED | unsupported |
| `editChatInviteLink` | QL_UNSUPPORTED | unsupported |
| `editForumTopic` | QL_UNSUPPORTED | unsupported |
| `editMessageCaption` | PATCH /v1/messages/{id} | implemented |
| `editMessageChecklist` | QL_UNSUPPORTED | unsupported |
| `editMessageMedia` | QL_UNSUPPORTED | unsupported |
| `editMessageSchedulingState` | QL_UNSUPPORTED | unsupported |
| `editMessageText` | PATCH /v1/messages/{id} | implemented |
| `editQuickReplyMessage` | QL_UNSUPPORTED | unsupported |
| `editStory` | QL_UNSUPPORTED | unsupported |
| `editTextCompositionStyle` | QL_UNSUPPORTED | unsupported |
| `enableProxy` | — (noop) | implemented |
| `fixTextWithAi` | QL_UNSUPPORTED | unsupported |
| `forwardMessages` | POST /v1/messages/{id}/forward | implemented |
| `getAccountTtl` | QL_UNSUPPORTED | unsupported |
| `getActiveSessions` | — (truthful empty result) | empty |
| `getAttachmentMenuBot` | — (truthful empty result) | empty |
| `getAuthenticationPasskeyParameters` | QL_UNSUPPORTED | unsupported |
| `getAuthorizationState` | — (local) | implemented |
| `getBasicGroup` | GET /v1/conversations/{id}/members (cached) | implemented |
| `getBasicGroupFullInfo` | GET /v1/conversations/{id}/members | implemented |
| `getBlockedMessageSenders` | GET /v1/me/blocks | implemented |
| `getBotSimilarBots` | QL_UNSUPPORTED | unsupported |
| `getBusinessChatLinkInfo` | QL_UNSUPPORTED | unsupported |
| `getBusinessChatLinks` | QL_UNSUPPORTED | unsupported |
| `getBusinessConnectedBot` | QL_UNSUPPORTED | unsupported |
| `getBusinessFeatures` | QL_UNSUPPORTED | unsupported |
| `getCallbackQueryAnswer` | QL_UNSUPPORTED | unsupported |
| `getChat` | GET /v1/conversations + members | implemented |
| `getChatActiveStories` | QL_UNSUPPORTED | unsupported |
| `getChatAvailableMessageSenders` | QL_UNSUPPORTED | unsupported |
| `getChatBoostFeatures` | QL_UNSUPPORTED | unsupported |
| `getChatBoostLink` | QL_UNSUPPORTED | unsupported |
| `getChatBoostLinkInfo` | QL_UNSUPPORTED | unsupported |
| `getChatBoostStatus` | QL_UNSUPPORTED | unsupported |
| `getChatBoosts` | QL_UNSUPPORTED | unsupported |
| `getChatEventLog` | QL_UNSUPPORTED | unsupported |
| `getChatFolder` | QL_UNSUPPORTED | unsupported |
| `getChatFolderChatsToLeave` | — (truthful empty result) | empty |
| `getChatFolderInviteLinks` | QL_UNSUPPORTED | unsupported |
| `getChatHistory` | GET /v1/conversations/{id}/messages | implemented |
| `getChatInviteLinkCounts` | QL_UNSUPPORTED | unsupported |
| `getChatInviteLinkMembers` | QL_UNSUPPORTED | unsupported |
| `getChatInviteLinks` | QL_UNSUPPORTED | unsupported |
| `getChatJoinRequests` | QL_UNSUPPORTED | unsupported |
| `getChatMember` | GET /v1/conversations/{id}/members | implemented |
| `getChatMessageByDate` | QL_UNSUPPORTED | unsupported |
| `getChatNotificationSettingsExceptions` | — (truthful empty result) | empty |
| `getChatScheduledMessages` | — (truthful empty result) | empty |
| `getChatSimilarChats` | — (truthful empty result) | empty |
| `getChatSponsoredMessages` | QL_UNSUPPORTED | unsupported |
| `getChatStatistics` | QL_UNSUPPORTED | unsupported |
| `getChatStoryAlbums` | QL_UNSUPPORTED | unsupported |
| `getChats` | GET /v1/conversations (cached) | implemented |
| `getChatsForChatFolderInviteLink` | QL_UNSUPPORTED | unsupported |
| `getChatsToPostStories` | — (truthful empty result) | empty |
| `getCommunityFullInfo` | QL_UNSUPPORTED | unsupported |
| `getContacts` | cached users / GET /v1/users/search | implemented |
| `getCountries` | QL_UNSUPPORTED | unsupported |
| `getCurrentState` | — (local snapshot) | implemented |
| `getCurrentWeather` | QL_UNSUPPORTED | unsupported |
| `getCustomEmojiStickers` | — (truthful empty result) | empty |
| `getDeepLinkInfo` | QL_UNSUPPORTED | unsupported |
| `getDefaultMessageAutoDeleteTime` | QL_UNSUPPORTED | unsupported |
| `getDefaultProfilePhotoCustomEmojiStickers` | QL_UNSUPPORTED | unsupported |
| `getDirectMessagesChatTopic` | QL_UNSUPPORTED | unsupported |
| `getDirectMessagesChatTopicHistory` | QL_UNSUPPORTED | unsupported |
| `getDirectMessagesChatTopicMessageByDate` | QL_UNSUPPORTED | unsupported |
| `getDirectMessagesChatTopicRevenue` | QL_UNSUPPORTED | unsupported |
| `getFile` | — (local index) | implemented |
| `getFileDownloadedPrefixSize` | QL_UNSUPPORTED | unsupported |
| `getForumTopic` | QL_UNSUPPORTED | unsupported |
| `getForumTopicHistory` | QL_UNSUPPORTED | unsupported |
| `getForumTopics` | QL_UNSUPPORTED | unsupported |
| `getFullRichMessage` | QL_UNSUPPORTED | unsupported |
| `getGiftAuctionState` | QL_UNSUPPORTED | unsupported |
| `getGiftChatThemes` | QL_UNSUPPORTED | unsupported |
| `getGroupCall` | QL_UNSUPPORTED | unsupported |
| `getGroupCallParticipants` | QL_UNSUPPORTED | unsupported |
| `getGroupsInCommon` | — (truthful empty result) | empty |
| `getInlineQueryResults` | QL_UNSUPPORTED | unsupported |
| `getInstalledBackgrounds` | QL_UNSUPPORTED | unsupported |
| `getInstalledStickerSets` | — (truthful empty result) | empty |
| `getInternalLinkType` | QL_UNSUPPORTED | unsupported |
| `getLanguagePackInfo` | QL_UNSUPPORTED | unsupported |
| `getLinkPreview` | QL_UNSUPPORTED | unsupported |
| `getLoginPasskeys` | QL_UNSUPPORTED | unsupported |
| `getMainWebApp` | QL_UNSUPPORTED | unsupported |
| `getMapThumbnailFile` | QL_UNSUPPORTED | unsupported |
| `getMe` | GET /v1/me | implemented |
| `getMessage` | GET /v1/conversations/{id}/messages or cache | implemented |
| `getMessageAddedReactions` | GET /v1/messages/{id}/reactions | implemented |
| `getMessageAvailableReactions` | — (fixed emoji set) | implemented |
| `getMessageEffect` | QL_UNSUPPORTED | unsupported |
| `getMessageLink` | QL_UNSUPPORTED | unsupported |
| `getMessageLinkInfo` | QL_UNSUPPORTED | unsupported |
| `getMessageProperties` | — (local) | implemented |
| `getMessageReadDate` | QL_UNSUPPORTED | unsupported |
| `getMessageThread` | QL_UNSUPPORTED | unsupported |
| `getMessageThreadHistory` | QL_UNSUPPORTED | unsupported |
| `getMessageViewers` | QL_UNSUPPORTED | unsupported |
| `getMessages` | — (cache / history) | implemented |
| `getNetworkStatistics` | QL_UNSUPPORTED | unsupported |
| `getOauthLinkInfo` | QL_UNSUPPORTED | unsupported |
| `getOption` | — (local constants) | implemented |
| `getOwnedStickerSets` | QL_UNSUPPORTED | unsupported |
| `getPasskeyParameters` | QL_UNSUPPORTED | unsupported |
| `getPassportAuthorizationForm` | QL_UNSUPPORTED | unsupported |
| `getPasswordState` | QL_UNSUPPORTED | unsupported |
| `getPaymentForm` | QL_UNSUPPORTED | unsupported |
| `getPollVoteStatistics` | QL_UNSUPPORTED | unsupported |
| `getPollVoters` | QL_UNSUPPORTED | unsupported |
| `getPremiumFeatures` | QL_UNSUPPORTED | unsupported |
| `getPremiumGiftPaymentOptions` | QL_UNSUPPORTED | unsupported |
| `getPremiumGiveawayPaymentOptions` | QL_UNSUPPORTED | unsupported |
| `getPreparedInlineMessage` | QL_UNSUPPORTED | unsupported |
| `getPreparedKeyboardButton` | QL_UNSUPPORTED | unsupported |
| `getProxies` | — (empty list) | implemented |
| `getPublicPostSearchLimits` | QL_UNSUPPORTED | unsupported |
| `getReadDatePrivacySettings` | QL_UNSUPPORTED | unsupported |
| `getReceivedGifts` | QL_UNSUPPORTED | unsupported |
| `getRecentInlineBots` | — (truthful empty result) | empty |
| `getRecentStickers` | — (truthful empty result) | empty |
| `getRecommendedChatFolders` | QL_UNSUPPORTED | unsupported |
| `getRecommendedChats` | — (truthful empty result) | empty |
| `getSavedAnimations` | — (truthful empty result) | empty |
| `getSavedNotificationSounds` | QL_UNSUPPORTED | unsupported |
| `getScopeNotificationSettings` | — (local defaults) | implemented |
| `getSecretChat` | QL_UNSUPPORTED | unsupported |
| `getStarGiveawayPaymentOptions` | QL_UNSUPPORTED | unsupported |
| `getStarPaymentOptions` | QL_UNSUPPORTED | unsupported |
| `getStickerSet` | QL_UNSUPPORTED | unsupported |
| `getStorageStatistics` | QL_UNSUPPORTED | unsupported |
| `getStorageStatisticsFast` | QL_UNSUPPORTED | unsupported |
| `getStory` | QL_UNSUPPORTED | unsupported |
| `getStoryAlbumStories` | QL_UNSUPPORTED | unsupported |
| `getStoryInteractions` | QL_UNSUPPORTED | unsupported |
| `getStoryNotificationSettingsExceptions` | — (truthful empty result) | empty |
| `getSuggestedStickerSetName` | QL_UNSUPPORTED | unsupported |
| `getSuitableDiscussionChats` | QL_UNSUPPORTED | unsupported |
| `getSupergroup` | channel chats as chatTypeSupergroup | implemented |
| `getSupergroupFullInfo` | GET /v1/conversations/{id}/members | implemented |
| `getSupergroupMembers` | QL_UNSUPPORTED | unsupported |
| `getTemporaryPasswordState` | QL_UNSUPPORTED | unsupported |
| `getTextEntities` | — (local regex) | implemented |
| `getTimeZones` | QL_UNSUPPORTED | unsupported |
| `getTonWalletTransaction` | QL_UNSUPPORTED | unsupported |
| `getTopChats` | — (truthful empty result) | empty |
| `getUpgradedGift` | QL_UNSUPPORTED | unsupported |
| `getUser` | GET /v1/users/{id} | implemented |
| `getUserFullInfo` | GET /v1/users/{id} | implemented |
| `getUserLink` | QL_UNSUPPORTED | unsupported |
| `getUserPrivacySettingRules` | QL_UNSUPPORTED | unsupported |
| `getUserProfilePhotos` | GET /v1/users/{id} (avatar) | implemented |
| `getWebAppLinkUrl` | QL_UNSUPPORTED | unsupported |
| `getWebAppUrl` | QL_UNSUPPORTED | unsupported |
| `getWebPageInstantView` | QL_UNSUPPORTED | unsupported |
| `joinChat` | QL_UNSUPPORTED | unsupported |
| `joinChatByInviteLink` | QL_UNSUPPORTED | unsupported |
| `joinGroupCall` | QL_UNSUPPORTED | unsupported |
| `joinVideoChat` | QL_UNSUPPORTED | unsupported |
| `leaveChat` | membership leave/delete | implemented |
| `leaveGroupCall` | QL_UNSUPPORTED | unsupported |
| `loadActiveStories` | — (truthful empty result) | empty |
| `loadChats` | GET /v1/conversations (initial load) | implemented |
| `loadDirectMessagesChatTopics` | QL_UNSUPPORTED | unsupported |
| `loadGroupCallParticipants` | QL_UNSUPPORTED | unsupported |
| `loadQuickReplyShortcutMessages` | QL_UNSUPPORTED | unsupported |
| `loadQuickReplyShortcuts` | QL_UNSUPPORTED | unsupported |
| `logOut` | drop session (and POST logout when the server exposes it) | implemented |
| `markChecklistTasksAsDone` | QL_UNSUPPORTED | unsupported |
| `openBotSimilarBot` | QL_UNSUPPORTED | unsupported |
| `openChat` | — (local) + POST /v1/conversations/{id}/read | implemented |
| `openChatSimilarChat` | QL_UNSUPPORTED | unsupported |
| `openStory` | QL_UNSUPPORTED | unsupported |
| `openWebApp` | QL_UNSUPPORTED | unsupported |
| `optimizeStorage` | QL_UNSUPPORTED | unsupported |
| `parseMarkdown` | — (pass-through / local) | implemented |
| `pinChatMessage` | PUT /v1/conversations/{id}/pins | implemented |
| `pingProxy` | QL_UNSUPPORTED | unsupported |
| `postStory` | QL_UNSUPPORTED | unsupported |
| `processChatJoinRequest` | QL_UNSUPPORTED | unsupported |
| `processChatJoinRequests` | QL_UNSUPPORTED | unsupported |
| `processWebProxyCarrierMessage` | QL_UNSUPPORTED | unsupported |
| `readAllDirectMessagesChatTopicReactions` | QL_UNSUPPORTED | unsupported |
| `recognizeSpeech` | QL_UNSUPPORTED | unsupported |
| `recoverPassword` | QL_UNSUPPORTED | unsupported |
| `registerDevice` | — (noop in P1) | implemented |
| `registerUser` | QL_UNSUPPORTED | unsupported |
| `removeAllFilesFromDownloads` | QL_UNSUPPORTED | unsupported |
| `removeBusinessConnectedBotFromChat` | QL_UNSUPPORTED | unsupported |
| `removeContacts` | QL_UNSUPPORTED | unsupported |
| `removeFileFromDownloads` | QL_UNSUPPORTED | unsupported |
| `removeLoginPasskey` | QL_UNSUPPORTED | unsupported |
| `removeMessageReaction` | PUT /v1/messages/{id}/reactions remove | implemented |
| `removeProxy` | QL_UNSUPPORTED | unsupported |
| `removeStickerFromSet` | QL_UNSUPPORTED | unsupported |
| `removeTextCompositionStyle` | QL_UNSUPPORTED | unsupported |
| `reorderChatFolders` | QL_UNSUPPORTED | unsupported |
| `reorderQuickReplyShortcuts` | QL_UNSUPPORTED | unsupported |
| `reorderStoryAlbums` | QL_UNSUPPORTED | unsupported |
| `replaceStickerInSet` | QL_UNSUPPORTED | unsupported |
| `reportChat` | POST /v1/conversations/{id}/report | implemented |
| `reportMessageReactions` | QL_UNSUPPORTED | unsupported |
| `reportStory` | QL_UNSUPPORTED | unsupported |
| `reportWebProxyCarrierError` | QL_UNSUPPORTED | unsupported |
| `requestPasswordRecovery` | QL_UNSUPPORTED | unsupported |
| `requestQrCodeAuthentication` | QL_UNSUPPORTED | unsupported |
| `resendAuthenticationCode` | QL_UNSUPPORTED | unsupported |
| `resendPhoneNumberCode` | QL_UNSUPPORTED | unsupported |
| `resendRecoveryEmailAddressCode` | QL_UNSUPPORTED | unsupported |
| `resetAuthenticationEmailAddress` | QL_UNSUPPORTED | unsupported |
| `resetNetworkStatistics` | QL_UNSUPPORTED | unsupported |
| `revokeChatInviteLink` | QL_UNSUPPORTED | unsupported |
| `searchBackground` | QL_UNSUPPORTED | unsupported |
| `searchCallMessages` | QL_UNSUPPORTED | unsupported |
| `searchChatAffiliateProgram` | QL_UNSUPPORTED | unsupported |
| `searchChatMembers` | QL_UNSUPPORTED | unsupported |
| `searchChatMessages` | GET /v1/conversations/{id}/search or /media; pinned via /pins | implemented |
| `searchChats` | GET /v1/users/search (plus local title filter) | implemented |
| `searchContacts` | GET /v1/users/search | implemented |
| `searchEmojis` | QL_UNSUPPORTED | unsupported |
| `searchFileDownloads` | QL_UNSUPPORTED | unsupported |
| `searchMessages` | GET /v1/conversations/{id}/search across announced chats | implemented |
| `searchPublicChat` | GET /v1/users/search | implemented |
| `searchPublicChats` | GET /v1/users/search | implemented |
| `searchPublicMessagesByTag` | QL_UNSUPPORTED | unsupported |
| `searchPublicPosts` | QL_UNSUPPORTED | unsupported |
| `searchStickerSet` | QL_UNSUPPORTED | unsupported |
| `searchStickers` | — (truthful empty result) | empty |
| `searchTextCompositionStyle` | QL_UNSUPPORTED | unsupported |
| `searchUserByPhoneNumber` | QL_UNSUPPORTED | unsupported |
| `searchUserByToken` | QL_UNSUPPORTED | unsupported |
| `searchWebApp` | QL_UNSUPPORTED | unsupported |
| `sendBotStartMessage` | QL_UNSUPPORTED | unsupported |
| `sendCallSignalingData` | QL_UNSUPPORTED | unsupported |
| `sendChatAction` | WS typing | implemented |
| `sendInlineQueryResultMessage` | QL_UNSUPPORTED | unsupported |
| `sendMessage` | POST /v1/conversations/{id}/messages (+ POST /v1/media) | implemented |
| `sendPaymentForm` | QL_UNSUPPORTED | unsupported |
| `sendPhoneNumberCode` | QL_UNSUPPORTED | unsupported |
| `sendQuickReplyShortcutMessages` | QL_UNSUPPORTED | unsupported |
| `sendWebAppCustomRequest` | QL_UNSUPPORTED | unsupported |
| `sendWebAppData` | QL_UNSUPPORTED | unsupported |
| `setAccentColor` | QL_UNSUPPORTED | unsupported |
| `setAccountTtl` | QL_UNSUPPORTED | unsupported |
| `setAuthenticationEmailAddress` | QL_UNSUPPORTED | unsupported |
| `setAuthenticationPhoneNumber` | QL_UNSUPPORTED | unsupported |
| `setAuthenticationPremiumPurchaseTransaction` | QL_UNSUPPORTED | unsupported |
| `setAutoDownloadSettings` | QL_UNSUPPORTED | unsupported |
| `setBio` | QL_UNSUPPORTED | unsupported |
| `setBirthdate` | QL_UNSUPPORTED | unsupported |
| `setBotUpdatesStatus` | QL_UNSUPPORTED | unsupported |
| `setBusinessAwayMessageSettings` | QL_UNSUPPORTED | unsupported |
| `setBusinessConnectedBot` | QL_UNSUPPORTED | unsupported |
| `setBusinessGreetingMessageSettings` | QL_UNSUPPORTED | unsupported |
| `setBusinessLocation` | QL_UNSUPPORTED | unsupported |
| `setBusinessOpeningHours` | QL_UNSUPPORTED | unsupported |
| `setBusinessStartPage` | QL_UNSUPPORTED | unsupported |
| `setChatAvailableReactions` | QL_UNSUPPORTED | unsupported |
| `setChatBackground` | QL_UNSUPPORTED | unsupported |
| `setChatDescription` | QL_UNSUPPORTED | unsupported |
| `setChatDiscussionGroup` | QL_UNSUPPORTED | unsupported |
| `setChatDraftMessage` | — (local) | implemented |
| `setChatEmojiStatus` | QL_UNSUPPORTED | unsupported |
| `setChatMemberStatus` | PATCH /v1/conversations/{id}/members/{user} | implemented |
| `setChatMemberTag` | QL_UNSUPPORTED | unsupported |
| `setChatMessageAutoDeleteTime` | QL_UNSUPPORTED | unsupported |
| `setChatMessageSender` | QL_UNSUPPORTED | unsupported |
| `setChatNotificationSettings` | PATCH /v1/conversations/{id} (muted) | implemented |
| `setChatPermissions` | QL_UNSUPPORTED | unsupported |
| `setChatPhoto` | PATCH /v1/conversations/{id} avatar_media_id | implemented |
| `setChatPinnedStories` | QL_UNSUPPORTED | unsupported |
| `setChatProfileAccentColor` | QL_UNSUPPORTED | unsupported |
| `setChatSlowModeDelay` | QL_UNSUPPORTED | unsupported |
| `setChatTheme` | QL_UNSUPPORTED | unsupported |
| `setChatTitle` | PATCH /v1/conversations/{id} title | implemented |
| `setCommunityName` | QL_UNSUPPORTED | unsupported |
| `setCommunityPhoto` | QL_UNSUPPORTED | unsupported |
| `setCustomEmojiStickerSetThumbnail` | QL_UNSUPPORTED | unsupported |
| `setDefaultBackground` | QL_UNSUPPORTED | unsupported |
| `setDefaultMessageAutoDeleteTime` | QL_UNSUPPORTED | unsupported |
| `setDirectMessagesChatTopicIsMarkedAsUnread` | QL_UNSUPPORTED | unsupported |
| `setEmojiStatus` | QL_UNSUPPORTED | unsupported |
| `setForumTopicNotificationSettings` | QL_UNSUPPORTED | unsupported |
| `setGiftSettings` | QL_UNSUPPORTED | unsupported |
| `setLogVerbosityLevel` | — (noop) | implemented |
| `setMessageSenderBlockList` | PUT /v1/users/{id}/block | implemented |
| `setName` | PATCH /v1/me | implemented |
| `setOption` | — (noop) | implemented |
| `setPassword` | QL_UNSUPPORTED | unsupported |
| `setPersonalChat` | QL_UNSUPPORTED | unsupported |
| `setPinnedForumTopics` | QL_UNSUPPORTED | unsupported |
| `setPollAnswer` | QL_UNSUPPORTED | unsupported |
| `setProfileAccentColor` | QL_UNSUPPORTED | unsupported |
| `setProfilePhoto` | PATCH /v1/me + media upload | implemented |
| `setQuickReplyShortcutName` | QL_UNSUPPORTED | unsupported |
| `setReactionNotificationSettings` | QL_UNSUPPORTED | unsupported |
| `setReadDatePrivacySettings` | QL_UNSUPPORTED | unsupported |
| `setRecoveryEmailAddress` | QL_UNSUPPORTED | unsupported |
| `setScopeNotificationSettings` | QL_UNSUPPORTED | unsupported |
| `setStickerEmojis` | QL_UNSUPPORTED | unsupported |
| `setStickerKeywords` | QL_UNSUPPORTED | unsupported |
| `setStickerMaskPosition` | QL_UNSUPPORTED | unsupported |
| `setStickerPositionInSet` | QL_UNSUPPORTED | unsupported |
| `setStickerSetThumbnail` | QL_UNSUPPORTED | unsupported |
| `setStickerSetTitle` | QL_UNSUPPORTED | unsupported |
| `setStoryAlbumName` | QL_UNSUPPORTED | unsupported |
| `setStoryPrivacySettings` | QL_UNSUPPORTED | unsupported |
| `setStoryReaction` | QL_UNSUPPORTED | unsupported |
| `setSupergroupUsername` | QL_UNSUPPORTED | unsupported |
| `setTdlibParameters` | — (loads session, then GET /v1/me, /v1/sync, /v1/conversations) | implemented |
| `setUserNote` | QL_UNSUPPORTED | unsupported |
| `setUserPersonalProfilePhoto` | QL_UNSUPPORTED | unsupported |
| `setUserPrivacySettingRules` | QL_UNSUPPORTED | unsupported |
| `setUsername` | QL_UNSUPPORTED | unsupported |
| `sharePhoneNumber` | QL_UNSUPPORTED | unsupported |
| `startLiveStory` | QL_UNSUPPORTED | unsupported |
| `stopPoll` | QL_UNSUPPORTED | unsupported |
| `suggestUserBirthdate` | QL_UNSUPPORTED | unsupported |
| `suggestUserProfilePhoto` | QL_UNSUPPORTED | unsupported |
| `summarizeMessage` | QL_UNSUPPORTED | unsupported |
| `terminateAllOtherSessions` | QL_UNSUPPORTED | unsupported |
| `terminateSession` | QL_UNSUPPORTED | unsupported |
| `testProxy` | QL_UNSUPPORTED | unsupported |
| `toggleAllDownloadsArePaused` | QL_UNSUPPORTED | unsupported |
| `toggleBotCanManageEmojiStatus` | QL_UNSUPPORTED | unsupported |
| `toggleBotIsAddedToAttachmentMenu` | QL_UNSUPPORTED | unsupported |
| `toggleBusinessConnectedBotChatIsPaused` | QL_UNSUPPORTED | unsupported |
| `toggleChatFolderTags` | QL_UNSUPPORTED | unsupported |
| `toggleChatHasProtectedContent` | QL_UNSUPPORTED | unsupported |
| `toggleChatIsMarkedAsUnread` | PATCH /v1/conversations/{id} | implemented |
| `toggleChatIsPinned` | PATCH /v1/conversations/{id} (pinned) | implemented |
| `toggleDirectMessagesChatTopicCanSendUnpaidMessages` | QL_UNSUPPORTED | unsupported |
| `toggleDownloadIsPaused` | QL_UNSUPPORTED | unsupported |
| `toggleForumTopicIsClosed` | QL_UNSUPPORTED | unsupported |
| `toggleForumTopicIsPinned` | QL_UNSUPPORTED | unsupported |
| `toggleGroupCallIsMyVideoEnabled` | QL_UNSUPPORTED | unsupported |
| `toggleGroupCallParticipantIsMuted` | QL_UNSUPPORTED | unsupported |
| `toggleStoryIsPostedToChatPage` | QL_UNSUPPORTED | unsupported |
| `toggleSupergroupHasAggressiveAntiSpamEnabled` | QL_UNSUPPORTED | unsupported |
| `toggleSupergroupHasAutomaticTranslation` | QL_UNSUPPORTED | unsupported |
| `toggleSupergroupHasHiddenMembers` | QL_UNSUPPORTED | unsupported |
| `toggleSupergroupIsAllHistoryAvailable` | QL_UNSUPPORTED | unsupported |
| `toggleSupergroupIsForum` | QL_UNSUPPORTED | unsupported |
| `toggleSupergroupJoinByRequest` | QL_UNSUPPORTED | unsupported |
| `toggleSupergroupJoinToSendMessages` | QL_UNSUPPORTED | unsupported |
| `toggleSupergroupSignMessages` | QL_UNSUPPORTED | unsupported |
| `transferChatOwnership` | QL_UNSUPPORTED | unsupported |
| `translateMessageText` | QL_UNSUPPORTED | unsupported |
| `translateText` | QL_UNSUPPORTED | unsupported |
| `unpinAllDirectMessagesChatTopicMessages` | QL_UNSUPPORTED | unsupported |
| `unpinChatMessage` | PUT /v1/conversations/{id}/pins remove | implemented |
| `upgradeBasicGroupChatToSupergroupChat` | QL_UNSUPPORTED | unsupported |
| `uploadStickerFile` | QL_UNSUPPORTED | unsupported |
| `validateOrderInfo` | QL_UNSUPPORTED | unsupported |
| `viewMessages` | POST /v1/conversations/{id}/read | implemented |

Status meanings:

- **implemented** — engine handles the call against the backend or a truthful local store (including no-ops that change nothing).
- **empty** — returns the correct empty TDLib collection (no stickers/stories/sessions yet).
- **unsupported** — returns `{ "@type": "error", "code": 400, "message": "QL_UNSUPPORTED: …" }`. The corresponding Settings row or composer action is hidden or marked 暂未开放.

