#!/usr/bin/env ruby
#
# Check your grades of the current semester
#
# Copyright (c) 2013 Michael Weibel <michael.weibel@gmail.com>
#
# License: MIT
#
# Requirements to use:
# Don't overload the HSR servers with the cronjob!
#

require './didipasshsr'

puts "Running DidIPassHSR scheduler task..."
runner = DidIPassHSR::Runner.new(ENV)
new_grades = runner.run()
puts "#{new_grades} new grades sent"