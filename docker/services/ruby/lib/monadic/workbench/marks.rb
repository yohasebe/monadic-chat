# frozen_string_literal: true

module Monadic
  module Workbench
    # The marks the user made on the work screen's items and sent with their
    # messages, kept on the board (the manifest's 'marks'), per original and
    # its version: the same file at the same path and version finds its marks
    # again; another file with the same bytes, or a new version, does not.
    #
    # They are kept as operations, each the user message's (its request):
    # add (a new mark), change (a mark of this turn moved), use (a mark sent
    # or looked at again), erase (marks taken off the item). What is shown is
    # what the operations give in the order they were taken; deleting a
    # message takes its operations out (an erase it made is undone, a mark a
    # later message changed or used stays as that message left it).
    #
    # Functions of the board's data, called inside its change.
    module Marks
      KEY = 'marks'
      # Marks shown at most on one version of an original (all its pages).
      SHOWN_LIMIT = 32
      # Operations kept at most per version (the oldest of marks no longer
      # shown go first).
      OPS_LIMIT = 400
      SHAPES = %w[rect ellipse].freeze
      # The operations of marks (the others are of drawings).
      MARK_KINDS = %w[add change use].freeze
      ID = /\Am_[a-z0-9]{6,32}\z/

      module_function

      # The original an item is of: its file's path, the image the AI made,
      # or the Library entry; nil for anything else (a browser).
      def origin_of(item)
        return "file:#{item.dig('file', 'path')}" if item['kind'] == 'file' && item.dig('file', 'path')
        return "artifact:#{item.dig('artifact', 'id')}" if item['kind'] == 'image' && item.dig('artifact', 'id')
        return "library:#{item.dig('library', 'id')}" if item['kind'] == 'library' && item.dig('library', 'id')

        nil
      end

      # The marks shown on version of origin, in the order they were made:
      # [{ 'id', 'rev', 'shape', 'color', 'page', 'rect' }].
      def shown(data, origin, version)
        replay(ops_of(data, origin, version)).values
      end

      # Records the marks the message request_id sent (each { 'id', 'rev',
      # 'shape', 'color', 'page', 'rect' } on the item of origin at version)
      # and the erasures it carried ({ origin, version, targets: [[id, rev]] }).
      # A new mark past SHOWN_LIMIT is not recorded. Returns how many marks
      # were recorded.
      def record!(data, request_id, sent: [], erased: [], drawn: [], drawing_erased: [])
        # What the message drew (each { origin, version, digest }), and the
        # drawings it erased (each { origin, version, digests }: those the
        # user saw).
        Array(drawn).each do |draw|
          ops_for!(data, draw[:origin], draw[:version]) << { 'kind' => 'draw', 'request_id' => request_id, 'digest' => draw[:digest] }
        end
        Array(drawing_erased).each do |erase|
          digests = Array(erase[:digests]).grep(String)
          next if digests.empty?

          ops_for!(data, erase[:origin], erase[:version]) << { 'kind' => 'erase_drawing', 'request_id' => request_id,
                                                                'digests' => digests }
        end
        Array(erased).each do |erase|
          ops = ops_for!(data, erase[:origin], erase[:version])
          targets = Array(erase[:targets]).select { |pair| pair.is_a?(Array) && pair.size == 2 }
          ops << { 'kind' => 'erase', 'request_id' => request_id, 'targets' => targets } unless targets.empty?
        end
        Array(sent).sum do |mark|
          ops = ops_for!(data, mark[:origin], mark[:version])
          now = replay(ops)
          had = now[mark['id']]
          kind = if had.nil? then 'add'
                 elsif had['rev'] == mark['rev'] then 'use'
                 else 'change'
                 end
          next 0 if kind == 'add' && now.size >= SHOWN_LIMIT

          ops << mark.slice('id', 'rev', 'shape', 'color', 'page', 'rect').merge('kind' => kind, 'request_id' => request_id)
          trim!(ops)
          1
        end
      end

      # The operations of request_id taken out (its message was deleted):
      # what it added goes, what it erased comes back. On a version where
      # bringing that back would show more than SHOWN_LIMIT, its erasures stay
      # (none of those marks comes back). Returns how many marks stayed erased.
      def undo!(data, request_id)
        (data[KEY] || {}).each_value.sum do |versions|
          versions.each_value.sum do |ops|
            mine = ->(op) { op['request_id'] == request_id }
            if replay(ops.reject(&mine)).size <= SHOWN_LIMIT
              ops.reject!(&mine)
              next 0
            end

            stayed = replay(ops.reject { |op| mine.call(op) && op['kind'] != 'erase' })
            restored = replay(ops.reject(&mine))
            ops.reject! { |op| mine.call(op) && op['kind'] != 'erase' }
            (restored.keys - stayed.keys).size
          end
        end
      end

      # Whether the message request_id recorded anything of the marks.
      def recorded?(data, request_id)
        (data[KEY] || {}).each_value.any? do |versions|
          versions.each_value.any? { |ops| ops.any? { |op| op['request_id'] == request_id } }
        end
      end

      # How many marks on version of origin the message request_id recorded
      # (new), and how many others are shown (earlier).
      def counts(data, origin, version, request_id)
        ops = ops_of(data, origin, version)
        shown = replay(ops)
        fresh = ops.select { |op| op['request_id'] == request_id && %w[add change use].include?(op['kind']) }.map { |op| op['id'] }
        new = shown.keys.count { |id| fresh.include?(id) }
        { 'new' => new, 'earlier' => shown.size - new }
      end

      # The drawings shown on version of origin: the digests of what each
      # message drew, in order, those erased left out.
      def drawn(data, origin, version)
        ops_of(data, origin, version).each_with_object([]) do |op, shown|
          case op['kind']
          when 'draw' then shown << op['digest'] unless shown.include?(op['digest'])
          when 'erase_drawing' then shown.reject! { |digest| op['digests'].include?(digest) }
          end
        end
      end

      # The shown marks the operations give, by id.
      def replay(ops)
        ops.each_with_object({}) do |op, now|
          case op['kind']
          # A use carries the mark as it was sent: it stays when the message
          # that added it is deleted.
          when 'add', 'change', 'use'
            now[op['id']] = op.slice('id', 'rev', 'shape', 'color', 'page', 'rect')
          when 'erase'
            op['targets'].each { |id, rev| now.delete(id) if now[id] && now[id]['rev'] == rev }
          end
        end
      end

      def ops_of(data, origin, version)
        data.dig(KEY, origin.to_s, version.to_s) || []
      end

      def ops_for!(data, origin, version)
        ((data[KEY] ||= {})[origin.to_s] ||= {})[version.to_s] ||= []
      end

      # The oldest operations of marks no longer shown go, past OPS_LIMIT.
      def trim!(ops)
        return if ops.size <= OPS_LIMIT

        live = replay(ops).keys
        # What was drawn and its erasures are kept: only marks' operations go.
        ops.reject!.with_index do |op, i|
          i < ops.size - OPS_LIMIT && MARK_KINDS.include?(op['kind']) && !live.include?(op['id'])
        end
      end
    end
  end
end
