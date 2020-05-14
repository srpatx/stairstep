# frozen_string_literal: true

require "thor"
require_relative "../stairstep"

class Stairstep::CLI < Thor
  package_name "stairstep"

  class << self
    def exit_on_failure?
      true
    end
  end
end

