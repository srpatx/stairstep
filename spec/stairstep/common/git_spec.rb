require "date"
require "stairstep/common/git"

# Fake CommandExecutor modelling the real contract Git relies on:
#   * #execute(*cmd, output:) runs a command, writes its (fake) output to the
#     given IO, and returns a success boolean — used only for the tag push.
#   * #execute!(*cmd) runs a command and raises on failure — used for the other
#     mutating git commands.
#   * #fetch_stdout(:execute!, *cmd) returns canned stdout for a read command.
# Every command is recorded so examples can assert what git ran.
class FakeGitExecutor
  attr_reader :calls

  def initialize(stdout: {}, fail_on: [], push_fails: false, push_output: "")
    @stdout = stdout
    @fail_on = fail_on
    @push_fails = push_fails
    @push_output = push_output
    @calls = []
  end

  def execute(*command, output: nil, **)
    @calls << command
    output&.write(@push_output)
    !@push_fails
  end

  def execute!(*command, **)
    @calls << command
    raise "Command failed: `#{command.join(" ")}`" if @fail_on.include?(command)

    true
  end

  def fetch_stdout(_exec, *command, **)
    @calls << command
    @stdout.fetch(command, "")
  end

  def ran?(*command) = @calls.include?(command)

  def pushed_any_tag? = @calls.any? { |c| c[0, 2] == ["git", "push"] }

  def tagged_any? = @calls.any? { |c| c[0, 2] == ["git", "tag"] }
end

RSpec.describe Stairstep::Common::Git do
  subject(:git) { described_class.new(executor, logger) }

  let(:logger) { double("Logger", info: nil) }
  let(:executor) do
    FakeGitExecutor.new(stdout: stdout, fail_on: fail_on, push_fails: push_fails, push_output: push_output)
  end
  let(:fail_on) { [] }
  let(:push_fails) { false }
  let(:push_output) { "" }

  let(:base) { "deploy-production-#{Date.today}" }
  let(:commit) { "abc123abc123abc123abc123abc123abc123abcd" }

  # By default `commit` resolves to itself and today has no deploy tags yet.
  let(:stdout) do
    {
      ["git", "rev-parse", "--verify", commit] => commit,
      ["git", "tag"] => existing_tag_list.join("\n")
    }
  end
  let(:existing_tag_list) { [] }

  def record_tag(ref: commit, verify_deploy: nil, &block)
    block ||= -> { :deployed }
    git.with_tag("production", commit: ref, message: "Deploy", tag: true, verify_deploy: verify_deploy, &block)
  end

  describe "ordering / gating" do
    it "runs the deploy (yield) before any tagging or push" do
      calls_at_yield = nil
      record_tag { calls_at_yield = executor.calls.dup }

      # nothing git-tag/push related had run by the time the deploy block executed
      expect(calls_at_yield.any? { |c| c[0, 2] == ["git", "tag"] || c[0, 2] == ["git", "push"] }).to be(false)
      # ...and tagging did happen afterwards
      expect(executor.tagged_any?).to be(true)
    end

    it "does nothing when tagging is disabled" do
      git.with_tag("production", commit: commit, message: "Deploy", tag: false) { :deployed }

      expect(executor.calls).to be_empty
    end

    it "records no tag when the deploy fails" do
      expect { record_tag { raise "boom" } }.to raise_error(/boom/)

      expect(executor.tagged_any?).to be(false)
      expect(executor.pushed_any_tag?).to be(false)
    end
  end

  describe "recording a new deploy tag" do
    it "re-fetches tags, creates a numbered tag, pushes it, and cleans up locally" do
      record_tag

      expect(executor.ran?("git", "fetch", "--tags")).to be(true) # AC2: numbering off a fresh fetch
      expect(executor.ran?("git", "tag", "-a", "-m", "Deploy", base, commit)).to be(true)
      expect(executor.ran?("git", "push", "origin", base)).to be(true)
      expect(executor.ran?("git", "tag", "-d", base)).to be(true)
    end

    it "picks the next free number when earlier tags for today already exist" do
      allow_existing(base, "#{base}.1")

      record_tag

      expect(executor.ran?("git", "tag", "-a", "-m", "Deploy", "#{base}.2", commit)).to be(true)
    end

    it "tags the resolved commit on the deploy ref-name path" do
      ref = "refs/deploys/production-#{Date.today}"
      stdout[["git", "rev-parse", "--verify", ref]] = commit # ref peels to a real SHA

      record_tag(ref: ref)

      expect(executor.ran?("git", "tag", "-a", "-m", "Deploy", base, ref)).to be(true)
    end
  end

  describe "push collision — promote path (slug identity)" do
    let(:push_fails) { true }
    let(:push_output) { " ! [remote rejected] #{base} -> #{base} (cannot lock ref 'refs/tags/#{base}': reference already exists)" }

    it "treats the collision as success when the deployed slug matches (verify_deploy true)" do
      expect { record_tag(verify_deploy: -> { true }) }.not_to raise_error
      expect(executor.ran?("git", "tag", "-d", base)).to be(true) # still cleans up local
    end

    it "fails loudly when the deployed slug differs (verify_deploy false)" do
      expect { record_tag(verify_deploy: -> { false }) }.to raise_error(/Command failed/)
    end
  end

  describe "push collision — deploy path (commit identity fallback)" do
    let(:push_fails) { true }
    let(:push_output) { "cannot lock ref 'refs/tags/#{base}': reference already exists" }

    it "treats a same-commit collision as success" do
      stub_remote_peeled(base, commit)

      expect { record_tag }.not_to raise_error
    end

    it "re-raises when the existing tag points at a different commit" do
      stub_remote_peeled(base, "def456def456def456def456def456def456abcd")

      expect { record_tag }.to raise_error(/Command failed/)
    end

    it "re-raises when the tag is absent on origin (ls-remote empty)" do
      # no stub_remote_peeled → ls-remote returns "" → nil
      expect { record_tag }.to raise_error(/Command failed/)
    end

    it "tolerates a multi-line ls-remote (leading warning) when extracting the sha" do
      stdout[["git", "ls-remote", "origin", "refs/tags/#{base}^{}"]] =
        "warning: redirecting to https://...\n#{commit}\trefs/tags/#{base}^{}\n"

      expect { record_tag }.not_to raise_error
    end
  end

  describe "non-collision push failure (auth / network)" do
    let(:push_fails) { true }
    let(:push_output) { "fatal: unable to access 'https://...': Could not resolve host: github.com" }

    it "re-raises even if the deployed artifact would have matched" do
      # verify would say "matches", but the failure is NOT a tag collision
      expect { record_tag(verify_deploy: -> { true }) }.to raise_error(/Command failed/)
    end
  end

  # --- helpers ---

  def allow_existing(*names)
    stdout[["git", "tag"]] = names.join("\n")
  end

  def stub_remote_peeled(tag_name, sha)
    stdout[["git", "ls-remote", "origin", "refs/tags/#{tag_name}^{}"]] = "#{sha}\trefs/tags/#{tag_name}^{}"
  end
end
