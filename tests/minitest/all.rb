#!/usr/bin/env ruby

require "minitest/autorun"
require 'set'
require 'yaml'
require 'json'
require 'fileutils'
require 'open3'
require 'tmpdir'
require 'erb'
require 'timeout'
require 'tempfile'
require 'strscan'
require 'pp'  ## for pretty_inspect
require 'csv'
require 'date'
require_relative '../../libexec/utils'
require_relative '../../libexec/arguments'
require_relative '../../libexec/config'
require_relative '../../libexec/interaction'
require_relative '../../libexec/players'
require_relative '../../libexec/sound_driver'
require_relative '../../libexec/analyze'
require_relative '../../libexec/licks'
require_relative '../../libexec/handle_holes'
require_relative '../../libexec/mode_listen'
require_relative '../../libexec/mode_licks'
require_relative '../../libexec/mode_play'
require_relative '../../libexec/mode_print'
require_relative '../../libexec/mode_samples'
require_relative '../../libexec/mode_tools'
require_relative '../../libexec/mode_quiz'
require_relative '../../libexec/mode_develop'
require_relative '../../libexec/mode_jamming'

class GeneralTest < Minitest::Test
  # Group tests by modules
  
  Cfg.set_global_vars_early
  
  def test_utils
    assert_equal 'yesterday', days_ago_in_words(1)
    assert_equal '10 weeks ago', days_ago_in_words(73)
  end

  def test_theory
    assert_equal %w[bs4 cs4 d4 ds4 ff4 es4 fs4 g4 gs4 a4 as4 cf4].map {|n| note2semi(n, shadowed: true)},
                 (-9 .. 2).to_a
  end
end
