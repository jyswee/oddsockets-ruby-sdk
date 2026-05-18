# frozen_string_literal: true

require 'json'

module OddSockets
  # Enhanced Features for OddSockets Ruby SDK
  # Provides 67 new Slack-like events with Ruby blocks and async patterns
  class EnhancedFeatures
    def initialize(client)
      @client = client
      @timeout = 10
    end

    # ==================== THREAD EVENTS ====================

    def thread_reply(channel:, parent_message_id:, message:, user_id:, user_name:, &block)
      params = {
        channel: channel,
        parentMessageId: parent_message_id,
        message: message,
        userId: user_id,
        userName: user_name
      }
      emit_with_response('thread_reply', params, 'thread_reply_success', &block)
    end

    def get_thread(thread_id, &block)
      emit_with_response('get_thread', { threadId: thread_id }, 'thread_data', &block)
    end

    def subscribe_thread(thread_id, user_id, &block)
      params = { threadId: thread_id, userId: user_id }
      emit_with_response('subscribe_thread', params, 'thread_subscribed', &block)
    end

    def mark_thread_read(thread_id, user_id)
      @client.emit('mark_thread_read', { threadId: thread_id, userId: user_id })
    end

    def follow_thread(thread_id, user_id)
      @client.emit('follow_thread', { threadId: thread_id, userId: user_id })
    end

    def unfollow_thread(thread_id, user_id)
      @client.emit('unfollow_thread', { threadId: thread_id, userId: user_id })
    end

    # ==================== REACTION EVENTS ====================

    def add_reaction(message_id:, channel:, emoji:, user_id:, user_name:)
      params = {
        messageId: message_id,
        channel: channel,
        emoji: emoji,
        userId: user_id,
        userName: user_name
      }
      @client.emit('add_reaction', params)
    end

    def remove_reaction(message_id:, channel:, emoji:, user_id:)
      params = {
        messageId: message_id,
        channel: channel,
        emoji: emoji,
        userId: user_id
      }
      @client.emit('remove_reaction', params)
    end

    def get_reactions(message_id, &block)
      emit_with_response('get_reactions', { messageId: message_id }, 'message_reactions', &block)
    end

    # ==================== READ RECEIPT EVENTS ====================

    def mark_read(message_id:, channel:, user_id:, user_name:)
      params = {
        messageId: message_id,
        channel: channel,
        userId: user_id,
        userName: user_name
      }
      @client.emit('mark_read', params)
    end

    def get_unread_counts(user_id, channels, &block)
      params = { userId: user_id, channels: channels }
      emit_with_response('get_unread_counts', params, 'unread_counts', &block)
    end

    def mark_all_read(channel, user_id)
      @client.emit('mark_all_read', { channel: channel, userId: user_id })
    end

    # ==================== CHANNEL EVENTS ====================

    def create_channel(name:, type:, description:, topic:, created_by:, created_by_name:, &block)
      params = {
        name: name,
        type: type,
        description: description,
        topic: topic,
        createdBy: created_by,
        createdByName: created_by_name,
        members: []
      }
      emit_with_response('create_channel', params, 'channel_create_success', &block)
    end

    def update_channel(channel_id, updates, user_id)
      params = {
        channelId: channel_id,
        updates: updates,
        userId: user_id
      }
      @client.emit('update_channel', params)
    end

    def archive_channel(channel_id, user_id)
      @client.emit('archive_channel', { channelId: channel_id, userId: user_id })
    end

    def invite_to_channel(channel_id:, invited_user_id:, invited_user_name:, invited_by:)
      params = {
        channelId: channel_id,
        invitedUserId: invited_user_id,
        invitedUserName: invited_user_name,
        invitedBy: invited_by
      }
      @client.emit('invite_to_channel', params)
    end

    def remove_from_channel(channel_id:, removed_user_id:, removed_by:)
      params = {
        channelId: channel_id,
        removedUserId: removed_user_id,
        removedBy: removed_by
      }
      @client.emit('remove_from_channel', params)
    end

    def join_channel(channel_id, user_id, user_name)
      params = {
        channelId: channel_id,
        userId: user_id,
        userName: user_name
      }
      @client.emit('join_channel', params)
    end

    def leave_channel(channel_id, user_id)
      @client.emit('leave_channel', { channelId: channel_id, userId: user_id })
    end

    def get_channel_members(channel_id, &block)
      emit_with_response('get_channel_members', { channelId: channel_id }, 'channel_members', &block)
    end

    # ==================== DIRECT MESSAGE EVENTS ====================

    def create_dm(user_ids, type, &block)
      params = { userIds: user_ids, type: type }
      emit_with_response('create_dm', params, 'dm_create_success', &block)
    end

    def send_dm(conversation_id:, message:, user_id:, user_name:)
      params = {
        conversationId: conversation_id,
        message: message,
        userId: user_id,
        userName: user_name
      }
      @client.emit('send_dm', params)
    end

    def get_dm_conversations(user_id, include_archived, &block)
      params = { userId: user_id, includeArchived: include_archived }
      emit_with_response('get_dm_conversations', params, 'dm_conversations', &block)
    end

    # ==================== NOTIFICATION EVENTS ====================

    def subscribe_notifications(user_id)
      @client.emit('subscribe_notifications', { userId: user_id })
    end

    def mark_notification_read(notification_id, user_id)
      params = { notificationId: notification_id, userId: user_id }
      @client.emit('mark_notification_read', params)
    end

    def mark_all_notifications_read(user_id)
      @client.emit('mark_all_notifications_read', { userId: user_id })
    end

    def clear_notifications(user_id)
      @client.emit('clear_notifications', { userId: user_id })
    end

    def get_notifications(user_id, limit, status = 'all', &block)
      params = { userId: user_id, limit: limit, status: status }
      emit_with_response('get_notifications', params, 'notifications_data', &block)
    end

    # ==================== PRESENCE EVENTS ====================

    def set_status(user_id, status)
      @client.emit('set_status', { userId: user_id, status: status })
    end

    def set_custom_status(user_id, emoji, text, expires_at = nil)
      params = { userId: user_id, emoji: emoji, text: text }
      params[:expiresAt] = expires_at if expires_at
      @client.emit('set_custom_status', params)
    end

    def clear_custom_status(user_id)
      @client.emit('clear_custom_status', { userId: user_id })
    end

    def set_dnd(user_id, until_time = nil)
      params = { userId: user_id }
      params[:until] = until_time if until_time
      @client.emit('set_dnd', params)
    end

    def clear_dnd(user_id)
      @client.emit('clear_dnd', { userId: user_id })
    end

    def start_typing(user_id, channel)
      @client.emit('start_typing', { userId: user_id, channel: channel })
    end

    def stop_typing(user_id, channel)
      @client.emit('stop_typing', { userId: user_id, channel: channel })
    end

    def get_user_presence(user_ids, &block)
      emit_with_response('get_user_presence', { userIds: user_ids }, 'user_presence_data', &block)
    end

    # ==================== MESSAGE EDITING EVENTS ====================

    def edit_message(message_id, channel, new_content, user_id)
      params = {
        messageId: message_id,
        channel: channel,
        newContent: new_content,
        userId: user_id
      }
      @client.emit('edit_message', params)
    end

    def delete_message(message_id, channel, user_id)
      params = {
        messageId: message_id,
        channel: channel,
        userId: user_id
      }
      @client.emit('delete_message', params)
    end

    def pin_message(message_id, channel, user_id)
      params = {
        messageId: message_id,
        channel: channel,
        userId: user_id
      }
      @client.emit('pin_message', params)
    end

    def unpin_message(message_id, channel, user_id)
      params = {
        messageId: message_id,
        channel: channel,
        userId: user_id
      }
      @client.emit('unpin_message', params)
    end

    def get_pinned_messages(channel, &block)
      emit_with_response('get_pinned_messages', { channel: channel }, 'pinned_messages', &block)
    end

    # ==================== SEARCH EVENTS ====================

    def search_messages(query, user_id, limit, &block)
      params = { query: query, userId: user_id, limit: limit }
      emit_with_response('search_messages', params, 'search_results', &block)
    end

    def filter_messages(filters, &block)
      emit_with_response('filter_messages', filters, 'filter_results', &block)
    end

    def search_in_channel(channel, query, limit, &block)
      params = { channel: channel, query: query, limit: limit }
      emit_with_response('search_in_channel', params, 'channel_search_results', &block)
    end

    def search_by_user(user_id, query, limit, &block)
      params = { userId: user_id, limit: limit }
      params[:query] = query if query
      emit_with_response('search_by_user', params, 'user_search_results', &block)
    end

    private

    def emit_with_response(event, params, response_event, &block)
      @client.emit(event, params)
      @client.once(response_event, &block) if block_given?
    end
  end
end
