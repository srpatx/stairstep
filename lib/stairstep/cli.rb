# frozen_string_literal: true

require "thor"
require_relative "../stairstep"
require_relative "../stairstep/deploy"
require_relative "../stairstep/promote"

class Stairstep::CLI < Thor
  package_name "stairstep"

  class << self
    def exit_on_failure?
      true
    end
  end

  class_option("--debug", type: :boolean, desc: "Print out debugging information")

  desc "deploy ENVIRONMENT", "deploy a specific commit to the given Heroku environment"
  long_desc <<~DESC
    You must run this script from within the git repository you plan to deploy from.
    If you do not specify a deploy commit it will try to deploy HEAD.

    You must have installed the heroku executable and authorized with Heroku.
    Run `heroku login` if you have not yet authorized with Heroku.

    This script will, by default, precompile assets, package gems, and create a
    commit for the results of each.  You may disable either or both actions by
    specifying options (see below).

    This script will also, by default, generate an annotated tag for the deploy,
    and push the tag to the `origin` remote.  You may also disable this behavior.
  DESC
  method_option "--commit", alias: "-C", desc: "The commit to deploy"
  method_option "--force", alias: "-f", type: :boolean, desc: "Force a non-fast-forward deploy"
  method_option "--db-capture", type: :boolean, desc: "Capture a snapshot of the database before deploying"
  method_option "--downtime", type: :boolean, default: true, desc: "Bring down the site during deploy (NB: Only skip this for deploys with no migrations)"
  method_option "--assets-precompile", type: :boolean, default: false, desc: "Create a commit for precompiled assets"
  method_option "--bundle-package", type: :boolean, default: false, desc: "Create a commit for packaged gems"
  method_option "--tag", type: :boolean, default: true, desc: "Create a tag for the commit"
  method_option "--development", type: :boolean, desc: "Combine --no-assets-precompile, --no-bundle-package, and --no-tag"
  def deploy(environment)
    Stairstep::Deploy.new(self, environment, options).run
  end

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

