require_relative "../../stairstep"

module Stairstep::Common
  class Bundler
    def initialize(executor, logger)
      @executor = executor
      @logger = logger
    end

    def install_local_gems
      File.open("log/bundle-install.log", "w+") do |file|
        execute("check", message: "Checking local gems", output: file) ||
          execute!("install", message: "Installing local gems (log: #{file.path})", output: file, progress: true)
      end
    end

    private

    attr_reader :executor, :logger

    def execute(*command, capture_stdout: false, **options)
      if capture_stdout
        executor.fetch_stdout(:execute!, "bundle", *command, **options)
      else
        executor.execute("bundle", *command, **options)
      end
    end

    def execute!(*command, **options)
      executor.execute!("bundle", *command, **options)
    end
  end
end
