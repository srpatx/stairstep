# frozen_string_literal: true

require "stairstep"
require "stairstep/command_executor"

class Stairstep::CommandExecutor
  class << self
    def reset!
      @commands = nil
    end

    def commands
      @commands ||= []
    end
  end

  def execute(*command_parts, **options)
    self.class.commands << [command_parts.join(" "), options]
  end
end

RSpec::Matchers.define(:execute_command) do |command|
  chain :with_options do |**options|
    @options = options
  end

  chain :once do
    @once = true
  end

  match do |action|
    Stairstep::CommandExecutor.reset!

    action.call

    @matches = Stairstep::CommandExecutor.commands.select { |(cmd, *)| cmd == command }
    @matches = @matches.select { |(_, options)| options == @options } if @options
    @once ? @matches.one? : @matches.any?
  end

  failure_message do
    <<~MSG
      expected to execute command:
      \t> #{[command, @options].compact}

      actual executions:
      #{Stairstep::CommandExecutor.commands.collect { |cmd| "\t> #{cmd}" }.join("\n")}
    MSG
  end
end

