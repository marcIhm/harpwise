#
#  Utility functions for the maintainer or developer of harpwise
#

def do_develop to_handle

  tasks_allowed = %w(man)
  err "Can only do 1 task at a time, but not #{to_handle.length}; too many arguments: #{to_handle}" if to_handle.length > 1
  err "Unknown task #{to_handle[0]}, only these are allowed: #{tasks_allowed}" unless tasks_allowed.include?(to_handle[0])

  case to_handle[0]
  when 'man'
    task_man
  end
  
end


def task_man
  puts 'foo'
  puts ERB.new(IO.read("#{$dirs[:install]}/resources/harpwise.man")).result(binding).chomp  
end
