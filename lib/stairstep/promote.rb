# frozen_string_literal: true

require "date"
require_relative "../stairstep"
require_relative "../stairstep/command_executor"
require_relative "../stairstep/common/heroku"

# rubocop:disable Metrics/ClassLength
class Stairstep::Promote
  def run(to_remote, options)
    @to_remote = to_remote
    process_options(options)

    heroku.verify_pipeline(pipeline)
    verify_remotes
    verify_applications
    heroku.capture_db(to_remote) if capture_db?

    promote_slug

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
    heroku.verify_application(from_remote)
    heroku.verify_application(to_remote)
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
    heroku.slug_commit(pipeline, from_remote)
  end

  def save_tag
    git("push", "origin", tag_name)
  end

  def promote_slug
    with_tag do
      heroku.scale_dynos(to_remote) do
        heroku.with_maintenance(to_remote, downtime: downtime?) do
          heroku.promote_slug(pipeline, from_remote, to_remote)
        end
      end
    end
  end

  def executor
    @executor ||= Stairstep::CommandExecutor.new
  end

  def heroku
    @heroku ||= Stairstep::Common::Heroku.new(executor)
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

