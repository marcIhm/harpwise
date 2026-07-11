#!/usr/bin/env ruby

require "minitest/autorun"
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
  def setup
  end
  
  def test_utils
    assert_equal 'yesterday', days_ago_in_words(1)
  end
end
