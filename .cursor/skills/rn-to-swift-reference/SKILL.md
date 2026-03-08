---
name: rn-to-swift-reference
description: Tham chiếu logic từ React Native khi port feature sang Swift iOS. Use when implementing feature that exists in RN mezon app.
---

# RN → Swift Reference

## Paths

- RN store: `/Users/thomas/Documents/ReactNativeClone/mezon/libs/store/src/lib/`
- channels: `channels/channels.slice.ts` - joinChannel, joinChat
- messages: `messages/messages.slice.ts` - fetchMessages, listChannelMessages
- RN screens: `apps/mobile/src/app/screens/home/homedrawer/`

## Mapping

| RN | Swift |
|----|-------|
| channelsActions.joinChat | MezonSocket.shared.joinChannel |
| messagesActions.fetchMessages | MezonHTTPClient.listChannelMessages |
| direction Direction_Mode.BEFORE_TIMESTAMP (3) | direction: 3 |
| content?.t (JSON) | extractTextFromContent - parse {"t":"..."} |
| selectMessagesByChannel | viewModel.$messages |

## API params

- clanId, channelId: Int64 (Swift) / string (RN)
- messageId: 0 cho initial load
- limit: 50 (LIMIT_MESSAGE)
