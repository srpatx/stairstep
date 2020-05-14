# frozen_string_literal: true

require "date"
require_relative "../../stairstep"

module Stairstep::Common
  class Git
    def initialize(executor)
      @executor = executor
    end

    def project_name
      File.basename(git("rev-parse", "--show-toplevel", capture_stdout: true)).rstrip
    end

    def with_tag(from_remote, to_remote, from_commit, tag: )
      tag_name = build_tag_name(to_remote)
      git("tag", "-a", "-m", "Deploy to #{to_remote} from #{from_remote} at #{Time.now}", tag_name, from_commit) if tag
      yield
      save_tag(tag_name) if tag
    ensure
      git("tag", "-d", tag_name) if tag
    end

    private

    attr_reader :executor

    def build_tag_name(remote)
      tag_name = base_tag_name = "deploy-#{remote}-#{Date.today}"

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

    def git(*command, capture_stdout: false, **options)
      if capture_stdout
        executor.fetch_stdout(:execute!, "git", *command, **options)
      else
        executor.execute!("git", *command, **options)
      end
    end
  end
end

