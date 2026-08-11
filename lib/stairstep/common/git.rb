require "date"
require "stringio"
require_relative "../../stairstep"

module Stairstep::Common
  class Git
    def initialize(executor, logger)
      @executor = executor
      @logger = logger
    end

    def project_name
      File.basename(git("rev-parse", "--show-toplevel", capture_stdout: true)).rstrip
    end

    def commit_sha(ref_name)
      git("rev-parse", "--verify", ref_name, capture_stdout: true).chomp
    end

    # Records the deploy as an annotated tag on origin, AFTER the deploy runs, so
    # a tag that appears on origin during the — potentially minutes-long — deploy
    # can't make us commit to a stale number and then collide on push. If the push
    # still loses a race, the collision is only accepted when the deployed
    # artifact matches what is already recorded (see #push_deploy_tag); promote
    # passes verify_deploy for a Heroku slug-checksum comparison.
    def with_tag(to_remote, commit:, message:, tag:, verify_deploy: nil)
      yield
      save_deploy_tag(to_remote, commit, message, verify_deploy) if tag
    end

    def verify_clean_working_directory
      diff = git("diff", "--shortstat", capture_stdout: true).strip

      if !diff.empty?
        logger.error(<<~ERROR)
          Your working directory contains uncommitted files.

          The deploy process may destroy your work.  Please commit and try again.

          Output:
          #{diff}
        ERROR
      end
    end

    def with_ref(remote, commit, &)
      ref_name = build_ref_name(remote)
      git("update-ref", ref_name, commit, message: "Creating deploy ref (#{ref_name})")
      checkout_ref(ref_name, &)
    ensure
      git("update-ref", "-d", ref_name, message: "Cleaning up deploy ref")
    end

    def push(remote, ref_name, force:)
      logger.info("Pushing to target environment #{remote}")
      params = [remote, "#{ref_name}:master"]
      params.unshift("--force") if force
      git("push", *params)
    end

    private

    attr_reader :executor, :logger

    def build_tag_name(remote)
      base_tag_name = base_tag_name(remote)

      counter = 0
      tag_name = base_tag_name

      while existing_tags.include?(tag_name)
        counter += 1
        tag_name = "#{base_tag_name}.#{counter}"
      end

      tag_name
    end

    def base_tag_name(remote)
      ["deploy", config["tag_prefix"], deploy_name(remote)].compact.join("-")
    end

    def existing_tags
      @existing_tags ||=
        begin
          git("fetch", "--tags")
          git("tag", capture_stdout: true).split("\n")
        end
    end

    # Number, create, and push the deploy tag — all after the deploy — so the
    # number reflects origin state seconds before the push (not minutes) and a tag
    # that appeared mid-deploy can't force a stale collision. Each deploy records
    # its own tag; #push_deploy_tag decides whether a losing-race collision is
    # benign.
    def save_deploy_tag(remote, commit, message, verify_deploy)
      refresh_existing_tags!
      tag_name = build_tag_name(remote)
      git("tag", "-a", "-m", message, tag_name, commit)
      push_deploy_tag(tag_name, commit_sha(commit), verify_deploy)
    ensure
      delete_tag(tag_name) if tag_name
    end

    # A rejected push is treated as success only when BOTH hold:
    #   * it is a "tag already exists" collision — decided from the push output,
    #     not the (generic) exception, and NOT an auth/network/hook failure; and
    #   * the deployed artifact matches what the colliding tag records
    #     (see #deployed_artifact_matches?).
    # Anything else re-raises.
    def push_deploy_tag(tag_name, deployed_sha, verify_deploy)
      output = StringIO.new
      succeeded = executor.execute("git", "push", "origin", tag_name, output: output)
      print(output.string)
      return if succeeded

      unless tag_collision?(output.string) && deployed_artifact_matches?(tag_name, deployed_sha, verify_deploy)
        raise("Command failed: `git push origin #{tag_name}`")
      end

      logger.info("Tag #{tag_name} already on origin and the deployed artifact matches; treating as success")
    end

    def tag_collision?(push_output)
      push_output.match?(/reference already exists|cannot lock ref/)
    end

    # Whether the just-deployed artifact matches what the colliding tag already
    # records. Promote supplies verify_deploy — a Heroku slug-checksum comparison
    # (deployed vs. live) — so a same-name / different-slug deploy fails loudly
    # (INS-11420 AC1). Without it, the deploy path (no from/to slug pair) falls
    # back to the git commit the existing tag points at.
    def deployed_artifact_matches?(tag_name, deployed_sha, verify_deploy)
      return verify_deploy.call if verify_deploy

      remote_tag_commit(tag_name) == deployed_sha
    end

    def remote_tag_commit(tag_name)
      # ls-remote prints "<sha>\t<ref>" per matching ref; take the sha off the ref
      # line (line-anchored, so a leading warning/redirect line doesn't derail it).
      git("ls-remote", "origin", "refs/tags/#{tag_name}^{}", capture_stdout: true)[/^(\h{7,})\s/, 1]
    rescue
      nil
    end

    def refresh_existing_tags!
      @existing_tags = nil
    end

    def delete_tag(tag_name)
      git("tag", "-d", tag_name)
    rescue
      warn("Failed to delete tag #{tag_name}, continuing...")
    end

    def checkout_ref(ref_name)
      git("checkout", "--quiet", ref_name, message: "Checking out deploy ref")
      yield(ref_name)
    ensure
      git("checkout", "-", "-f", "--quiet", message: "Restoring HEAD position")
    end

    def build_ref_name(remote)
      "refs/deploys/#{deploy_name(remote)}"
    end

    def deploy_name(remote)
      "#{remote}-#{Date.today}"
    end

    def git(*command, capture_stdout: false, **)
      if capture_stdout
        executor.fetch_stdout(:execute!, "git", *command, **)
      else
        executor.execute!("git", *command, **)
      end
    end

    def config
      @config ||=
        if File.exist?("config/stairstep.yml")
          YAML.load_file("config/stairstep.yml")
        else
          {}
        end
    end
  end
end
