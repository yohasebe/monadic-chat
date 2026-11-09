# frozen_string_literal: true

module Monadic
  module Utils
    module Privacy
      # The words a chat hides from what it sends: the ones the user
      # confirmed (by marking them, or by taking a candidate the Privacy
      # container found). Each word has one placeholder, <<TYPE_N>>, for the
      # whole chat:
      #
      # - the mapping from placeholders to words only grows: a placeholder
      #   once given is kept, so what was sent with it can be read back;
      # - the active words are the ones hidden from now on; a word taken off
      #   is no longer hidden, and its placeholder still reads back;
      # - numbers come from the highest given per type, never again for
      #   another word, however the active words change;
      # - the revision grows with every change, so that what was prepared
      #   under one set of words can be told from what is current.
      #
      # A word is found as written (case and form as they are; no
      # normalization). A word inside a longer one is left to the longer;
      # two words that overlap in part are not hidden at all (Overlap), so
      # that the user can say which is meant. Text that already holds
      # something of the form <<TYPE_N>> keeps it as text: it is sent as
      # ‹‹TYPE_N›› and never read back as one of the chat's words.
      #
      # Text that looked like a placeholder is not given back as it was: the
      # model sees ‹‹TYPE_N››, and so does a reply that repeats it (the
      # history keeps what the user wrote).
      #
      # What it keeps is its own: words and types are copied in, and what it
      # gives out (ids, lists, to_h) is frozen or a copy, so nothing outside
      # changes the table.
      #
      # Nothing here talks to the container or the network.
      class WordTable
        SCHEMA = 1
        MAX_WORDS = 200
        MAX_WORD_CHARS = 200
        MAX_PLACEHOLDERS = 2000
        MAX_TYPES = 100
        MAX_NUMBER = 999_999
        TYPE_RE = /\A[A-Z][A-Z_]{0,39}\z/
        # The form a placeholder is given in: a type, and a number from 1 to
        # MAX_NUMBER without leading zeros.
        ID_RE = /\A([A-Z][A-Z_]{0,39})_([1-9]\d{0,5})\z/
        # What is read back from a model as a placeholder: the clean form,
        # and spaces or "?" a model put inside the brackets.
        RESTORE_RE = /<<[\s?]*([A-Z_]+)_(\d+)[\s?]*>>/
        LITERAL_OPEN = "‹‹"
        LITERAL_CLOSE = "››"

        class Invalid < StandardError; end

        # Words that overlap in part in a text (pairs of the words).
        class Overlap < StandardError
          attr_reader :pairs

          def initialize(pairs)
            @pairs = pairs
            super('words overlap in part; mark the whole of what is meant as one word')
          end
        end

        attr_reader :revision

        def initialize
          @mapping = {}    # "PERSON_1" => { word:, type: }
          @active = {}     # word => { id:, type: }
          @high = Hash.new(0)
          @revision = 0
          @lock = Mutex.new
        end

        # The word's placeholder id, hidden from now on; type is how it is
        # shown. A word confirmed before keeps its placeholder (another type
        # only changes how it is shown).
        def confirm!(word, type)
          word = own(checked_word(word))
          type = own(checked_type(type))
          @lock.synchronize do
            current = @active[word]
            if current
              next current[:id] if current[:type] == type

              @active[word] = current.merge(type: type)
              @revision += 1
              next current[:id]
            end
            raise Invalid, "at most #{MAX_WORDS} words" if @active.size >= MAX_WORDS

            id = id_for_word(word) || new_id(word, type)
            @active[word] = { id: id, type: type }
            @revision += 1
            id
          end
        end

        # The word is no longer hidden. Its placeholder still reads back.
        def disable!(word)
          @lock.synchronize do
            next false unless @active.delete(word)

            @revision += 1
            true
          end
        end

        def active_words
          @lock.synchronize { @active.map { |word, entry| { word: word, id: entry[:id], type: entry[:type] }.freeze }.freeze }
        end

        # The text as sent: each active word replaced by its placeholder, and
        # anything that looks like a placeholder kept as text. Overlap when
        # two active words overlap in part.
        def apply(text)
          active = @lock.synchronize { @active.transform_values { |e| e[:id] } }
          literal = escape_literals(text.to_s)
          spans = chosen_spans(literal, active)
          out = +''
          at = 0
          spans.each do |first, last, word|
            out << literal[at...first] << "<<#{active[word]}>>"
            at = last
          end
          out << literal[at..]
        end

        # The text with each placeholder of this chat put back as its word,
        # once (a word is not looked into again). A placeholder this chat did
        # not give stays as it is.
        def restore(text)
          mapping = @lock.synchronize { @mapping.dup }
          text.to_s.gsub(RESTORE_RE) do
            entry = mapping["#{Regexp.last_match(1)}_#{Regexp.last_match(2)}"]
            entry ? entry[:word] : Regexp.last_match(0)
          end
        end

        def to_h
          @lock.synchronize do
            {
              'schema' => SCHEMA,
              'mapping' => @mapping.to_h { |id, e| [id.dup, { 'word' => e[:word].dup, 'type' => e[:type].dup }] },
              'active' => @active.map { |word, e| { 'word' => word.dup, 'id' => e[:id].dup, 'type' => e[:type].dup } },
              'high' => @high.to_h { |type, n| [type.dup, n] },
              'revision' => @revision
            }
          end
        end

        # A table from what to_h gave (from the history or an imported file),
        # checked: its form, sizes, that every active word has its own
        # placeholder of the mapping, and numbers no lower than those given.
        def self.from_h(data)
          raise Invalid, 'not a word table' unless data.is_a?(Hash) && data['schema'] == SCHEMA

          table = new
          table.send(:load!, data)
          table
        end

        private

        def load!(data)
          mapping = data['mapping']
          active = data['active']
          high = data['high']
          revision = data['revision']
          unless mapping.is_a?(Hash) && active.is_a?(Array) && high.is_a?(Hash) && revision.is_a?(Integer) && revision >= 0
            raise Invalid, 'not a word table'
          end
          raise Invalid, 'too many placeholders' if mapping.size > MAX_PLACEHOLDERS
          raise Invalid, 'too many words' if active.size > MAX_WORDS
          raise Invalid, 'too many types' if high.size > MAX_TYPES

          mapping.each do |id, entry|
            match = ID_RE.match(id.to_s) or raise Invalid, 'a placeholder of another form'
            raise Invalid, 'a placeholder without its word' unless entry.is_a?(Hash)

            word = own(checked_word(entry['word']))
            type = own(checked_type(entry['type']))
            raise Invalid, 'a placeholder of another type' unless match[1] == type

            @mapping[own(id.to_s)] = { word: word, type: type }
          end
          words = @mapping.values.map { |e| e[:word] }
          raise Invalid, 'a word with two placeholders' unless words.uniq.size == words.size

          high.each do |type, n|
            raise Invalid, 'a number of another form' unless n.is_a?(Integer) && n.between?(0, MAX_NUMBER)

            @high[own(checked_type(type))] = n
          end
          @mapping.each_key do |id|
            match = ID_RE.match(id)
            raise Invalid, 'a placeholder above the numbers given' if match[2].to_i > @high[match[1]]
          end
          active.each do |entry|
            raise Invalid, 'an active word of another form' unless entry.is_a?(Hash)

            word = own(checked_word(entry['word']))
            id = entry['id']
            raise Invalid, 'an active word without its placeholder' unless id.is_a?(String) && @mapping.dig(id, :word) == word
            raise Invalid, 'a word active twice' if @active.key?(word)

            @active[word] = { id: @mapping.keys.find { |k| k == id }, type: own(checked_type(entry['type'])) }
          end
          ids = @active.values.map { |e| e[:id] }
          raise Invalid, 'a placeholder for two active words' unless ids.uniq.size == ids.size

          @revision = revision
        end

        def checked_word(word)
          unless word.is_a?(String) && word.valid_encoding? && !word.strip.empty? && word.length <= MAX_WORD_CHARS
            raise Invalid, 'a word must be text of at most 200 characters'
          end
          raise Invalid, 'a word must be on one line' if word.match?(/[\r\n]/)
          raise Invalid, 'a word must not hold << or >>' if word.include?('<<') || word.include?('>>')

          word
        end

        def checked_type(type)
          raise Invalid, 'a type must be upper case letters' unless type.is_a?(String) && TYPE_RE.match?(type)

          type
        end

        # The placeholder this word had (taken off, then confirmed again).
        def id_for_word(word)
          @mapping.find { |_, entry| entry[:word] == word }&.first
        end

        def new_id(word, type)
          raise Invalid, 'too many placeholders' if @mapping.size >= MAX_PLACEHOLDERS
          raise Invalid, "no number left for #{type}" if @high[type] >= MAX_NUMBER
          raise Invalid, 'too many types' if !@high.key?(type) && @high.size >= MAX_TYPES

          @high[type] += 1
          id = own("#{type}_#{@high[type]}")
          @mapping[id] = { word: word, type: type }
          id
        end

        # A frozen copy of a string, the table's own.
        def own(text)
          text.dup.freeze
        end

        def escape_literals(text)
          text.gsub(RESTORE_RE) { "#{LITERAL_OPEN}#{Regexp.last_match(0)[2...-2]}#{LITERAL_CLOSE}" }
        end

        # Where each active word is replaced: [first, last, word], in order.
        # A span inside another is left to the other; spans that overlap in
        # part are Overlap.
        def chosen_spans(text, active)
          spans = []
          active.each_key do |word|
            from = 0
            while (i = text.index(word, from))
              spans << [i, i + word.length, word]
              from = i + 1
            end
          end
          spans.sort_by! { |first, last, _| [first, -last] }
          chosen = []
          overlaps = []
          spans.each do |span|
            held = chosen.last
            if held && span[0] < held[1]
              # Inside the span before it, or the same word again (read left
              # to right, as a replacement does).
              next if span[1] <= held[1] || span[2] == held[2]

              overlaps << [held[2], span[2]]
              next
            end
            chosen << span
          end
          raise Overlap, overlaps.uniq unless overlaps.empty?

          chosen
        end
      end
    end
  end
end
