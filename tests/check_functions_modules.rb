#!/usr/bin/ruby
# -*- fill-column: 94 -*-

# Simple helper script to assist while converting harpwise' codebase to modules.

Dir.chdir(`git rev-parse --show-toplevel`.chomp)

scanfiles = Dir['libexec/*.rb']
checkfiles = ['harpwise', scanfiles].flatten

puts
puts "#{scanfiles.length} files to scan for modules"
puts "#{checkfiles.length} files to check for functions beeing prefixed with modules"
puts

fn2mod = Hash.new
scanfiles.each do |sfile|
  puts "Scanning #{sfile}"
  mod_here = 'main'
  in_class = false
  File.readlines(sfile, chomp: true).each do |line|
    in_class = true if line =~ /^class\s+/
    mod_here = $1 if line =~ /^module\s+(\S+)\s*$/
    mod_here = 'main' if line =~ /^end/
    in_class = false if line =~ /^end/
    if !in_class && line =~ /^\s*def\s+(\w+)/
      fn = $1
      fail "Internal error with functions #{fn} not consisting of word chars entirely" unless fn =~ /^\w+$/
      fail "Function #{fn} appears in module #{mod_here}, but has already appeared in module #{fn2mod[fn]}" if fn2mod[fn]
      fn2mod[fn] = mod_here
    end
  end
end

puts
mods = fn2mod.values.uniq
puts "Found #{fn2mod.keys.length} functions from #{mods.length} modules."
pp mods
puts

counts = Hash.new {|h,k| h[k] = 0}
checkfiles.each do |cfile|
  puts "Checking #{cfile}"
  mod_here = 'main'
  lno = 0
  File.readlines(cfile, chomp: true).each do |line|
    lno += 1
    mod_here = $1 if line =~ /^module\s+(\S+)\s*$/
    mod_here = 'main' if line =~ /^end/
    next if line =~ /^\s*#/
    next if line['require_relative']

    fn2mod.each do |fn,mod|

      if line =~ /\b#{fn}\b/ &&      # does function appear at all?
         !line["def #{fn}"]          # skip the def itself

        counts[:a_function_used] += 1

        if mod != 'main' &&          # no qualification needed in main
           mod != mod_here           # qualified name only required outside of defining module

          counts[:a_function_used_outside_its_module] += 1

          if !line["#{mod}::#{fn}"]      # is it prefixed correctly?
            puts "\nWarning in file #{cfile}, line #{lno}: Invalid usage of function #{fn}\nfrom module #{mod} in this line:\n\n#{line}\n\n"
            counts[:warning_a_function_used_outside_but_not_prefixed_correctly] += 1
          end
        end
      end
    end
  end  
end

puts
pp counts
puts

exval = counts.keys.map(&:to_s).any? {|k| k['warning']} ? 1 : 0
puts "exit value #{exval}"
puts
exit exval

