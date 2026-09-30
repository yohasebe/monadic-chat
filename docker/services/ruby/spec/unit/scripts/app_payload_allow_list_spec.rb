require 'spec_helper'
require 'fileutils'
require 'digest'
require 'open3'
require 'tmpdir'

# The payload that ships inside the desktop app used to be assembled by copying
# `docker/` and excluding dotfiles — a deny list, which shipped whatever
# happened to be sitting in the working tree. Releases beta.21 through beta.32
# carried benchmark logs, __pycache__ and rspec state that way, each naming
# absolute paths on the build machine.
#
# These examples pin the replacement: a file ships because it is tracked or
# because it was named as a build product, and the packaged archive is checked
# against that list rather than trusted.
RSpec.describe 'the app payload allow list' do
  let(:root) { File.expand_path('../../../../../..', __dir__) }
  let(:stager) { File.join(root, 'scripts/stage_docker_payload.rb') }
  let(:verifier) { File.join(root, 'scripts/verify_bundle_payload.rb') }

  before do
    expect(File.exist?(stager)).to be(true), "stager not found at #{stager}"
    expect(File.exist?(verifier)).to be(true), "verifier not found at #{verifier}"
  end

  describe 'what the staging step decides to ship' do
    let(:source) { File.read(stager) }

    it 'refuses shipped files with uncommitted changes' do
      # A build ships what is committed; the blob IDs it records come from HEAD.
      expect(source).to include('--untracked-files=no')
      expect(source).to include('have uncommitted changes')
      expect(source).to include('ls-tree -r -z HEAD')
      # git status trusts the index; a --skip-worktree edit is only seen by hashing.
      expect(source).to include("'hash-object', '--no-filters', '--stdin-paths'")
    end

    it 'takes tracked files as the base, not the working tree' do
      # Matched in two pieces so the assertion does not itself contain an
      # interpolation sequence, which reads as a mistake in a single-quoted
      # string.
      expect(source).to include('git -C ')
      expect(source).to include('ls-files -z')
    end

    it 'names every untracked file it allows' do
      # The generated files the app cannot run without. Anything else that is
      # untracked has to be added here deliberately, which is the whole point.
      expect(source).to include('*PINNED_VENDOR.keys')
      expect(source).to include('BuildProducts::JS_BUNDLE')
      expect(source).to include('BuildProducts::MAXGRAPH')
      expect(source).to include("'docker/services/ruby/help_data/help_db.json'")
      # A glob over the vendor directory shipped whatever an old fetch left
      # there, including an HTML error page saved as a stylesheet.
      expect(source).not_to include('public/vendor/**')
    end

    it 'stops on a vendor file that differs from its pin' do
      expect(source).to include('differ from assets_list.sh')
      expect(source).to match(/^assert_vendor_is_pinned$/)
    end

    it 'leaves out the files git keeps only to hold a directory' do
      # electron-builder drops .gitkeep by name (app-builder-lib's fileMatcher
      # excludes it alongside .DS_Store and __pycache__), so staging one would
      # guarantee a staged-but-not-shipped mismatch on every build. They carry
      # no meaning in a packaged app either way.
      expect(source).to include('GIT_BOOKKEEPING')
      expect(source).to include("%w[.gitkeep .gitignore .gitattributes]")
    end

    it 'leaves out the trees the shipped app never reads' do
      # The packaged docker/ tree is the build context for the Ruby image and
      # nothing else. That image's .dockerignore already drops spec/ and docs/,
      # so shipping them only enlarges the download — and makes a test edit
      # change the shipped bytes, which forces a rebuild to keep the tag and
      # the artifacts in step.
      expect(source).to include('docker/services/ruby/spec/')
      # Naming the list is not enough — it has to be applied. Dropping the
      # filtering line while leaving the constant behind would otherwise pass.
      expect(source).to match(/\.reject \{ \|p\| EXCLUDED_FROM_PAYLOAD\.any\?/)
    end

    it 'refuses to run when .dockerignore stops agreeing' do
      # Dropping these is only safe while the container build also excludes
      # them. If that changed, the container would need them from the payload
      # and the omission would break the build silently.
      expect(source).to include('def assert_dockerignore_agrees')
      expect(source).to include('no longer excludes')
      # Defining the check and never calling it is the same defect in a
      # different place.
      expect(source).to match(/^assert_dockerignore_agrees$/)
    end

    it 'fails when a named build product is missing' do
      # Shipping without the vendor assets or the help database would produce
      # an app that starts and then cannot render or answer.
      expect(source).to include('required build product missing')
    end
  end

  describe 'what the build actually points at' do
    let(:package_json) { JSON.parse(File.read(File.join(root, 'package.json'))) }
    let(:extra) { package_json.dig('build', 'extraResources') }

    it 'copies from the staged payload' do
      froms = extra.map { |e| e['from'] }
      expect(froms).to include('./build/app-payload/docker', './build/app-payload/bin')
    end

    it 'places the AppStream metainfo where software catalogs look for it' do
      # appimage.github.io and software centres read usr/share/metainfo; the
      # file is named after the component id it declares.
      entries = package_json.dig('build', 'linux', 'extraFiles')
      expect(entries).to be_an(Array)
      metainfo = entries.find { |e| e['to'].to_s.start_with?('usr/share/metainfo/') }
      expect(metainfo).not_to be_nil
      source = File.join(root, metainfo['from'])
      expect(File.file?(source)).to be(true)
      id = File.read(source)[%r{<id>([^<]+)</id>}, 1]
      expect(File.basename(metainfo['to'])).to eq("#{id}.appdata.xml")
      expect(File.basename(metainfo['from'])).to eq("#{id}.appdata.xml")
      # The desktop file it launches is the one electron-builder writes.
      expect(File.read(source)).to include("<launchable type=\"desktop-id\">#{package_json['desktopName']}</launchable>")
    end

    it 'no longer copies the working tree' do
      # This is the defect: `from: ./docker` with a filter that only removed
      # dotfiles.
      froms = extra.map { |e| e['from'] }
      expect(froms).not_to include('./docker')
      expect(froms).not_to include('./bin')
    end
  end

  describe 'the gate that reads what shipped' do
    let(:build_rake) { File.read(File.join(root, 'rakelib/build.rake')) }
    let(:release_rake) { File.read(File.join(root, 'rakelib/release.rake')) }

    it 'stages before packaging' do
      expect(build_rake).to include('sh "ruby scripts/stage_docker_payload.rb"')
    end

    it 'builds the JS bundle before staging it' do
      # electron-builder packs the staged copy. Staging a bundle left on disk
      # by an earlier build shipped stale UI code in 1.0.0-beta.37.
      setup = build_rake[build_rake.index('def setup_build_environment')..]
      bundle_at = setup.index('sh "npm run build:js"')
      stage_at = setup.index('sh "ruby scripts/stage_docker_payload.rb"')
      expect(bundle_at).not_to be_nil
      expect(stage_at).not_to be_nil
      expect(bundle_at).to be < stage_at
    end

    it 'builds maxGraph before staging it' do
      setup = build_rake[build_rake.index('def setup_build_environment')..]
      expect(setup.index('sh "npm run build:maxgraph"')).to be < setup.index('sh "ruby scripts/stage_docker_payload.rb"')
    end

    it 'checks the archives after packaging' do
      expect(build_rake).to include('sh "ruby scripts/verify_bundle_payload.rb"')
    end

    it 'requires the linux.extraFiles in every AppImage, with their committed contents' do
      verifier_source = File.read(verifier)
      expect(verifier_source).to include("build/app-extra")
      expect(verifier_source).to include('is missing')
      expect(verifier_source).to include('differs from the committed')
      # Every extraFiles/extraResources key is read, and an unknown one stops staging.
      expect(File.read(stager)).to include('EXTRA_KEYS = %w[extraFiles extraResources]')
      expect(File.read(stager)).to include('is not checked by verify_bundle_payload.rb')
    end

    it 'compares the configuration electron-builder uses with what staging recorded' do
      # -c.<key>=... and --config reach the packager but not package.json, so
      # before_pack hands the effective configuration to the one place that
      # decides what counts as an extra file.
      before_pack = File.read(File.join(root, 'scripts/before_pack.js'))
      expect(before_pack).to include('context.packager.config')
      expect(before_pack).to include("args.push('--config', file)")
      expect(File.read(stager)).to include("ARGV.index('--config')")
      expect(File.read(stager)).to include('which staging did not record')
    end

    it 'checks again before publishing, and stops on failure' do
      expect(release_rake).to include('system("ruby", "scripts/verify_bundle_payload.rb")')
      expect(release_rake).to include('packaged payload verification failed')
    end
  end

  describe 'the verifier applied to an archive' do
    # Builds a miniature archive shaped like the real one and runs the real
    # verifier over it, so the comparison itself is exercised rather than
    # described.
    NODE_MODULES = File.expand_path('../../../../../../node_modules', __dir__)
    RESOURCES = 'Monadic Chat.app/Contents/Resources'

    # Packs an asar the way electron-builder does, with the same library.
    def pack_asar(files, dest)
      Dir.mktmpdir('asar_src') do |src|
        files.each do |path, body|
          full = File.join(src, path)
          FileUtils.mkdir_p(File.dirname(full))
          File.write(full, body)
        end
        # createPackage collects files through a glob whose installed version
        # it no longer matches, and then packs nothing; pass the list instead.
        script = <<~'JS'
          const asar = require('@electron/asar');
          const fs = require('fs');
          const path = require('path');
          const src = process.argv[1];
          const files = [];
          (function walk(d) {
            for (const n of fs.readdirSync(d)) {
              const p = path.join(d, n);
              files.push(p);
              if (fs.statSync(p).isDirectory()) walk(p);
            }
          })(src);
          asar.createPackageFromFiles(src, process.argv[2], files)
            .catch(e => { console.error(e); process.exit(1); });
        JS
        system({ 'NODE_PATH' => NODE_MODULES }, 'node', '-e', script, src, dest, err: File::NULL) or raise 'asar pack failed'
        raise 'asar pack wrote nothing' unless File.size?(dest)
      end
    end

    DEFAULT_ASAR = {
      'package.json' => '{"name":"app","version":"1.0.0"}',
      'app/main.js' => 'x',
      'node_modules/dotenv/package.json' => '{"name":"dotenv","version":"1.0.0"}'
    }.freeze

    # The committed package.json carries fields electron-builder drops when it
    # packs the app, as the real one does.
    COMMITTED_PACKAGE_JSON = '{"name":"app","version":"1.0.0","scripts":{"test":"jest"}}'

    # asar_files: what the packed app.asar holds; asar_expected / modules: the
    # lists staging records; resources_extra: files placed beside app.asar;
    # committed: contents at HEAD where they differ from what was packed.
    def with_fixture(manifest_paths, archive_paths, asar_files: DEFAULT_ASAR,
                     asar_expected: %w[app/main.js package.json], modules: %w[dotenv@1.0.0],
                     resources_extra: [], asar: true, committed: {}, extra: [], products: nil)
      Dir.mktmpdir('payload_spec') do |dir|
        build = File.join(dir, 'build')
        FileUtils.mkdir_p(build)
        File.write(File.join(build, 'app-payload.manifest'), (manifest_paths + (products || {}).keys).sort.join("\n") + "\n")
        File.write(File.join(build, 'app-payload.symlinks'), '')
        File.write(File.join(build, 'app-asar.manifest'), asar_expected.join("\n") + "\n")
        File.write(File.join(build, 'app-asar.modules'), modules.join("\n") + "\n")
        # extraResources files staging recorded ("kind<TAB>destination<TAB>source").
        File.write(File.join(build, 'app-extra'), extra.map { |e| e.join("\t") }.join("\n") + "\n")

        # The blob list staging records from HEAD, with the objects themselves
        # in a repository so the verifier can read the committed package.json.
        system('git', 'init', '-q', dir) or raise 'git init failed'
        at_head = manifest_paths.to_h { |p| [p, 'x'] }
                                .merge(asar_expected.to_h { |p| [p, asar_files[p]] })
                                .merge('package.json' => COMMITTED_PACKAGE_JSON)
                                .merge(committed)
        blobs = at_head.map do |path, body|
          sha, status = Open3.capture2('git', '-C', dir, 'hash-object', '-w', '--stdin', stdin_data: body.to_s)
          raise 'git hash-object failed' unless status.success?

          "#{sha.strip}\t#{path}"
        end
        File.write(File.join(build, 'app-tracked.blobs'), blobs.sort.join("\n") + "\n")

        commit_products_source(dir, build) if products

        src = File.join(dir, 'src')
        (archive_paths + (products || {}).keys).each do |p|
          full = File.join(src, RESOURCES, 'app', p)
          FileUtils.mkdir_p(File.dirname(full))
          File.write(full, (products || {}).fetch(p, 'x'))
        end
        resources_extra.each do |p|
          full = File.join(src, RESOURCES, p)
          FileUtils.mkdir_p(File.dirname(full))
          File.write(full, 'x')
        end
        FileUtils.mkdir_p(File.join(src, RESOURCES))
        pack_asar(asar_files, File.join(src, RESOURCES, 'app.asar')) if asar

        dist = File.join(dir, 'dist')
        FileUtils.mkdir_p(dist)
        zip = File.join(dist, 'Monadic.Chat-1.0.0-test-arm64.zip')
        system('zip', '-q', '-r', zip, 'Monadic Chat.app', chdir: src) or raise 'zip failed'

        yield dir, dist
      end
    end

    # A commit whose asset list pins one vendor file and whose package.json
    # scripts write fixed bundles, standing in for the real sources: the
    # verifier builds the bundles again from it and compares.
    PINNED_CSS = 'docker/services/ruby/public/vendor/css/a.css'
    JS_BUNDLE = 'docker/services/ruby/public/js/monadic.bundle.min.js'
    MAXGRAPH = 'docker/services/ruby/public/vendor/js/maxgraph.bundle.js'
    GOOD_PRODUCTS = { PINNED_CSS => 'pinned', JS_BUNDLE => 'bundle', MAXGRAPH => 'graph' }.freeze

    def commit_products_source(dir, build)
      sha = Digest::SHA256.hexdigest('pinned')
      files = {
        'docker/services/ruby/bin/assets_list.sh' => "vendor_manifest() { printf 'css/a.css\\t%s\\n' #{sha}; }\n",
        'build.js' => <<~JS,
          const fs = require('fs'), path = require('path');
          const [out, body] = { js: ['#{JS_BUNDLE}', 'bundle'], graph: ['#{MAXGRAPH}', 'graph'] }[process.argv[2]];
          fs.mkdirSync(path.dirname(out), { recursive: true });
          fs.writeFileSync(out, body);
        JS
        'package.json' => '{"scripts":{"build:js":"node build.js js","build:maxgraph":"node build.js graph"}}'
      }
      files.each do |path, body|
        full = File.join(dir, path)
        FileUtils.mkdir_p(File.dirname(full))
        File.write(full, body)
      end
      git = ['git', '-C', dir, '-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', '-c', 'core.hooksPath=/dev/null']
      system(*git, 'add', *files.keys) or raise 'git add failed'
      system(*git, 'commit', '-q', '-m', 'fixture') or raise 'git commit failed'
      head, status = Open3.capture2('git', '-C', dir, 'rev-parse', 'HEAD')
      raise 'git rev-parse failed' unless status.success?

      File.write(File.join(build, 'app-commit'), head)
    end

    # The verifier reads the manifest from its own repo root, so point a copy
    # of the scripts at the fixture instead.
    def run_verifier(dir, dist)
      FileUtils.mkdir_p(File.join(dir, 'scripts'))
      FileUtils.cp(verifier, File.join(dir, 'scripts'))
      # The verifier loads its Linux library checks from beside itself.
      FileUtils.cp(File.join(File.dirname(verifier), 'linux_libraries.rb'), File.join(dir, 'scripts'))
      FileUtils.cp(File.join(File.dirname(verifier), 'build_products.rb'), File.join(dir, 'scripts'))
      Open3.capture3({ 'MONADIC_NODE_MODULES' => NODE_MODULES },
                     'ruby', File.join(dir, 'scripts/verify_bundle_payload.rb'), dist)
    end

    it 'passes when the archive matches the manifest' do
      with_fixture(%w[docker/a.rb bin/b.sh], %w[docker/a.rb bin/b.sh]) do |dir, dist|
        stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).not_to include('FAILED'), stdout
        expect(status.exitstatus).to eq(0)
      end
    end

    it 'reports a file the manifest never named' do
      # The failure this whole change is about.
      with_fixture(%w[docker/a.rb], %w[docker/a.rb docker/tmp/benchmark.log]) do |dir, dist|
        _stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).to include('not in the staged payload')
        expect(stderr).to include('docker/tmp/benchmark.log')
        expect(status.exitstatus).to eq(1)
      end
    end

    it 'reports a staged file that never reached the archive' do
      with_fixture(%w[docker/a.rb docker/b.rb], %w[docker/a.rb]) do |dir, dist|
        _stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).to include('did not reach the archive')
        expect(status.exitstatus).to eq(1)
      end
    end

    it 'reports an untracked file packed into app.asar' do
      files = DEFAULT_ASAR.merge('app/notes.txt' => 'private')
      with_fixture(%w[docker/a.rb], %w[docker/a.rb], asar_files: files) do |dir, dist|
        _stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).to include('untracked file(s): app/notes.txt')
        expect(status.exitstatus).to eq(1)
      end
    end

    it 'reports a package that is not a production dependency' do
      files = DEFAULT_ASAR.merge('node_modules/jest/package.json' => '{"name":"jest","version":"29.0.0"}')
      with_fixture(%w[docker/a.rb], %w[docker/a.rb], asar_files: files) do |dir, dist|
        _stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).to include('outside the production dependencies: jest@29.0.0')
        expect(status.exitstatus).to eq(1)
      end
    end

    it 'reports a file placed beside app.asar' do
      with_fixture(%w[docker/a.rb], %w[docker/a.rb], resources_extra: %w[debug.log]) do |dir, dist|
        _stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).to include('unexpected entries beside app.asar: debug.log')
        expect(status.exitstatus).to eq(1)
      end
    end

    it 'reports a tracked file whose packed bytes differ from the commit' do
      # A path comparison passes an uncommitted edit to a tracked file: the
      # path is right, the contents are not what was reviewed.
      with_fixture(%w[docker/a.rb], %w[docker/a.rb], committed: { 'docker/a.rb' => "x\n# debug\n" }) do |dir, dist|
        _stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).to include('1 tracked file(s) differ from the committed version')
        expect(stderr).to include('~ docker/a.rb')
        expect(status.exitstatus).to eq(1)
      end
    end

    it 'reports the same for a file inside app.asar' do
      with_fixture(%w[docker/a.rb], %w[docker/a.rb], committed: { 'app/main.js' => 'y' }) do |dir, dist|
        _stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).to include('~ app/main.js')
        expect(status.exitstatus).to eq(1)
      end
    end

    it 'reports a packed package.json field the commit does not have' do
      # electron-builder may drop fields, never add or change them.
      files = DEFAULT_ASAR.merge('package.json' => '{"name":"app","version":"1.0.1"}')
      with_fixture(%w[docker/a.rb], %w[docker/a.rb], asar_files: files) do |dir, dist|
        _stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).to include('package.json fields differ from the commit: version')
        expect(status.exitstatus).to eq(1)
      end
    end

    it 'reports a file in resources/app that is neither payload nor a recorded extra' do
      with_fixture(%w[docker/a.rb], %w[docker/a.rb notes.txt]) do |dir, dist|
        _stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).to include('unexpected files in')
        expect(stderr).to include('app/notes.txt')
        expect(status.exitstatus).to eq(1)
      end
    end

    it 'reports a recorded extra resource that did not ship' do
      extra = [%w[resources app/LICENSE LICENSE]]
      with_fixture(%w[docker/a.rb], %w[docker/a.rb], extra: extra, committed: { 'LICENSE' => 'x' }) do |dir, dist|
        _stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).to include('app/LICENSE is missing')
        expect(status.exitstatus).to eq(1)
      end
    end

    it 'fails without the record of extra files' do
      # Treating a missing record as "no extras" would pass a package whose
      # metainfo or licence never shipped.
      with_fixture(%w[docker/a.rb], %w[docker/a.rb]) do |dir, dist|
        File.delete(File.join(dir, 'build', 'app-extra'))
        _stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).to include('no build/app-extra')
        expect(status.exitstatus).not_to eq(0)
      end
    end

    it 'fails when the archive has no app.asar to check' do
      # A missing asar must not read as a clean one.
      with_fixture(%w[docker/a.rb], %w[docker/a.rb], asar: false) do |dir, dist|
        _stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).to include('no app.asar found')
        expect(status.exitstatus).to eq(1)
      end
    end

    it 'passes build products that match their pins and a rebuild of the commit' do
      with_fixture(%w[docker/a.rb], %w[docker/a.rb], products: GOOD_PRODUCTS) do |dir, dist|
        stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).not_to include('FAILED'), stderr
        expect(stdout).to include('3 build products with their pins and rebuilds')
        expect(status.exitstatus).to eq(0)
      end
    end

    it 'reports a bundle that differs from a rebuild of the commit' do
      # 1.0.0-beta.37: the bundle of the commit before its last, packed from
      # the disk. Present and well-formed, so only a rebuild tells it apart.
      with_fixture(%w[docker/a.rb], %w[docker/a.rb], products: GOOD_PRODUCTS.merge(JS_BUNDLE => 'stale')) do |dir, dist|
        _stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).to include("#{JS_BUNDLE} differs from the build of")
        expect(status.exitstatus).to eq(1)
      end
    end

    it 'reports a vendor file that differs from its pin' do
      # 1.0.0-beta.37 also shipped an nginx 404 page as a highlight.js theme.
      with_fixture(%w[docker/a.rb], %w[docker/a.rb], products: GOOD_PRODUCTS.merge(PINNED_CSS => '<html>404</html>')) do |dir, dist|
        _stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).to include("#{PINNED_CSS} differs from the hash pinned in assets_list.sh")
        expect(status.exitstatus).to eq(1)
      end
    end

    it 'reports an untracked file that is neither pinned nor built' do
      extra = GOOD_PRODUCTS.merge('docker/services/ruby/public/vendor/hljs/theme.css' => 'x')
      with_fixture(%w[docker/a.rb], %w[docker/a.rb], products: extra) do |dir, dist|
        _stdout, stderr, status = run_verifier(dir, dist)

        expect(stderr).to include('vendor/hljs/theme.css ships, but')
        expect(status.exitstatus).to eq(1)
      end
    end

    it 'fails when there is no archive to read' do
      # A run that checked nothing must not report success.
      Dir.mktmpdir('payload_spec') do |dir|
        FileUtils.mkdir_p(File.join(dir, 'build'))
        File.write(File.join(dir, 'build/app-payload.manifest'), "docker/a.rb\n")
        empty = File.join(dir, 'dist')
        FileUtils.mkdir_p(empty)

        _stdout, stderr, status = run_verifier(dir, empty)

        expect(stderr).to include('no packaged archive found')
        expect(status.exitstatus).not_to eq(0)
      end
    end
  end
end
