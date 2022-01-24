require_relative "../stairstep/base"

class Stairstep::Promote < Stairstep::Base
  def run
    heroku.verify_pipeline(pipeline)
    verify_remotes
    verify_applications
    heroku.capture_db(to_remote) if capture_db?

    promote_slug

    logger.info("Success!")
  end

  private

  def process_options(options)
    super
    @from_remote = options["from"]
  end

  def pipeline
    @pipeline ||= heroku.pipeline || git.project_name
  end

  def verify_remotes
    logger.error("Unknown remote to promote from") unless from_remote
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

  def from_commit
    heroku.slug_commit(pipeline, from_remote)
  end

  def promote_slug
    git.with_tag(to_remote, commit: from_commit, message: "Deploy to #{to_remote} from #{from_remote} at #{Time.now}", tag: tag?) do
      heroku.manage_deploy(to_remote, downtime: downtime?, initial_deploy: initial_deploy?) do
        heroku.promote_slug(pipeline, from_remote, to_remote)
      end
    end
  end
end

