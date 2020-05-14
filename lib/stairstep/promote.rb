# frozen_string_literal: true

require "date"
require "json"
require_relative "../stairstep"
require_relative "../stairstep/command_executor"

# rubocop:disable Metrics/ClassLength
class Stairstep::Promote
  def run(to_remote, options)
    @to_remote = to_remote
    process_options(options)

    verify_pipeline
    verify_remotes
    verify_applications
    capture_db if capture_db?

    with_tag { promote_slug }

    info("Success!")
  end

  private

  attr_reader :to_remote

  def process_options(options)
    @from_remote = options["from"]
    @capture_db = options["db-capture"]
    @downtime = options["downtime"]
    @tag = options["tag"]
    @debug = options["debug"]
  end

  def pipeline
    @pipeline ||= File.basename(fetch_stdout(:git, "rev-parse", "--show-toplevel")).rstrip
  end

  def verify_pipeline
    execute("heroku", "pipelines:info", pipeline, output: nil)
  end

  def verify_remotes
    error("Unknown remote to promote from") unless from_remote
  end

  def from_remote
    @from_remote ||= calculate_from_remote
  end

  # rubocop:disable Style/MissingElse
  def calculate_from_remote
    case to_remote
    when "production" then "staging"
    when "staging" then "demo"
    end
  end
  # rubocop:enable Style/MissingElse

  def verify_applications
    verify_application(from_remote)
    verify_application(to_remote)
  end

  def verify_application(remote)
    heroku(remote, "apps:info", output: nil)
  rescue
    error("Cannot access Heroku application at remote '#{remote}'")
  end

  def capture_db
    heroku(to_remote, "pg:backups", "capture")
  rescue Exception # rubocop:disable Lint/RescueException
    heroku(to_remote, "pg:backups", "cancel")
    raise
  end

  def with_tag
    git("tag", "-a", "-m", "Deploy to #{to_remote} from #{from_remote} at #{Time.now}", tag_name, from_commit) if tag?
    yield
    save_tag if tag?
  ensure
    git("tag", "-d", tag_name) if tag?
  end

  def tag_name
    @tag_name ||=
      begin
        tag_name = base_tag_name = "deploy-#{deploy_name}"
        counter = 0
        while existing_tags.include?(tag_name)
          counter += 1
          tag_name = "#{base_tag_name}.#{counter}"
        end

        tag_name
      end
  end

  def existing_tags
    @existing_tags ||=
      begin
        git("fetch", "--tags")
        fetch_stdout(:git, "tag").split("\n")
      end
  end

  def deploy_name
    @deploy_name ||= "#{to_remote}-#{Date.today}"
  end

  def from_commit
    path = "/apps/#{from_app}/slugs/#{from_slug_id}"
    slug_json = fetch_stdout(:heroku_api, "GET", path)
    JSON.parse(slug_json)["commit"]
  end

  def from_slug_id
    release_json = fetch_stdout(:heroku, from_remote, "releases:info", "--json")
    JSON.parse(release_json)["slug"]["id"]
  end

  def from_app
    "#{pipeline}-#{from_remote}"
  end

  def to_app
    "#{pipeline}-#{to_remote}"
  end

  def promote_slug
    scale_dynos do
      with_maintenance do
        heroku(from_remote, "pipelines:promote", "--to", to_app)
      end
    end
  end

  def scale_dynos
    heroku(to_remote, "ps:scale", *(worker_dyno_counts(to_remote).collect { |type, _| "#{type}=0" }))
    yield
  ensure
    heroku(to_remote, "ps:scale", *(worker_dyno_counts(to_remote).collect { |type, count| "#{type}=#{count}" }))
  end

  def worker_dyno_counts(remote)
    @worker_dyno_counts ||= {}
    @worker_dyno_counts[remote] ||=
      begin
        dyno_json = fetch_stdout(:heroku, remote, "ps", "--json")
        web_dyno_defs = JSON.parse(dyno_json).reject { |dyno_def| %w[web scheduler run].include?(dyno_def["type"]) }

        web_dyno_defs.inject(Hash.new(0)) do |dynos, dyno_def|
          type = dyno_def["type"]
          dynos.merge(type => dynos[type] + 1)
        end
      end
  end

  def with_maintenance
    heroku(to_remote, "maintenance:on") if downtime?
    yield
  ensure
    heroku(to_remote, "maintenance:off") if downtime?
  end

  def save_tag
    git("push", "origin", tag_name)
  end

  def executor
    @executor ||= Stairstep::CommandExecutor.new
  end

  def info(message)
    puts("\n", "=-" * 40)
    puts(message.upcase)
  end

  def warning(message)
    puts("\n", "?" * 80)
    puts(message.upcase)
  end

  def error(message, exception: nil)
    puts("\n", "!" * 80)
    if exception
      p(exception)
      raise if debug?
    end
    abort(message.upcase)
  end

  def method_missing(method, *args, **kwargs)
    if (match_data = method.to_s.match(/\A(\w+)\?\z/)) # => e.g. #capture_db?
      instance_variable_get(:"@#{match_data[1]}")
    elsif executor.respond_to?(method)
      executor.public_send(method, *args, **kwargs)
    else
      super
    end
  end

  def respond_to_missing?(method, *)
    match_data = method.to_s.match(/\A(\w+)\?\z/)
    super || instance_variable_names.include?(:"@#{match_data[1]}")
  end
end
# rubocop:enable Metrics/ClassLength

