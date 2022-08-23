#
#  Utility functions for the maintainer or developer of harpwise
#

def do_develop to_handle

  tasks_allowed = %w(man diff)
  err "Can only do 1 task at a time, but not #{to_handle.length}; too many arguments: #{to_handle}" if to_handle.length > 1
  err "Unknown task #{to_handle[0]}, only these are allowed: #{tasks_allowed}" unless tasks_allowed.include?(to_handle[0])

  case to_handle[0]
  when 'man'
    task_man
  when 'diff'
    task_diff
  end
  
end


def task_man
  types_content = get_types_content
  
  File.write("#{$dirs[:install]}/man/harpwise.1",
             ERB.new(IO.read("#{$dirs[:install]}/resources/harpwise.man.erb")).result(binding).chomp)

  puts
  system("ls -l #{$dirs[:install]}/man/harpwise.1")
  puts "\nTo read it:\n\n  man -l #{$dirs[:install]}/man/harpwise.1\n\n"
end


def task_diff
  types_content = get_types_content
  seen = false

  lines = Hash.new
  line = Hash.new
  srcs = [:usage, :man]
  
  seen = {:desc => [/^DESCRIPTION$/, false],
          :prim_start => [/The primary documentation/, false],
          :prim_end => [/not available as man-pages/, false],
          :exa_start => [/^EXAMPLES$/, false],
          :exa_end => [/^COPYRIGHT$/, false]}
  
  erase_part = ['<hy>', '<beginning of page>']
  erase_line = %w(MODE ARGUMENTS OPTIONS)
  replaces = {'SUGGESTED READING' => 'SUGGESTED READING:'}

  #
  # Bring usage information and man page into canonical form
  #

  # keep everything
  lines[:usage] = ERB.new(IO.read("#{$dirs[:install]}/resources/usage.txt")).result(binding).lines.
                    map {|l| l.chomp.strip.downcase}.
                    reject(&:empty?)

  # remove disclaimer for the man-page or lines, which are added by groff
  lines[:man] = %x(groff -man -a -Tascii #{$dirs[:install]}/man/harpwise.1).lines.
                  map {|l| l.strip}.
                  # use only some sections of lines
                  map do |l|
                    newly_seen = false
                    seen.each do |k,v|
                      if l.strip.match?(v[0])
                        v[1] = true
                        newly_seen = true
                      end
                    end
                    if newly_seen
                      nil
                    elsif !seen[:desc][1]
                      nil
                    elsif seen[:prim_start][1] && !seen[:prim_end][1]
                      nil
                    elsif seen[:exa_start][1] && !seen[:exa_end][1]
                      nil
                    else
                      l
                    end
                  end.compact.
                  # erase and replace
                  map do |l|
                    erase_part.each {|e| l.gsub!(e,'')}
                    l
                  end.
                  map do |l|
                    erase_line.any? {|e| e == l.strip} ? nil : l
                  end.compact.
                  map {|l| replaces[l] || l}.
                  map {|l| l.strip.downcase}.reject(&:empty?).compact

  srcs.each {|s| line[s] = lines[s].shift}

  while srcs.all? {|s| lines[s].length > 0}
    clen = 0
    clen += 1 while line[:usage][clen] && line[:usage][clen] == line[:man][clen]
    if clen > 0
      srcs.each do |s|
        line[s][0, clen] = ''
        line[s].strip!
        line[s] = lines[s].shift.strip if line[s].empty?
      end
    else
      pp [line[:usage], line[:man]]
      fail "#{srcs} differ; see above"
    end
  end
end
