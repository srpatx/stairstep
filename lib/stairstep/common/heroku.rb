# frozen_string_literal: true

require "json"
require_relative "../../stairstep"

module Stairstep::Common
  class Heroku
    def initialize(executor)
      @executor = executor
    end

    def verify_pipeline(pipeline)
      executor.execute("heroku", "pipelines:info", pipeline, output: nil)
    end

    def verify_application(remote)
      heroku(remote, "apps:info", output: nil)
    rescue
      error("Cannot access Heroku application at remote '#{remote}'")
    end

    def capture_db(remote)
      heroku(remote, "pg:backups", "capture")
    rescue Exception # rubocop:disable Lint/RescueException
      heroku(remote, "pg:backups", "cancel")
      raise
    end

    def slug_commit(pipeline, remote)
      app_name = "#{pipeline}-#{remote}"
      path = "/apps/#{app_name}/slugs/#{slug_id(remote)}"
      slug_json = heroku_api("GET", path)
      JSON.parse(slug_json)["commit"]
    end

    def slug_id(remote)
      release_json = heroku(remote, "releases:info", "--json", capture_stdout: true)
      JSON.parse(release_json)["slug"]["id"]
    end

    def scale_dynos(remote)
      heroku(remote, "ps:scale", *(worker_dyno_counts(remote).collect { |type, _| "#{type}=0" }))
      yield
    ensure
      heroku(remote, "ps:scale", *(worker_dyno_counts(remote).collect { |type, count| "#{type}=#{count}" }))
    end

    def worker_dyno_counts(remote)
      @worker_dyno_counts ||= {}
      @worker_dyno_counts[remote] ||=
        begin
          dyno_json = heroku(remote, "ps", "--json", capture_stdout: true)
          web_dyno_defs = JSON.parse(dyno_json).reject { |dyno_def| %w[web scheduler run].include?(dyno_def["type"]) }

          web_dyno_defs.inject(Hash.new(0)) do |dynos, dyno_def|
            type = dyno_def["type"]
            dynos.merge(type => dynos[type] + 1)
          end
        end
    end

    def with_maintenance(remote, downtime: )
      heroku(remote, "maintenance:on") if downtime
      yield
    ensure
      heroku(remote, "maintenance:off") if downtime
    end

    def promote_slug(pipeline, from_remote, to_remote)
      heroku(from_remote, "pipelines:promote", "--to", "#{pipeline}-#{to_remote}")
    end

    private

    attr_reader :executor

    def heroku(remote, *command, capture_stdout: false, **options)
      if capture_stdout
        executor.fetch_stdout(:execute!, "heroku", *command, "--remote", remote, **options)
      else
        executor.execute!("heroku", *command, "--remote", remote, **options)
      end
    end

    def heroku_api(method, path, **options)
      executor.fetch_stdout(:execute!, "heroku", "api", method, path, **options)
    end
  end
end

