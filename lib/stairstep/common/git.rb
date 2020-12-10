# frozen_string_literal: true

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

    def with_tag(to_remote, commit: , message: , tag: )
      tag_name = build_tag_name(to_remote) if tag
      git("tag", "-a", "-m", message, tag_name, commit) if tag
      yield
      save_tag(tag_name) if tag
    ensure
      git("tag", "-d", tag_name) if tag
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

    def with_ref(remote, commit, &block)
      ref_name = build_ref_name(remote)
      git("update-ref", ref_name, commit, message: "Creating deploy ref (#{ref_name})")
      checkout_ref(ref_name, &block)
    ensure
      git("update-ref", "-d", ref_name, message: "Cleaning up deploy ref")
    end

    def push(remote, ref_name, force: )
      logger.info("Pushing to target environment #{remote}")
      params = [remote, "#{ref_name}:master"]
      params.unshift("--force") if force
      git("push", *params)
    end

    private

    attr_reader :executor, :logger

    def build_tag_name(remote)
      tag_name = base_tag_name = "deploy-#{deploy_name(remote)}"

      counter = 0
      while existing_tags.include?(tag_name)
        counter += 1
        tag_name = "#{base_tag_name}.#{counter}"
      end

      tag_name
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

    def git(*command, capture_stdout: false, **options)
      if capture_stdout
        executor.fetch_stdout(:execute!, "git", *command, **options)
      else
        executor.execute!("git", *command, **options)
      end
    end
  end
end

