# frozen_string_literal: true

require 'json'
require 'open3'

# Refuses to let a release proceed unless the commit being released passed CI.
#
# v1.0.0-beta.35 was published with Lint red on both dev and main, and nobody
# noticed for two days: the release procedure gates the artifacts (manifest
# hashes, notarization, zip symlinks, PE signature) but never looks at the
# workflow results for the commit those artifacts were built from.
#
# What this does NOT cover, so that a green result is not read as more than it
# is:
#
#   * The help database. `rake build` regenerates help_db.json, which is
#     gitignored and therefore never part of the tree CI ran against. It is
#     gated separately by help_dump_guard at staging and packaging time.
#   * The `main` release commit. Its tree matches dev's, but specs.yml picks
#     the service image tag from the branch name (:dev vs :latest), so dev's
#     green says nothing about how the same source behaves against the
#     released images.
#   * Service image publication. specs.yml waits for publish-images to stop
#     running but never requires it to have succeeded, so a green Specs run
#     does not mean the images were published.
#   * Anything CI skips: env-dependent specs without API keys, and steps
#     marked continue-on-error.
module VerifyCIGreen
  # Matched by workflow file path, not by display name: a workflow can be
  # renamed without changing what it checks, and two workflows can end up
  # sharing a display name.
  REQUIRED = {
    '.github/workflows/lint.yml' => ['anti-patterns', 'eslint'].freeze,
    '.github/workflows/specs.yml' => [
      'rspec unit',
      'jest',
      'rspec integration (IN_CONTAINER=true)',
      'rspec integration (IN_CONTAINER=false)'
    ].freeze
  }.freeze

  REPO = 'yohasebe/monadic-chat'

  class ApiError < StandardError; end

  module_function

  # Returns an array of problem strings; empty means the commit may be released.
  # `fetch` takes an API path and returns parsed JSON, so the checks can be
  # exercised without reaching GitHub. Anything worth saying that is NOT a
  # reason to refuse goes to `notes`, which the caller prints: folding the two
  # together would have made a commit with two green runs unreleasable.
  def problems(sha:, branch: 'dev', repo: REPO, fetch: method(:gh_api), notes: [])
    return ['a full 40-character commit SHA is required'] unless sha.to_s.match?(/\A[0-9a-f]{40}\z/)

    REQUIRED.flat_map do |workflow, jobs|
      workflow_problems(workflow, jobs, sha: sha, branch: branch, repo: repo, fetch: fetch, notes: notes)
    end
  end

  def workflow_problems(workflow, required_jobs, sha:, branch:, repo:, fetch:, notes:)
    name = File.basename(workflow)
    runs = begin
      matching_runs(
        fetch_all("repos/#{repo}/actions/workflows/#{name}/runs?head_sha=#{sha}", 'workflow_runs', fetch: fetch),
        workflow: workflow, branch: branch
      )
    rescue ApiError => e
      # An API failure is not an absent run and is not a green one.
      return ["#{name}: cannot read the workflow runs (#{e.message})"]
    end

    # No run is not the same as no failure. A workflow that never started --
    # disabled, trigger changed, commit never pushed -- must not read as green.
    if runs.empty?
      return ["#{name}: no push run for #{sha[0, 8]} on #{branch}; " \
              'the commit may not be pushed, or the workflow did not start']
    end

    run = runs.max_by { |r| r['id'] }
    notes << "#{name}: #{runs.size} runs for this commit; evaluating the newest (#{run['id']})" if runs.size > 1
    notes << "#{name}: run #{run['id']} -- #{run['html_url']}"

    unless run['status'] == 'completed'
      return ["#{name}: run #{run['id']} is #{run['status']}, not finished -- #{run['html_url']}"]
    end
    unless run['conclusion'] == 'success'
      return ["#{name}: run #{run['id']} concluded #{run['conclusion'].inspect} -- #{run['html_url']}"]
    end

    job_problems(run, required_jobs, repo: repo, fetch: fetch)
  end

  # `per_page=100` is a page size, not "everything". A run with more entries
  # than that -- four jobs re-run twenty-six times is enough -- would be read
  # from its first page only, so the newest attempt of a job could sit on page
  # two and never be seen. Collect until the reported total is in hand, and
  # treat a collection that stops growing as unreadable rather than complete.
  MAX_PAGES = 20

  def fetch_all(path, key, fetch:, per_page: 100)
    items = []
    total = nil
    1.upto(MAX_PAGES) do |page|
      payload = fetch.call("#{path}#{path.include?('?') ? '&' : '?'}per_page=#{per_page}&page=#{page}")
      raise ApiError, "unreadable #{key} response" unless payload.is_a?(Hash)

      batch = payload[key]
      raise ApiError, "no #{key} in the response" unless batch.is_a?(Array)

      total ||= payload['total_count']
      # Without a total there is no way to tell a complete listing from a
      # truncated one, and a truncated listing must not read as complete.
      raise ApiError, "no total_count in the #{key} response" unless total.is_a?(Integer)

      items.concat(batch)
      return { key => items, 'total_count' => total } if items.size >= total
      raise ApiError, "#{key} listing stopped short of #{total}" if batch.empty?
    end
    raise ApiError, "#{key} listing did not finish within #{MAX_PAGES} pages"
  end

  def matching_runs(payload, workflow:, branch:)
    runs = payload['workflow_runs']
    raise ApiError, 'no workflow_runs in the response' unless runs.is_a?(Array)

    # head_sha alone would also match a pull_request run, or the same commit
    # pushed to another branch, which tested something else.
    runs.select do |run|
      run.is_a?(Hash) && run['path'] == workflow &&
        run['event'] == 'push' && run['head_branch'] == branch
    end
  end

  # A green workflow is not the same as every job having run: a job skipped by
  # a condition does not make the run red, and neither does a job that was
  # removed from the workflow.
  def job_problems(run, required_jobs, repo:, fetch:)
    jobs = begin
      latest_attempt_per_job(
        fetch_all("repos/#{repo}/actions/runs/#{run['id']}/jobs?filter=all", 'jobs', fetch: fetch)
      )
    rescue ApiError => e
      return ["#{run['name']}: cannot read the jobs of run #{run['id']} (#{e.message})"]
    end

    required_jobs.filter_map do |wanted|
      job = jobs[wanted]
      next "#{run['name']}: job #{wanted.inspect} did not run in #{run['id']} -- #{run['html_url']}" if job.nil?
      next if job['status'] == 'completed' && job['conclusion'] == 'success'

      "#{run['name']}: job #{wanted.inspect} is #{job['status']}/#{job['conclusion'].inspect} -- #{job['html_url']}"
    end
  end

  # `filter=latest` drops the jobs a partial re-run did not repeat, which would
  # read as "job did not run". Asking for every attempt and keeping the highest
  # one per name is correct whether the re-run was partial or complete.
  def latest_attempt_per_job(payload)
    jobs = payload['jobs']
    raise ApiError, 'no jobs in the response' unless jobs.is_a?(Array)

    jobs.each_with_object({}) do |job, acc|
      next unless job.is_a?(Hash) && job['name']

      current = acc[job['name']]
      acc[job['name']] = job if current.nil? || job['run_attempt'].to_i >= current['run_attempt'].to_i
    end
  end

  def gh_api(path)
    out, err, status = Open3.capture3('gh', 'api', path)
    raise ApiError, err.lines.last.to_s.strip unless status.success?

    JSON.parse(out)
  rescue JSON::ParserError => e
    raise ApiError, "unreadable response: #{e.message}"
  rescue SystemCallError => e
    raise ApiError, e.message
  end
end

if __FILE__ == $PROGRAM_NAME
  sha = ARGV[0]
  branch = ARGV[1] || 'dev'
  if sha.nil? || sha.empty?
    abort "usage: verify_ci_green.rb <full-commit-sha> [branch]\n" \
          "  e.g. ruby scripts/verify_ci_green.rb \"$(git rev-parse origin/dev)\""
  end

  notes = []
  found = VerifyCIGreen.problems(sha: sha, branch: branch, notes: notes)
  # Printed on success too: what was accepted is the evidence a release rests
  # on, and "which run did it look at" is the first question afterwards.
  notes.each { |note| puts "[verify_ci_green] #{note}" }
  $stdout.flush # so the evidence is not buffered past the abort below
  if found.empty?
    puts "[verify_ci_green] OK — #{sha[0, 8]} on #{branch} passed #{VerifyCIGreen::REQUIRED.size} required workflow(s)."
  else
    abort "[verify_ci_green] refusing to release #{sha[0, 8]}:\n  " + found.join("\n  ") +
          "\n  A green result covers only these workflows on this commit; see the comment in this script."
  end
end
