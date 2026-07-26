#!/usr/bin/ruby
# -*- fill-column: 94 -*-

require 'byebug'

# Simple helper script to assist while converting harpwise' codebase to modules.

Dir.chdir(`git rev-parse --show-toplevel`.chomp)
counts = Hash.new {|h,k| h[k] = 0}
puts

scanfiles = Dir['libexec/*.rb']
counts[:files_to_scan] = scanfiles.length
checkfiles = ['harpwise', scanfiles].flatten
counts[:files_to_check] = checkfiles.length

fn2mod = Hash.new {|h,k| h[k] = []}
scanfiles.each do |sfile|
  puts "Scanning #{sfile}"
  mod_here = 'main'
  class_here = ''
  class_indent = ''
  File.readlines(sfile, chomp: true).each_with_index do |line, idx|

    # track module and class
    if line =~ /^(\s*)class\s+(\S+)(\s*|\s*<\s*\S+\s*)$/
      fail "Missed end of class #{class_here} while new class starts: ##{idx}: #{line}" if class_here != ''
      class_indent, class_here = $1, $2
      counts[:new_class] += 1
      pp line
    end
    if line =~ /^module\s+(\S+)\s*$/
      mod_here = $1
      counts[:new_module] += 1
      pp line
    end
    mod_here = 'main' if line =~ /^end/
    class_indent, class_here = '','' if line =~ /^#{class_indent}end\b/ || line =~ /^end\b/
    if class_here == '' && line =~ /^\s*def\s+(\w+)/
      fn = $1
      fail "Internal error with functions #{fn} not consisting of word chars entirely" unless fn =~ /^\w+$/
      fn2mod[fn] << mod_here
    end
  end
end

counts[:warning_self_no_class_found] += 1 if counts[:new_class] == 0
counts[:warning_self_no_module_found] += 1 if counts[:new_module] == 0
puts
mods = fn2mod.values.flatten.uniq

false_pos = ['space_to_cont: \'SPACE to continue ... \',',
             'journal_menu journal_current journal_play journal_delete',
             'journal_delete journal_menu journal_write',
             'puts_underlined "choose_interactive',
             'puts_underlined \'one_char',
             'end while $ctl_mic[:switch_modes]',
             'switch_modes toggle_record_user remote_message',
             '$ctl_mic[:switch_modes]',
             '$ctl_mic[:journal_menu]',
             'puts_underlined \'days_ago_in_words']

warned_functions = Set.new
checkfiles.each do |cfile|
  puts "Checking #{cfile}"
  mod_here = 'main'
  class_here = ''
  class_indent = ''
  lno = 0
  File.readlines(cfile, chomp: true).each_with_index do |line, idx|

    next if line =~ /^\s*#/
    next if line['require_relative']
    next if false_pos.any? {|fp| line[fp]}

    # track module and class
    if line =~ /^(\s*)class\s+(\S+)(\s*|\s*<\s*\S+\s*)$/
      fail "Missed end of class #{class_here} while new class starts: ##{idx}: #{line}" if class_here != ''
      class_indent, class_here = $1, $2
    end
    mod_here = $1 if line =~ /^module\s+(\S+)\s*$/
    mod_here = 'main' if line =~ /^end/
    class_indent, class_here = '','' if line =~ /^#{class_indent}end\b/ || line =~ /^end\b/    

    fn2mod.each do |fn, mods|
      
      if line =~ /\b#{fn}\b/ &&      # does function appear at all?
         !line["def #{fn}"]          # skip the def itself
        
        counts[:a_function_used] += 1
        
        if !(mods.include?('main') || # no qualification (never!) needed for functions from main
             (mods.include?(mod_here) && # qualified name mostly required outside of defining module
              (mod_here != 'Quiz' || # ... sure, when not quiz
               (mod_here == 'Quiz' && class_here == '')))) # special case for mod Quiz, which contains classes
          counts[:a_function_used_outside_its_module] += 1
          
          if !mods.any? {|mod| line["#{mod}::#{fn}"]}     # is it prefixed correctly?
            puts "\nWarning in file #{cfile}, line #{idx+1}: Invalid usage of function #{fn}\nfrom module #{mods} in this line:\n\n#{line}\n\n"
            counts[:warning_a_function_used_outside_but_not_prefixed_correctly] += 1
            warned_functions << [cfile, fn, fn2mod[fn]]
          end
        end
      end
    end
  end  
end

puts
puts "Modules:"
pp mods
counts[:num_of_functions] = fn2mod.keys.length
counts[:num_of_modules] = mods.length
puts "Counters:"
pp counts
puts "Warned functions:"
pp warned_functions.to_a.sort
puts "Warnings:"
pp counts.keys.map(&:to_s).select {|k| k['warning']}
puts

exval = counts.keys.map(&:to_s).any? {|k| k['warning']} ? 1 : 0
puts "exit value #{exval}"
puts
exit exval

