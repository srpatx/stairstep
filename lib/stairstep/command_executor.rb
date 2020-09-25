# frozen_string_literal: true

require "open3"
require "stringio"
require_relative "../stairstep"

class Stairstep::CommandExecutor
  def execute(*command, message: nil, output: $stdout, progress: false, stdout_only: false)
    print("*** ")
    puts(message || command.join(" "))

    method = stdout_only ? :popen2 : :popen2e

    Open3.public_send(method, *command) do |_stdin, stdout, thread|
      while (line = stdout.gets)
        print(".") if progress
        output&.puts(line)
      end
      puts if progress

      thread.value.success?
    end
  end

  def execute!(*command, **options)
    raise "Command failed: `#{command.join(' ')}`" unless execute(*command, **options)
  end

  def fetch_stdout(exec, *command, **options)
    io = StringIO.new
    __send__(exec, *command, **options.merge(output: io, stdout_only: true))
    io.rewind
    io.read
  end
end

