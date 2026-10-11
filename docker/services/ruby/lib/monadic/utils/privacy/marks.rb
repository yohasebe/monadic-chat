# frozen_string_literal: true

module Monadic
  module Utils
    module Privacy
      # Strings the user marks in what they write, for the Privacy Filter to
      # mask: ⟦江戸川今太郎⟧, or with a type, ⟦Acme社|組織⟧. The marks are
      # taken out of the text (the chat keeps the text as written, without
      # them) and the strings are kept for the chat, masked wherever they
      # occur from then on.
      #
      # A ⟦ or ⟧ meant as itself is written \⟦ or \⟧. A mark that is not
      # closed, is nested, is empty, spans a line or names an unknown type is
      # refused, never sent as it is. Errors do not repeat the marked text.
      module Marks
        OPEN = "⟦"  # ⟦
        CLOSE = "⟧" # ⟧
        ESCAPE = '\\'
        MAX_LENGTH = 200

        class Invalid < StandardError; end

        # Words for a type, in the languages of the page, and the type the
        # Privacy container masks the string as.
        TYPE_ALIASES = {
          'PERSON' => %w[person name people 人 人名 名前 氏名 personne nom persona nombre 사람 이름 人物],
          'ORGANIZATION' => %w[organization organisation org company 組織 会社 団体 企業 organización empresa entreprise
                               organisation unternehmen firma 조직 회사 机构 公司],
          'LOCATION' => %w[location place 場所 地名 住所 lugar lieu ort 장소 地点],
          'EMAIL_ADDRESS' => %w[email mail メール メールアドレス correo courriel 이메일 邮箱],
          'PHONE_NUMBER' => %w[phone tel 電話 電話番号 teléfono téléphone telefon 전화 电话],
          'URL' => %w[url link リンク enlace lien 링크 链接],
          'DATE_TIME' => %w[date 日付 日時 fecha 날짜 日期 datum]
        }.freeze

        ALIAS_TO_TYPE = TYPE_ALIASES.each_with_object({}) do |(type, words), map|
          map[type.downcase] = type
          words.each { |w| map[w.downcase] = type }
        end.freeze

        module_function

        def any?(text)
          text.is_a?(String) && (text.include?(OPEN) || text.include?(CLOSE))
        end

        # [text without the marks, [{ text:, type: }, ...]]
        def extract(text)
          return [text, []] unless any?(text)

          out = +''
          terms = []
          current = nil
          chars = text.each_char.to_a
          i = 0
          while i < chars.size
            char = chars[i]
            if char == ESCAPE && [OPEN, CLOSE].include?(chars[i + 1])
              (current || out) << chars[i + 1]
              i += 2
              next
            end

            case char
            when OPEN
              raise Invalid, 'a mark is opened inside another mark' if current

              current = +''
            when CLOSE
              raise Invalid, 'a mark is closed that was not opened' unless current

              term = term_of(current)
              terms << term
              out << term[:text]
              current = nil
            else
              raise Invalid, 'a mark spans more than one line' if current && ["\n", "\r"].include?(char)

              (current || out) << char
            end
            i += 1
          end
          raise Invalid, 'a mark is not closed' if current

          # A word marked twice keeps the type it was marked with last.
          [out, terms.reverse.uniq { |t| t[:text] }.reverse]
        end

        # "text" or "text|type" (the last | separates the type).
        def term_of(content)
          text = content
          type = 'PERSON'
          if content.include?('|')
            text, _, word = content.rpartition('|')
            type = ALIAS_TO_TYPE[word.strip.downcase]
            raise Invalid, 'a mark names a type that is not known' unless type
          end
          text = text.strip
          raise Invalid, 'a mark is empty' if text.empty?
          raise Invalid, "a mark is longer than #{MAX_LENGTH} characters" if text.length > MAX_LENGTH

          { text: text, type: type }
        end
      end
    end
  end
end
