require_relative "../stairstep"

class Stairstep::Logger
  def info(message)
    puts("\n", "=-" * 40)
    puts(message.upcase)
  end

  def warning(message)
    puts("\n", "?" * 80)
    puts(message.upcase)
  end

  def error(message, exception: nil)
    puts("\n", "!" * 80)
    if exception
      p(exception)
      raise if debug?
    end
    abort(message.upcase)
  end
end

