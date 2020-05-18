# frozen_string_literal: true

require "thor"
require_relative "../stairstep"
require_relative "../stairstep/promote"

class Stairstep::CLI < Thor
  package_name "stairstep"

  class << self
    def exit_on_failure?
      true
    end
  end

  class_option("--debug", type: :boolean, desc: "Print out debugging information")

  desc "promote ENVIRONMENT", "promote to the given Heroku environment"
  long_desc <<~DESC
    You must run this script from within the git repository you plan to deploy from.
    If you do not specify a deploy commit it will try to deploy HEAD.

    You must have installed the heroku executable and authorized with Heroku.
    Run `heroku login` if you have not yet authorized with Heroku.

    This script will, by default, generate an annotated tag for the deploy,
    and push the tag to the `origin` remote.  You may disable this behavior.
  DESC
  method_option "--from", desc: "Environment to promote from (defaults to the conventional previous environment (e.g. staging <= demo))"
  method_option "--db-capture", type: :boolean, desc: "Capture a snapshot of the database before deploying"
  method_option "--downtime", type: :boolean, default: true, desc: "Bring down the site during deploy (NB: Only skip this for deploys with no migrations)"
  method_option "--tag", type: :boolean, default: true, desc: "Create a tag for the commit"
  def promote(environment)
    Stairstep::Promote.new(self, environment, options).run
  end
end

