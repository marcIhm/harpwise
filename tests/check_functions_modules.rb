#!/usr/bin/ruby
# -*- fill-column: 94 -*-

require 'byebug'
require 'prism'

# Simple helper script to assist while converting harpwise' codebase to modules.

# For every function (not methods!) defined in ourcode, it checks that calls for this name
# resolves correctly (e.g. beeing prefixed with the right module).  This gives no false
# positive as long we dont define functions with known names (e.g. "select")

class DefVisitor < Prism::Visitor
  def visit_def_node(node)
    $defs[node.name] << [$mod_here, $class_here, node.name]
    super
  end
  def visit_module_node(node)
    $mod_here = node.name
    super
    $mod_here = ''
  end
  def visit_class_node(node)
    $class_here = node.name
    super
    $class_here = ''
  end
end

class CallVisitor < Prism::Visitor
  def visit_call_node(node)
    if $defs[node.name] && node.call_operator_loc && node.call_operator_loc.slice != '.'
      $numchecked += 1
      wrongs = $defs[node.name].map do |df|
        catch :wrong do
          if node.receiver.class == Prism::ConstantReadNode
            # call prefixed with constant
            throw :wrong, "case 1, defined was #{df} but call is #{[node.receiver.name, nil, node.name]}\n" + node.inspect if df[0] != node.receiver.name
          elsif node.receiver.class == Prism::ConstantPathNode
            # special case e.g. ::Players::play_holes_or_notes_and_handle_kb
            throw :wrong, "case 2, defined was #{df} but call is #{[node.receiver.child.name, nil, node.name]}\n" + node.inspect if df[0] != node.receiver.child.name
          else
            # call without prefix
            throw :wrong, "case 3, defined was #{df} but call is #{[nil, nil, node.name]}\n" + node.inspect if df[0] != '' && df[0] != $mod_here
          end
          nil
        end
      end.compact
      if wrongs.length > 0 && wrongs.length == $defs[node.name].length
        puts "\n\nWrong call at '#{node.location.slice}' in #{$file_here}, line #{node.location.start_line}\nmatches none of #{$defs[node.name].length} defines:"
        wrongs.each {|w| puts w}
        $wrongs += 1
      end
    end
    super
  end
  def visit_module_node(node)
    $mod_here = node.name
    super
    $mod_here = ''
  end
  def visit_class_node(node)
    $class_here = node.name
    super
    $class_here = ''
  end
end

Dir.chdir(`git rev-parse --show-toplevel`.chomp)
checkfiles = ['harpwise', Dir['libexec/*.rb']].flatten

puts
puts "Collecting defs:"
$defs = Hash.new {|h,k| h[k] = Array.new}
$mod_here = ''
$class_here = ''
checkfiles.each do |cfile|
  puts '  ' + cfile
  $file_here = cfile
  tree = Prism.parse_file(cfile)
  tree.value.accept(DefVisitor.new)
end
puts "#{$defs.keys.length} defs"

puts
puts "Checking calls:"
$mod_here = ''
$class_here = ''
$wrongs = 0
$numchecked = 0
checkfiles.each do |cfile|
  puts '  ' + cfile
  $file_here = cfile
  tree = Prism.parse_file(cfile)
  tree.value.accept(CallVisitor.new)
end
puts "#{$numchecked} calls"

exval = $wrongs > 0 ? 1 : 0
puts
puts "Number of wrong calls is #{$wrongs}, exit value #{exval}"
puts
exit exval
