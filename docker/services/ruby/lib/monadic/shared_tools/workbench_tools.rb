# frozen_string_literal: true

require 'json'
require_relative '../workbench/board'
require_relative '../workbench/caller'
require_relative '../workbench/channel'
require_relative '../workbench/look'
require_relative '../workbench/put'
require_relative '../workbench/shown'
require_relative '../workbench/document'
require_relative '../workbench/point'
require_relative '../workbench/draw'

module MonadicSharedTools
  # What every app can do with the work screen (the workbench beside the
  # chat): show a file of the shared folder there. No provider's API is
  # called. The file is not copied: the work screen shows it as it is when
  # shown, and says so when it changes or is gone.
  module WorkbenchTools
    # The prefixes a model may put before a path of the shared folder.
    SHARED_PREFIXES = %r{\A/(?:monadic/)?data/}

    # workbench: who called (Monadic::Workbench::Caller), given by the
    # server, never by the model.
    # path: a file of the shared folder; item: an item already on the work
    # screen (its id from the observation), brought before the user.
    def show_on_workbench(path: nil, item: nil, workbench: nil)
      return WorkbenchTools.show_item(item, workbench) if item && !item.to_s.empty?
      return WorkbenchTools.refusal('give a path or an item') if path.nil? || path.to_s.empty?

      WorkbenchTools.show_file(path, workbench)
    end

    # Brings an item of the work screen (by its id) before the user's tab,
    # as show_on_workbench(item:) does. What is said back, as JSON, or why
    # not.
    def self.show_item(item_id, workbench)
      return refusal('this reply cannot show anything in the work screen') unless workbench

      board = Monadic::Workbench::Board.existing(workbench.chat_id) or return refusal('nothing is on the work screen')
      item = board.bring(item_id: item_id.to_s, origin: workbench.origin, epoch: workbench.epoch)
      Monadic::Workbench::Shown.add(workbench.request_id, item) if item['file']
      Monadic::Workbench::Channel.changed(workbench.chat_id)
      entry = item['file'] || item['artifact'] || {}
      JSON.generate({ 'status' => 'shown_in_work_screen', 'item' => item['id'], 'name' => entry['name'],
                      'note' => 'The item is brought before the user in the work screen (unless they are typing or ' \
                                'turned this off; then they are told it is there).' }.compact)
    rescue Monadic::Workbench::Board::Refused => e
      refusal(e.message)
    end

    # Shows a file of the shared folder in the work screen for the reply of
    # workbench, as show_on_workbench does; other tools call it for what
    # they made (a notebook, a screenshot). What is said back, as JSON, or
    # why not.
    def self.show_file(path, workbench)
      return refusal('this reply cannot show anything in the work screen') unless workbench

      board = Monadic::Workbench::Board.for(workbench.chat_id)
      item, = board.add_file(path: path.to_s.sub(SHARED_PREFIXES, ''), origin: workbench.origin, epoch: workbench.epoch)
      Monadic::Workbench::Shown.add(workbench.request_id, item)
      Monadic::Workbench::Channel.changed(workbench.chat_id)
      JSON.generate({ 'status' => 'shown_in_work_screen', 'path' => item.dig('file', 'path'),
                      'note' => 'The file is shown in the work screen as it is now. It was not copied.' })
    rescue Monadic::Workbench::Board::Refused => e
      refusal(e.message)
    rescue Monadic::Workbench::FileItem::Busy
      refusal('the work screen is reading other files now; try again in a moment')
    end

    def self.refusal(reason)
      "❌ The file was not shown in the work screen: #{reason}."
    end

    # A text the model made, written as a new file of the chat's folder
    # and shown in the work screen (Monadic::Workbench::Put). A file that
    # was written but could not be shown is said so, with its path.
    def put_on_workbench(name:, content:, workbench: nil)
      result = Monadic::Workbench::Put.run(workbench, name: name, content: content)
      Monadic::Workbench::Channel.changed(workbench.chat_id) if result[:shown]
      out = { 'status' => result[:shown] ? 'shown_in_work_screen' : 'written_not_shown', 'path' => result[:path] }
      out['reason'] = result[:reason] unless result[:shown]
      JSON.generate(out)
    rescue Monadic::Workbench::Put::Refused => e
      "❌ Nothing was put on the work screen: #{e.message}."
    end

    # A section of a long text, kept for the reply and shown with the rest
    # of the document in the work screen (Monadic::Workbench::Document).
    def write_section(document:, section:, content:, session: nil, workbench: nil)
      app_name = (session && session.dig(:parameters, 'app_name')) || self.class.name
      result = Monadic::Workbench::Document.write(session: session, workbench: workbench, app_name: app_name,
                                                  document: document, section: section, content: content)
      out = { 'status' => result[:shown] ? 'shown_in_work_screen' : 'written_not_shown',
              'document_path' => result[:path], 'section_path' => result[:section_path] }
      JSON.generate(out)
    rescue Monadic::Workbench::Document::Refused, Monadic::Utils::SharedPathGuard::InvalidPath, SystemCallError => e
      "❌ The section was not written: #{e.message}."
    end

    # Points the user at a part of what their tab shows (Monadic::Workbench::
    # Point): what was pointed at, as JSON, or why not.
    def point_at_workbench(quote: nil, first_line: nil, last_line: nil, page: nil, label: nil, workbench: nil)
      WorkbenchTools.point(workbench, quote: quote, first_line: first_line, last_line: last_line, page: page, label: label)
    end

    def self.point(workbench, quote:, first_line:, last_line:, page:, label:)
      number = ->(v) { v.is_a?(String) && v.match?(/\A\d+\z/) ? v.to_i : v }
      quote = nil if quote.is_a?(String) && quote.strip.empty?
      done = Monadic::Workbench::Point.run(workbench, quote: quote, first_line: number.call(first_line),
                                                      last_line: number.call(last_line), page: number.call(page), label: label)
      point = done[:point]
      out = { 'status' => 'pointed', 'name' => done[:item].dig('file', 'name') }
      out['lines'] = { 'first' => point['lines'][0], 'last' => point['lines'][1] } if point['lines']
      out['page'] = point['page'] if point['page']
      JSON.generate(out)
    rescue Monadic::Workbench::Point::Refused => e
      "❌ Nothing was pointed at: #{e.message}."
    end

    def draw_on_whiteboard(shapes: nil, remove: nil, new_whiteboard: false, layout: nil, workbench: nil)
      WorkbenchTools.draw(workbench, shapes: shapes, remove: remove, new_whiteboard: new_whiteboard, layout: layout)
    end

    def self.draw(workbench, shapes:, remove:, new_whiteboard:, layout: nil)
      done = Monadic::Workbench::Draw.run(workbench, shapes: shapes, remove: remove,
                                                     new_board: [true, 'true'].include?(new_whiteboard), layout: layout)
      out = { 'status' => 'drawn', 'name' => done[:item].dig('file', 'name') }
      %i[added changed removed adjusted issues].each { |key| out[key.to_s] = done[key] unless done[key].empty? }
      JSON.generate(out)
    rescue Monadic::Workbench::Draw::Refused => e
      "❌ Nothing was drawn: #{e.message}."
    end

    # What the asking tab has selected in the work screen, read now
    # (Monadic::Workbench::Look): a Look::Result whose image, if any, the
    # provider's helper places after the result, or a refusal.
    def look_at_workbench(scope: 'visible', item: nil, workbench: nil)
      Monadic::Workbench::Look.run(workbench, scope: scope, item: item)
    end
  end
end
