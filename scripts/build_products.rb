# frozen_string_literal: true

# The files that ship in the app without being tracked (other than the help
# database, which HelpDumpGuard checks), and the bytes each one must have.
#
# The expected bytes come from the sources, never from the file on disk:
# vendor files from the hashes pinned in assets_list.sh, and the two bundles
# from building them again from the commit. A file that was merely present
# used to be enough. 1.0.0-beta.37 shipped the JS bundle of the commit before
# its last, and an HTML error page saved as a highlight.js theme.

require 'digest'
require 'open3'
require 'tmpdir'

module BuildProducts
  RUBY = 'docker/services/ruby'
  VENDOR = "#{RUBY}/public/vendor"
  ASSETS_LIST = "#{RUBY}/bin/assets_list.sh"
  JS_BUNDLE = "#{RUBY}/public/js/monadic.bundle.min.js"
  MAXGRAPH = "#{VENDOR}/js/maxgraph.bundle.js"
  # katex.min.css loads its fonts from fonts/ beside it.
  FONT_LINK = "#{VENDOR}/css/fonts"
  FONT_LINK_TARGET = '../fonts'
  # The package.json script that builds each bundle.
  BUILT = { JS_BUNDLE => 'build:js', MAXGRAPH => 'build:maxgraph' }.freeze

  module_function

  # {repo path => sha256} for every file vendor_fetch writes, asked from
  # assets_list.sh itself, the way the download scripts read it.
  def pinned_vendor(root)
    out, err, status = Open3.capture3('bash', '-c', 'source "$1" && vendor_manifest', '_',
                                      File.join(root, ASSETS_LIST))
    raise "assets_list.sh: #{err.strip}" unless status.success?

    pins = out.split("\n").to_h do |line|
      rel, sha = line.split("\t", 2)
      raise "assets_list.sh: malformed entry #{line.inspect}" unless rel && sha&.match?(/\A\h{64}\z/)

      ["#{VENDOR}/#{rel}", sha]
    end
    raise 'assets_list.sh pins no files' if pins.empty?

    pins
  end

  # {repo path => sha256} for every product at commit: the vendor pins as the
  # commit has them, and the bundles built in a clean checkout of it.
  def expected(root, commit)
    Dir.mktmpdir('build_products') do |tmp|
      tree = File.join(tmp, 'tree')
      run(root, 'git', 'worktree', 'add', '--detach', '--quiet', tree, commit)
      begin
        modules = File.join(root, 'node_modules')
        File.symlink(modules, File.join(tree, 'node_modules')) if File.directory?(modules)
        built = BUILT.to_h do |path, script|
          run(tree, 'npm', 'run', '--silent', script)
          out = File.join(tree, path)
          raise "npm run #{script} did not write #{path}" unless File.file?(out)

          [path, Digest::SHA256.file(out).hexdigest]
        end
        pinned_vendor(tree).merge(built)
      ensure
        system('git', '-C', root.to_s, 'worktree', 'remove', '--force', tree, out: File::NULL, err: File::NULL)
      end
    end
  end

  def run(dir, *cmd)
    out, status = Open3.capture2e(*cmd, chdir: dir.to_s)
    raise "#{cmd.join(' ')} failed:\n#{out}" unless status.success?

    out
  end
end
