#!/usr/bin/ruby

require 'set'
require 'yaml'
require 'fileutils'
require 'open3'
require_relative '../lib/config.rb'
require_relative '../lib/interaction.rb'
require_relative '../lib/helper.rb'
# override a method just loaded
def dbg text
  text
end

$sut = load_technical_config

def expect found, expected
  if found == expected
    puts "\e[32mOkay\e[0m"
  else
    puts "\e[31mNOT Okay\e[0m"
    puts "Expected '#{expected}' but found '#{found}'"
    exit 1
  end
end

def new_session
  kill_session
  sys "tmux -u new-session -d -x #{$sut[:term_min_width]} -y #{$sut[:term_min_height]} -s #{$sname}"
end

def kill_session
  system "tmux kill-session -t #{$sname} >/dev/null 2>&1"
end

Dir.chdir(%x(git rev-parse --show-toplevel).chomp) do

  puts "\nPreparing data"
  FileUtils.rm_r 'config/testing'
  FileUtils.cp_r 'config/richter', 'config/testing'
  
  puts "\nTesting auto-calibration"
  $sname = 'calib'
  new_session
  tms = "tmux send -t #{$sname}"
  tmsl = "tmux send -l -t #{$sname}"
  sys "#{tmsl} 'cd harp_scale_trainer'"
  sys "#{tms} ENTER"
  sys "#{tmsl} './harp_scale_trainer calib testing --auto --testing'"
  sys "#{tms} ENTER"
  sys "#{tms} ENTER"
  sleep 4
  
  result = %x(tmux capture-pane -t calib -p).lines.map!(&:chomp)
  kill_session
  
  expect result[-4], 'All recordings done.'
end
