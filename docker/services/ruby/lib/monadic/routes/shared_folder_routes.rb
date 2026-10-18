# frozen_string_literal: false

# The shared folder as the page shows it: one folder at a time, read only.
# Sizes of folders are counted in the background; the page asks for them
# again (sizes only, no listing) while counts finish.
get "/api/shared_folder" do
  content_type :json
  listing = Monadic::Workspace::SharedFolder.list(
    params[:path].to_s,
    page: params[:page] || 1,
    per_page: params[:per_page] || Monadic::Workspace::SharedFolder::PER_PAGE,
    live_chat_ids: WebSocketHelper.live_chat_ids,
    sizes: Monadic::Workspace::SharedFolder::Sizes.default,
    query: params[:q],
    classes: params[:classes],
    sort: params[:sort] || 'name',
    descending: params[:desc] == 'true',
    older_than_days: params[:older_than_days]
  )
  { success: true }.merge(listing).to_json
rescue Monadic::Workspace::SharedFolder::Invalid => e
  status 400
  error_json(e.message)
rescue SystemCallError => e
  status 500
  error_json("The shared folder could not be read (#{e.class.name.split('::').last})")
end

# One entry and whether it may be moved to the trash, asked by the desktop
# app just before it moves it (the page's own answer is not taken).
get "/api/shared_folder/entry" do
  content_type :json
  item = Monadic::Workspace::SharedFolder.entry(params[:path].to_s, live_chat_ids: WebSocketHelper.live_chat_ids)
  { success: true, item: item }.to_json
rescue Monadic::Workspace::SharedFolder::Invalid => e
  status 400
  error_json(e.message)
rescue SystemCallError => e
  status 500
  error_json("The shared folder could not be read (#{e.class.name.split('::').last})")
end

# Every entry that matches the search and filters and may be moved to the
# trash, for choosing all of them across pages (sent to the desktop app,
# which asks again for each one before it moves it).
get "/api/shared_folder/matching" do
  content_type :json
  found = Monadic::Workspace::SharedFolder.matching(
    params[:path].to_s,
    live_chat_ids: WebSocketHelper.live_chat_ids,
    sizes: Monadic::Workspace::SharedFolder::Sizes.default,
    query: params[:q],
    classes: params[:classes],
    older_than_days: params[:older_than_days]
  )
  { success: true }.merge(found).to_json
rescue Monadic::Workspace::SharedFolder::Invalid => e
  status 400
  error_json(e.message)
rescue SystemCallError => e
  status 500
  error_json("The shared folder could not be read (#{e.class.name.split('::').last})")
end

get "/api/shared_folder/sizes" do
  content_type :json
  paths = params[:paths]
  paths = [paths] unless paths.is_a?(Array)
  sizes = Monadic::Workspace::SharedFolder.sizes_of(paths.compact.map(&:to_s),
                                                   sizes: Monadic::Workspace::SharedFolder::Sizes.default)
  { success: true, sizes: sizes }.to_json
rescue SystemCallError => e
  status 500
  error_json("The shared folder could not be read (#{e.class.name.split('::').last})")
end

# Previews: a text file's beginning, or a media file's bytes. Only the app's
# own page may ask (Sec-Fetch-Site same-origin, which Electron and current
# browsers send); a request without it, or from another site, is refused
# before anything is looked up. Nothing is cached, and no other site may
# embed what is sent.
helpers do
  def shared_preview_guard!
    headers 'Cross-Origin-Resource-Policy' => 'same-origin', 'Cache-Control' => 'no-store',
            'X-Content-Type-Options' => 'nosniff'
    return if request.env['HTTP_SEC_FETCH_SITE'] == 'same-origin'

    halt 403, { 'Content-Type' => 'application/json' }, error_json('Previews are shown in the app only')
  end

  def shared_preview_failure(error)
    case error
    when Monadic::Workspace::SharedFolderPreview::NotText then status 415
    when Monadic::Workspace::SharedFolderPreview::Unavailable then status 501
    when Monadic::Workspace::SharedFolderPreview::Invalid then status 404
    else status 500
    end
    content_type :json
    message = error.is_a?(SystemCallError) ? "The file could not be read (#{error.class.name.split('::').last})" : error.message
    error_json(message)
  end
end

get "/api/shared_folder/text" do
  shared_preview_guard!
  content_type :json
  { success: true }.merge(Monadic::Workspace::SharedFolderPreview.read_text(params[:path].to_s)).to_json
rescue Monadic::Workspace::SharedFolderPreview::Invalid, Monadic::Workspace::SharedFolderPreview::NotText,
       Monadic::Workspace::SharedFolderPreview::Unavailable, SystemCallError => e
  shared_preview_failure(e)
end

# Images, audio, video and PDFs, from the file opened and checked (the path
# is not opened again), with one byte range when asked. HTML, SVG and XML
# are not sent here: they are shown as text.
get "/api/shared_folder/file" do
  shared_preview_guard!
  preview = Monadic::Workspace::SharedFolderPreview
  io, stat, kind = preview.open_file(params[:path].to_s, kinds: %w[image audio video pdf])
  begin
    size = stat.size
    range = preview.range_for(request.env['HTTP_RANGE'], size)
    # A PDF opens in the browser's viewer, which a sandbox would stop; it
    # can be framed by the app's own page only. Other media run nothing.
    headers 'Content-Type' => preview.mime_for(params[:path].to_s), 'Content-Disposition' => 'inline',
            'Accept-Ranges' => 'bytes', 'X-Frame-Options' => 'SAMEORIGIN',
            'Content-Security-Policy' => kind == 'pdf' ? "frame-ancestors 'self'" : "sandbox; default-src 'none'; frame-ancestors 'self'"
    if range == :unsatisfiable
      io.close
      headers 'Content-Range' => "bytes */#{size}"
      halt 416
    end
    first, last = range || [0, size - 1]
    length = size.zero? ? 0 : last - first + 1
    if range
      status 206
      headers 'Content-Range' => "bytes #{first}-#{last}/#{size}"
    end
    # After body: Sinatra drops a Content-Length set before it.
    body preview::FileBody.new(io, first, length)
    headers 'Content-Length' => length.to_s
    nil # the body is set; a value returned here would replace it
  rescue StandardError
    io.close unless io.closed?
    raise
  end
rescue Monadic::Workspace::SharedFolderPreview::Invalid, Monadic::Workspace::SharedFolderPreview::Unavailable,
       SystemCallError => e
  shared_preview_failure(e)
end
