require_relative "lib/stairstep/version"

Gem::Specification.new do |spec|
  spec.name = "stairstep"
  spec.version = Stairstep::VERSION
  spec.authors = ["SRP Developers"]
  spec.email = ["developers@srp-ok.com"]

  spec.summary = "Deploy a Rails application to Heroku"
  spec.homepage = "https://github.com/strongholdresourcepartners/stairstep"
  spec.license = "MIT"
  spec.required_ruby_version = Gem::Requirement.new(">= 3.2.0")

  spec.metadata["allowed_push_host"] = "TODO: Set to 'http://mygemserver.com'"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/strongholdresourcepartners/stairstep"
  spec.metadata["changelog_uri"] = "https://github.com/strongholdresourcepartners/stairstep/releases"
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    `git ls-files -z`.split("\x0").reject { |f| f.match(%r{^(spec|features)/}) }
  end
  spec.bindir = "bin"
  spec.executables = %w[stairstep]
  spec.require_paths = %w[lib]

  spec.add_dependency("thor", "~> 1.0")

  spec.add_development_dependency("rake")
  spec.add_development_dependency("rspec")
  spec.add_development_dependency("standard")
end
