# frozen_string_literal: true

require 'json'
require 'securerandom'
require 'digest'
require_relative 'turn_state/form'
require_relative 'workspace/chats'
require_relative 'workbench/caller'

module Monadic
  # An app's state made from what each reply changed (Form): the reply's
  # changes are kept with its message, and the state now is what the
  # messages left in the chat changed, the newest for each value or item,
  # on top of the base the chat began with. Deleting a turn takes its
  # changes with it.
  #
  # While a reply runs, what it changes is kept for it alone (its record)
  # and given to its message once (seal), or let go when it ends without
  # one (close). One reply of a chat changes its state at a time: another
  # is refused (Busy) until that one ends. A record begun before the chat
  # changed under it (a turn deleted, a file read in, the chat resumed or
  # left) is let go rather than given to the message.
  module TurnState
    class Refused < StandardError; end
    class Busy < Refused; end

    CLOSED_LIMIT = 1000

    @records = {}
    @writers = {}
    @revisions = Hash.new(0)
    @closed = {}
    @cache = {}
    @update_locks = Hash.new { |h, k| h[k] = Mutex.new }
    @lock = Mutex.new

    Record = Struct.new(:chat_id, :epoch, :app, :revision, :changes, keyword_init: true)

    module_function

    # --- reading -----------------------------------------------------------

    # The value of key for the app the session is in now: { found:, data:,
    # version:, updated_at: } (found: false when no change and no base has
    # it, or it was removed). The running reply sees its own changes.
    def value(session, key)
      app = app_of(session)
      change = pending(session, app, ['value', key])
      return from_change(change, committed(session, app)[:values][key]) if change

      entry = committed(session, app)[:values][key]
      return { found: false, data: nil, version: 0, updated_at: nil } if entry.nil?

      entry
    end

    # The data of key for the app the session is in; nil when there is
    # none (or it was removed).
    def data_of(session, key)
      return nil unless session.respond_to?(:[])

      entry = value(session, key.to_s)
      entry[:found] ? entry[:data] : nil
    end

    # The items of collection, oldest first: [{ id:, data:, by: }] (by: the
    # mid of the message that changed it last; nil for the base or the
    # running reply).
    def items(session, collection)
      app = app_of(session)
      index = committed(session, app)[:items][collection] || { order: [], data: {}, removed: {}, by: {} }
      order = index[:order].dup
      data = index[:data].dup
      removed = index[:removed].dup
      by = index[:by].dup
      pending_items(session, app, collection).each do |change|
        id = change['id']
        order << id unless order.include?(id)
        if change['op'] == 'remove'
          removed[id] = true
        else
          removed.delete(id)
          data[id] = change['data']
        end
        by[id] = nil
      end
      order.filter_map { |id| { id: id, data: data[id], by: by[id] } if data.key?(id) && !removed[id] }
    end

    # --- changing (for the running reply) ----------------------------------

    def set_value(session, key, data)
      change!(session, { 'kind' => 'value', 'key' => key.to_s, 'op' => 'set', 'data' => data })
    end

    def remove_value(session, key)
      change!(session, { 'kind' => 'value', 'key' => key.to_s, 'op' => 'remove' })
    end

    # Puts an item's whole value; a new item is given an id. Returns the id.
    def put_item(session, collection, data, id: nil)
      id = id.to_s.empty? ? "i_#{SecureRandom.alphanumeric(10).downcase}" : id.to_s
      change!(session, { 'kind' => 'item', 'collection' => collection.to_s, 'id' => id, 'op' => 'set', 'data' => data })
      id
    end

    # The id of an item that is a text: the same wherever the text is put
    # again.
    def text_id(text)
      "t_#{Digest::SHA256.hexdigest(text.to_s)[0, 24]}"
    end

    def remove_item(session, collection, id)
      change!(session, { 'kind' => 'item', 'collection' => collection.to_s, 'id' => id.to_s, 'op' => 'remove' })
    end

    # The value of key changed by the block, which only computes (it is
    # given the value now, or default, and returns the new one) while the
    # reply's other changes to the chat's state wait. Nothing changes when
    # it raises.
    def update(session, key, default = nil)
      chat_id = writer!(session).chat_id
      lock = @lock.synchronize { @update_locks[chat_id] }
      raise Refused, 'the state is being changed by this same update' if lock.owned?

      lock.synchronize do
        now = value(session, key)
        new_value = yield(now[:found] ? now[:data] : default)
        set_value(session, key, new_value)
        new_value
      end
    end

    # --- the reply's end ---------------------------------------------------

    # The reply's changes for its message (checked, frozen), once; nil when
    # it changed nothing, or the chat changed under it.
    def seal(request_id, session)
      record = take(request_id)
      return nil unless record && !record.changes.empty?
      return nil unless current?(record)

      changes = Form.clean_changes(record.changes.values, limit: Form::SAVE_BYTES)
      return nil unless changes && chat_bytes(session) + JSON.generate(changes).bytesize <= Form::CHAT_BYTES

      changed!(record.chat_id)
      changes
    end

    # The reply ended: what it changed and no message took is let go.
    def close(request_id)
      take(request_id)
      nil
    end

    # The chat changed in a way a running reply's changes cannot follow (a
    # turn deleted, a file read in, the chat resumed): its derived state is
    # made again, and a record begun before is let go at its seal.
    def changed!(chat_id)
      return unless chat_id

      @lock.synchronize do
        @revisions[chat_id] += 1
        @cache.delete(chat_id)
      end
    end

    # For tests.
    def reset!
      @lock.synchronize do
        @records.clear
        @writers.clear
        @revisions.clear
        @closed.clear
        @cache.clear
        @update_locks.clear
      end
    end

    # --- inside ------------------------------------------------------------

    def app_of(session)
      params = session.respond_to?(:[]) ? (session[:parameters] || session['parameters']) : nil
      (params && (params['app_name'] || params[:app_name])).to_s
    end

    # The running reply's record, made at its first change: the chat, the
    # epoch and the app it changes, and the chat's revision then. Refused
    # without a running reply, or while another reply changes the chat.
    def writer!(session)
      caller = Monadic::Workbench::Caller.current(session)
      raise Refused, 'only a running reply of this chat can change its state' unless caller&.request_id

      request_id = caller.request_id
      @lock.synchronize do
        raise Refused, 'this reply has ended' if @closed.key?(request_id)

        holder = @writers[caller.chat_id]
        if holder && holder != request_id
          raise Busy, 'another reply of this chat is changing its state; try again after it ends'
        end

        @writers[caller.chat_id] = request_id
        @records[request_id] ||= Record.new(chat_id: caller.chat_id, epoch: caller.epoch, app: app_of(session),
                                            revision: @revisions[caller.chat_id], changes: {})
      end
    end

    def change!(session, change)
      change_all!(session, [change])
    end

    # Several changes of the running reply as one: all are made, or, when
    # one does not fit or the reply would change too much, none.
    def change_all!(session, list)
      record = writer!(session)
      checked = list.map { |change| Form.change(change.merge('app' => record.app)) }
      if (at = checked.index(nil))
        raise Refused, "the change does not fit the form of state (#{shape(list[at], record.app)})"
      end

      @lock.synchronize do
        changes = record.changes.dup
        checked.each { |change| changes[slot(change)] = change }
        raise Refused, "a reply can change #{Form::ENTRIES} values and items of the state at most" if changes.size > Form::ENTRIES

        size = JSON.generate(changes.values).bytesize
        raise Refused, "the state this reply changed would be larger than #{Form::SAVE_BYTES / 1024} KB" if size > Form::SAVE_BYTES

        record.changes = changes
      end
      nil
    rescue Form::Invalid => e
      raise Refused, "the value cannot be kept in state: #{e.message}"
    end

    # What a refused change was of, without what it holds.
    def shape(change, app)
      c = change.is_a?(Hash) ? change.transform_keys(&:to_s) : {}
      "app #{app.inspect}, #{c['kind']} #{(c['key'] || c['collection']).inspect}, id #{c['id'].inspect}, #{c['op']}, keys #{c.keys.sort.join(' ')}"
    end

    def slot(change)
      change['kind'] == 'value' ? ['value', change['key']] : ['item', change['collection'], change['id']]
    end

    def take(request_id)
      return nil unless request_id

      @lock.synchronize do
        @closed[request_id] = true
        @closed.shift while @closed.size > CLOSED_LIMIT
        record = @records.delete(request_id)
        @writers.delete(record.chat_id) if record && @writers[record.chat_id] == request_id
        record
      end
    end

    def current?(record)
      epoch_now = Monadic::Workspace::Chats.epoch(record.chat_id)
      @lock.synchronize { record.epoch == epoch_now && @revisions[record.chat_id] == record.revision }
    end

    # The running reply's own change at slot, if it made one.
    def pending(session, app, slot)
      record = own_record(session)
      return nil unless record && record.app == app

      @lock.synchronize { record.changes[slot] }
    end

    def pending_items(session, app, collection)
      record = own_record(session)
      return [] unless record && record.app == app

      @lock.synchronize do
        record.changes.values.select { |c| c['kind'] == 'item' && c['collection'] == collection }
      end
    end

    def own_record(session)
      caller = Monadic::Workbench::Caller.current(session)
      caller&.request_id && @lock.synchronize { @records[caller.request_id] }
    end

    def from_change(change, committed_entry)
      version = (committed_entry ? committed_entry[:version] : 0) + 1
      return { found: false, data: nil, version: version, updated_at: nil } if change['op'] == 'remove'

      { found: true, data: change['data'], version: version, updated_at: nil }
    end

    # The state the chat's messages and base make for app: { values: { key
    # => entry }, items: { collection => { order:, data:, removed: } } },
    # kept per chat until its messages or revision change.
    def committed(session, app)
      chat_id = session.respond_to?(:[]) ? session[Monadic::Workspace::Chats::SESSION_KEY] : nil
      messages = Array(session.respond_to?(:[]) ? session[:messages] : nil)
      signature = [app, @lock.synchronize { @revisions[chat_id] }, messages.size,
                   messages.last.is_a?(Hash) ? messages.last['mid'] : nil, base_of(session, app).hash]
      cached = chat_id && @lock.synchronize { @cache[chat_id] }
      return cached[:index] if cached && cached[:signature] == signature

      index = build(messages, base_of(session, app), app)
      @lock.synchronize { @cache[chat_id] = { signature: signature, index: index } } if chat_id
      index
    end

    def base_of(session, app)
      state = session.respond_to?(:[]) ? session[:monadic_state] : nil
      entries = state.is_a?(Hash) ? (state[app] || state[app.to_sym]) : nil
      entries.is_a?(Hash) ? entries : {}
    end

    def build(messages, base, app)
      values = {}
      base.each do |key, entry|
        next if key.to_s.start_with?('_') || !entry.is_a?(Hash)

        values[key.to_s] = { found: true, data: entry[:data] || entry['data'],
                             version: (entry[:version] || entry['version']).to_i,
                             updated_at: entry[:updated_at] || entry['updated_at'] }
      end
      items = base_items(base)
      messages.each do |message|
        next unless message.is_a?(Hash)

        Array(Form.clean_changes(message[Form::STATE_CHANGES_KEY])).each do |change|
          next unless change['app'] == app

          change['kind'] == 'value' ? fold_value(values, change, message) : fold_item(items, change, message)
        end
      end
      { values: values, items: items }
    end

    def fold_value(values, change, message)
      version = (values[change['key']]&.dig(:version) || 0) + 1
      values[change['key']] = { found: change['op'] == 'set', data: change['data'], version: version,
                                updated_at: message['timestamp'], by: message['mid'] }
    end

    def fold_item(items, change, message)
      index = (items[change['collection']] ||= { order: [], data: {}, removed: {}, by: {} })
      id = change['id']
      index[:order] << id unless index[:order].include?(id)
      index[:by][id] = message['mid']
      if change['op'] == 'remove'
        index[:removed][id] = true
      else
        index[:removed].delete(id)
        index[:data][id] = change['data']
      end
    end

    # The items the base holds (its "_items" entry: { collection => { id =>
    # data } }, in order).
    def base_items(base)
      entry = base['_items'] || base[:_items]
      data = entry.is_a?(Hash) ? (entry[:data] || entry['data']) : nil
      return {} unless data.is_a?(Hash)

      data.each_with_object({}) do |(collection, found), out|
        next unless found.is_a?(Hash)

        out[collection.to_s] = { order: found.keys.map(&:to_s), data: found.transform_keys(&:to_s), removed: {}, by: {} }
      end
    end

    def chat_bytes(session)
      Array(session.respond_to?(:[]) ? session[:messages] : nil).sum do |message|
        changes = message.is_a?(Hash) ? message[Form::STATE_CHANGES_KEY] : nil
        changes ? JSON.generate(changes).bytesize : 0
      end
    end
  end
end
