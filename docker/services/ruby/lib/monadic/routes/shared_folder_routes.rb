# frozen_string_literal: false

# The shared folder as the page shows it: one folder at a time, read only.
# Sizes of folders are counted in the background; the page asks for them
# again (sizes only, no listing) while counts finish.
get "/api/shared_folder" do
  content_type :json
  listing = Monadic::Workspace::SharedFolder.list(
    params[:path].to_s,
    page: params[:page] || 1,
    live_chat_ids: WebSocketHelper.live_chat_ids,
    sizes: Monadic::Workspace::SharedFolder::Sizes.default
  )
  { success: true }.merge(listing).to_json
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
