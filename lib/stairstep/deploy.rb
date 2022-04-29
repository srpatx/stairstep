require_relative "../stairstep/base"
require_relative "../stairstep/command_executor"
require_relative "../stairstep/common/bundler"
require "fileutils"

class Stairstep::Deploy < Stairstep::Base
  def run
    heroku.verify_application(to_remote)
    git.verify_clean_working_directory
    ensure_log_directory
    heroku.capture_db(to_remote) if capture_db?

    git.with_ref(to_remote, commit) do |ref_name|
      bundler.install_local_gems
      prepare_commit(ref_name)
      push_commit(ref_name)
    end

    logger.info("Success!")
  end

  private

  def process_options(options)
    super
    @commit = options["commit"]
    @force = options["force"]
    @precompile = options["assets-precompile"]
    @bundle = options["bundle-package"]

    if options["development"]
      @bundle = false
      @tag = false
    end
  end

  def commit
    @commit || "HEAD"
  end

  def ensure_log_directory
    Dir.mkdir("log") unless Dir.exist?("log")
  end

  def prepare_commit(ref_name)
    logger.info("Preparing commit")
    precompile if precompile?
    bundle(ref_name) if bundle?
  end

  def precompile
    executor.execute!({ "RAILS_ENV" => "production" }, "bundle", "exec", "rake", "assets:precompile", message: "Precompiling assets")
    executor.execute!({ "RAILS_ENV" => "production" }, "bundle", "exec", "rake", "assets:clean", message: "Cleaning outdated assets")
  end

  def bundle(ref_name)
    File.open("log/bundle-package.log", "w+") do |file|
      executor.execute!("bundle", "package", message: "Packaging gems -- log: #{file.path}", output: file, progress: true)
      executor.execute!("git", "add", "-f", "vendor/cache")
      executor.execute!("git", "commit", "-m", "Package gems", message: "git commit -m'Package gems'", output: file)
    end

    executor.execute!("git", "update-ref", ref_name, "head", ref_name)
  end

  def push_commit(ref_name)
    git.with_tag(to_remote, commit: ref_name, message: "Deploy to #{to_remote} at #{Time.now}", tag: tag?) do
      verify_force if force?
      heroku.manage_deploy(to_remote, downtime: downtime?, initial_deploy: initial_deploy?) do
        if precompile?
          FileUtils.rm_rf("node_modules")
          FileUtils.rm_rf(".bundle")
          heroku.create_build(to_remote, git.commit_sha(ref_name))
        else
          git.push(to_remote, ref_name, force: force?)
        end
      end
    end
  end

  def verify_force
    logger.warning("Force push")
    puts("You are force-pushing to a deployed environment!")
    puts("Verify you want to do this by typing the name of the remote:")
    answer = thor.ask("> ")

    logger.error("Verification failed") unless answer.strip == to_remote
  end

  def bundler
    @bundler ||= Stairstep::Common::Bundler.new(executor, logger)
  end
end
