require 'spec_helper'

# v1.0.0-beta.35 was built, signed, notarized, manifest-verified and published
# with Lint red on both dev and main. Every gate in the release procedure looks
# at the artifacts; none looked at whether the commit they were built from
# passed CI.
#
# What these examples pin is the shapes that must NOT read as green. A gate
# that only recognises an explicit red is the gate that was missing: the ways
# this goes wrong are a run that never started, a run still going, a stale
# success sitting next to a newer failure, a green run with a job missing from
# it, and an API call that failed.
RSpec.describe 'scripts/verify_ci_green.rb' do
  before(:all) do
    load File.expand_path('../../../../../../scripts/verify_ci_green.rb', __dir__)
  end

  let(:sha) { 'a' * 40 }
  let(:lint_run) do
    { 'id' => 100, 'name' => 'Lint', 'path' => '.github/workflows/lint.yml',
      'event' => 'push', 'head_branch' => 'dev', 'status' => 'completed',
      'conclusion' => 'success', 'html_url' => 'https://example.invalid/100' }
  end
  let(:specs_run) { lint_run.merge('id' => 200, 'name' => 'Specs', 'path' => '.github/workflows/specs.yml') }

  def job(name, conclusion: 'success', status: 'completed', attempt: 1)
    { 'name' => name, 'status' => status, 'conclusion' => conclusion,
      'run_attempt' => attempt, 'html_url' => "https://example.invalid/job/#{name}" }
  end

  def jobs_for(workflow, attempt: 1)
    VerifyCIGreen::REQUIRED.fetch(workflow).map { |n| job(n, attempt: attempt) }
  end

  # Shaped like the real endpoints: a page of items plus the total, which is
  # what tells a complete listing from a truncated one.
  def page(items, key, total: nil)
    { key => items, 'total_count' => total || items.size }
  end

  # Serves one canned answer per API path. Anything the gate asks for that was
  # not set up raises, so a check that silently stops asking cannot pass.
  def fake(runs: nil, jobs: nil, &block)
    return block if block

    lambda do |path|
      case path
      when %r{workflows/lint\.yml/runs} then page(( runs || {})[:lint].to_a, 'workflow_runs')
      when %r{workflows/specs\.yml/runs} then page((runs || {})[:specs].to_a, 'workflow_runs')
      # Lint runs are numbered 1xx here and Specs runs 2xx, so a re-run keeps
      # its workflow's jobs without the fake needing to know every id.
      when %r{runs/1\d\d/jobs} then page((jobs || {}).fetch(:lint, jobs_for('.github/workflows/lint.yml')), 'jobs')
      when %r{runs/2\d\d/jobs} then page((jobs || {}).fetch(:specs, jobs_for('.github/workflows/specs.yml')), 'jobs')
      else raise "unexpected API path: #{path}"
      end
    end
  end

  def problems(**kwargs)
    VerifyCIGreen.problems(sha: sha, fetch: fake(**kwargs))
  end

  it 'accepts a commit whose required workflows and jobs all succeeded' do
    expect(problems(runs: { lint: [lint_run], specs: [specs_run] })).to be_empty
  end

  it 'refuses a sha that is not a full commit id' do
    expect(VerifyCIGreen.problems(sha: 'cd87e5a8', fetch: fake)).to include(/full 40-character/)
  end

  # The absence of a red is not a green. A workflow that never started leaves
  # nothing to fail.
  it 'refuses a commit with no run at all' do
    expect(problems(runs: { lint: [], specs: [] })).to contain_exactly(
      /lint\.yml: no push run/, /specs\.yml: no push run/
    )
  end

  it 'refuses a commit where only one required workflow ran' do
    expect(problems(runs: { lint: [lint_run], specs: [] })).to contain_exactly(/specs\.yml: no push run/)
  end

  it 'refuses a run that has not finished' do
    pending_run = specs_run.merge('status' => 'in_progress', 'conclusion' => nil)
    expect(problems(runs: { lint: [lint_run], specs: [pending_run] }))
      .to contain_exactly(/specs\.yml: run 200 is in_progress, not finished/)
  end

  it 'refuses a run that failed' do
    expect(problems(runs: { lint: [lint_run.merge('conclusion' => 'failure')], specs: [specs_run] }))
      .to include(/lint\.yml: run 100 concluded "failure"/)
  end

  ['cancelled', 'timed_out', 'skipped', 'neutral', 'action_required', nil].each do |conclusion|
    it "refuses a run that concluded #{conclusion.inspect}" do
      expect(problems(runs: { lint: [lint_run.merge('conclusion' => conclusion)], specs: [specs_run] }))
        .to include(/lint\.yml: run 100 concluded/)
    end
  end

  # A re-run that failed must not be overridden by the success it replaced.
  it 'evaluates the newest run when a commit has more than one' do
    old_success = lint_run.merge('id' => 99)
    new_failure = lint_run.merge('id' => 101, 'conclusion' => 'failure')
    found = problems(runs: { lint: [old_success, new_failure], specs: [specs_run] })
    expect(found).to include(/lint\.yml: run 101 concluded "failure"/)
  end

  # Having had to choose is worth saying, but it is not a reason to refuse: an
  # earlier version put this in the problem list, which made a commit with two
  # green runs impossible to release.
  it 'accepts a commit with two green runs and says which one it used' do
    notes = []
    found = VerifyCIGreen.problems(
      sha: sha, notes: notes,
      fetch: fake(runs: { lint: [lint_run, lint_run.merge('id' => 101)], specs: [specs_run] })
    )
    expect(found).to be_empty
    expect(notes).to include(/lint\.yml: 2 runs for this commit; evaluating the newest \(101\)/)
  end

  # The run it settled on is the evidence the release rests on.
  it 'records the run it accepted even when nothing is wrong' do
    notes = []
    VerifyCIGreen.problems(sha: sha, notes: notes,
                           fetch: fake(runs: { lint: [lint_run], specs: [specs_run] }))
    expect(notes).to include(/lint\.yml: run 100 -- /, /specs\.yml: run 200 -- /)
  end

  # head_sha alone also matches a pull_request run and the same commit pushed
  # elsewhere, neither of which tested what is being released.
  it 'does not accept a pull_request run for the same commit' do
    expect(problems(runs: { lint: [lint_run.merge('event' => 'pull_request')], specs: [specs_run] }))
      .to contain_exactly(/lint\.yml: no push run/)
  end

  it 'does not accept a run from another branch' do
    expect(problems(runs: { lint: [lint_run.merge('head_branch' => 'feature')], specs: [specs_run] }))
      .to contain_exactly(/lint\.yml: no push run/)
  end

  it 'accepts a run on the branch it was asked about' do
    main_run = lint_run.merge('head_branch' => 'main')
    fetcher = fake(runs: { lint: [main_run], specs: [specs_run.merge('head_branch' => 'main')] })
    expect(VerifyCIGreen.problems(sha: sha, branch: 'main', fetch: fetcher)).to be_empty
  end

  # A green workflow is not every job having run: a job removed from the
  # workflow, or skipped by a condition, leaves the run green.
  it 'refuses a green run that is missing a required job' do
    partial = jobs_for('.github/workflows/specs.yml').reject { |j| j['name'] == 'jest' }
    expect(problems(runs: { lint: [lint_run], specs: [specs_run] }, jobs: { specs: partial }))
      .to contain_exactly(/job "jest" did not run in 200/)
  end

  it 'refuses a green run whose required job was skipped' do
    skipped = jobs_for('.github/workflows/lint.yml').map do |j|
      j['name'] == 'eslint' ? j.merge('conclusion' => 'skipped') : j
    end
    expect(problems(runs: { lint: [lint_run], specs: [specs_run] }, jobs: { lint: skipped }))
      .to contain_exactly(%r{job "eslint" is completed/"skipped"})
  end

  # `filter=latest` would drop the jobs a failed-jobs-only re-run did not
  # repeat, which would read as "job did not run" on a run that is green.
  it 'accepts a partial re-run where the untouched jobs succeeded on the first attempt' do
    mixed = [job('anti-patterns', attempt: 1), job('eslint', conclusion: 'failure', attempt: 1),
             job('eslint', attempt: 2)]
    expect(problems(runs: { lint: [lint_run], specs: [specs_run] }, jobs: { lint: mixed })).to be_empty
  end

  it 'takes the newest attempt of a job even when the older one is listed later' do
    regressed = [job('anti-patterns', attempt: 1), job('eslint', attempt: 2),
                 job('eslint', conclusion: 'failure', attempt: 1)]
    expect(problems(runs: { lint: [lint_run], specs: [specs_run] }, jobs: { lint: regressed })).to be_empty
  end

  # An API that could not be read is not an API that reported success.
  it 'refuses when the runs cannot be read' do
    failing = lambda do |path|
      raise VerifyCIGreen::ApiError, 'HTTP 403' if path.include?('lint.yml')

      page([specs_run], 'workflow_runs')
    end
    expect(VerifyCIGreen.problems(sha: sha, fetch: failing))
      .to include(/lint\.yml: cannot read the workflow runs \(HTTP 403\)/)
  end

  it 'refuses when the response has no workflow_runs' do
    expect(VerifyCIGreen.problems(sha: sha, fetch: ->(_) { { 'message' => 'Not Found' } }))
      .to include(/cannot read the workflow runs \(no workflow_runs in the response\)/)
  end

  it 'refuses when the jobs of a green run cannot be read' do
    fetcher = lambda do |path|
      raise VerifyCIGreen::ApiError, 'HTTP 502' if path.include?('/jobs')

      page([path.include?('lint.yml') ? lint_run : specs_run], 'workflow_runs')
    end
    expect(VerifyCIGreen.problems(sha: sha, fetch: fetcher)).to include(/cannot read the jobs of run/)
  end

  # `per_page=100` is a page size, not "everything". Four jobs re-run twenty-six
  # times is 104 entries: reading only the first page would take a job's stale
  # success for its latest attempt.
  describe 'listings that do not fit on one page' do
    let(:many) do
      26.times.flat_map do |i|
        jobs_for('.github/workflows/specs.yml').map { |j| j.merge('run_attempt' => i + 1) }
      end
    end

    def paged_fetch(all_jobs)
      lambda do |path|
        case path
        when %r{workflows/lint\.yml/runs} then page([lint_run], 'workflow_runs')
        when %r{workflows/specs\.yml/runs} then page([specs_run], 'workflow_runs')
        when %r{runs/1\d\d/jobs} then page(jobs_for('.github/workflows/lint.yml'), 'jobs')
        when %r{runs/2\d\d/jobs}
          # Anchored on the separator: /page=(\d+)/ matches per_page=100 first,
          # which asks for page 100 and gets an empty slice back.
          n = path[/[?&]page=(\d+)/, 1].to_i
          page(all_jobs.each_slice(100).to_a[n - 1] || [], 'jobs', total: all_jobs.size)
        else raise "unexpected API path: #{path}"
        end
      end
    end

    it 'reads every page before deciding' do
      expect(VerifyCIGreen.problems(sha: sha, fetch: paged_fetch(many))).to be_empty
    end

    it 'refuses when the newest attempt on a later page did not succeed' do
      regressed = many[0..-2] + [many.last.merge('conclusion' => 'skipped')]
      expect(VerifyCIGreen.problems(sha: sha, fetch: paged_fetch(regressed)))
        .to include(%r{job "rspec integration \(IN_CONTAINER=false\)" is completed/"skipped"})
    end

    it 'refuses when a later page cannot be read' do
      fetcher = paged_fetch(many)
      failing = lambda do |path|
        raise VerifyCIGreen::ApiError, 'HTTP 502' if path.include?('page=2')

        fetcher.call(path)
      end
      expect(VerifyCIGreen.problems(sha: sha, fetch: failing)).to include(/cannot read the jobs of run/)
    end

    # An empty page before the total is reached means the listing cannot be
    # completed, which is not the same as having seen all of it.
    it 'refuses a listing that stops short of the reported total' do
      short = lambda do |path|
        first = path.match?(/[?&]page=1(&|$)/)
        page(first ? [lint_run] : [], 'workflow_runs', total: 5)
      end
      expect(VerifyCIGreen.problems(sha: sha, fetch: short))
        .to include(/lint\.yml: cannot read the workflow runs \(workflow_runs listing stopped short of 5\)/)
    end

    # Without a total there is no way to tell a complete page from a truncated
    # one, so an answer that omits it is unreadable rather than complete.
    it 'refuses a response with no total_count' do
      expect(VerifyCIGreen.problems(sha: sha, fetch: ->(_) { { 'workflow_runs' => [lint_run] } }))
        .to include(/no total_count in the workflow_runs response/)
    end
  end

  # The required set is what makes the gate non-vacuous, so it is pinned here:
  # dropping a workflow or a job from REQUIRED silently shrinks what a green
  # result means.
  it 'requires both lint and specs, down to their jobs' do
    expect(VerifyCIGreen::REQUIRED).to eq(
      '.github/workflows/lint.yml' => ['anti-patterns', 'eslint'],
      '.github/workflows/specs.yml' => ['rspec unit', 'jest',
                                        'rspec integration (IN_CONTAINER=true)',
                                        'rspec integration (IN_CONTAINER=false)']
    )
  end
end
