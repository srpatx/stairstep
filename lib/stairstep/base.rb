require_relative "../stairstep"
require_relative "../stairstep/command_executor"
require_relative "../stairstep/logger"
require_relative "../stairstep/common/git"
require_relative "../stairstep/common/heroku"

class Stairstep::Base
  def initialize(thor, to_remote, options)
    @thor = thor
    @to_remote = to_remote
    process_options(options)
  end

  private

  attr_reader :thor, :to_remote

  def process_options(options)
    @capture_db = options["db-capture"]
    @downtime = options["downtime"]
    @tag = options["tag"]
    @debug = options["debug"]
    @initial_deploy = options["initial-deploy"]
  end

  def executor
    @executor ||= Stairstep::CommandExecutor.new
  end

  def heroku
    @heroku ||= Stairstep::Common::Heroku.new(executor, logger)
  end

  def git
    @git ||= Stairstep::Common::Git.new(executor, logger)
  end

  def logger
    @logger ||= Stairstep::Logger.new
  end

  def method_missing(method, *args, **kwargs)
    if (match_data = method.to_s.match(/\A(\w+)\?\z/)) # => e.g. #capture_db?
      instance_variable_get(:"@#{match_data[1]}")
    else
      super
    end
  end

  def respond_to_missing?(method, *)
    match_data = method.to_s.match(/\A(\w+)\?\z/)
    super || instance_variable_names.include?(:"@#{match_data[1]}")
  end
end
