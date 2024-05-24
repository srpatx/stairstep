require "date"
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

    def with_tag(to_remote, commit:, message:, tag:)
      tag_name = build_tag_name(to_remote) if tag
      git("tag", "-a", "-m", message, tag_name, commit) if tag
      yield
      save_tag(tag_name) if tag
    ensure
      delete_tag(tag_name) if tag
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

    def save_tag(tag_name)
      git("push", "origin", tag_name)
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
