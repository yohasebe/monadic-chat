require 'spec_helper'
require 'open3'

# The vendor files the web UI serves are downloaded, not tracked, so the list
# that names them is the only record of what they are. 1.0.0-beta.37 shipped
# an nginx 404 page as a highlight.js theme (the download saved any response
# and skipped files that existed) and a Bootstrap other than the one listed.
RSpec.describe 'the pinned vendor asset list' do
  let(:root) { File.expand_path('../../../../../..', __dir__) }
  let(:list) { File.join(root, 'docker/services/ruby/bin/assets_list.sh') }

  # Asked from bash, the way the download scripts read the list.
  def bash(script)
    out, err, status = Open3.capture3('bash', '-c', "source \"$1\" && #{script}", '_', list)
    raise err unless status.success?

    out
  end

  let(:assets) { bash('printf "%s\n" "${ASSETS[@]}"').split("\n").map { |l| l.split(',') } }

  it 'pins every file to a versioned URL and a sha256' do
    expect(assets.size).to be > 40
    assets.each do |type, url, filename, sha|
      expect(%w[css js font webfont]).to include(type), filename
      expect(url).to start_with('https://'), filename
      expect(url).not_to include('@latest'), filename
      # A URL that serves whatever is current cannot keep matching a pin.
      expect(url).to match(%r{[@/]v?\d+\.\d+(\.\d+)?/|/v\d+/}), "#{filename}: #{url}"
      expect(sha).to match(/\A\h{64}\z/), filename
    end
    expect(assets.map { |a| a[2] }.uniq.size).to eq(assets.size)
  end

  it 'lists each file vendor_fetch writes, with the generated stylesheet' do
    manifest = bash('vendor_manifest').split("\n").map { |l| l.split("\t") }
    expect(manifest.size).to eq(assets.size + 1)
    expect(manifest.map(&:first)).to include('css/montserrat.css', 'css/katex.min.css', 'fonts/KaTeX_Main-Regular.woff2')
    manifest.each { |_path, sha| expect(sha).to match(/\A\h{64}\z/) }
  end

  it 'refuses an error response or a mismatched file instead of saving it' do
    source = File.read(list)
    expect(source).to include('curl --fail')
    expect(source).to include('Hash mismatch')
  end

  it 'is the only downloader: both fetch scripts go through vendor_fetch' do
    [File.join(root, 'bin/assets.sh'), File.join(root, 'docker/services/ruby/scripts/download_assets.sh')].each do |script|
      body = File.read(script)
      expect(body).to include('vendor_fetch '), script
      expect(body).not_to match(/^\s*curl /), script
    end
  end
end
