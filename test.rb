#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
#
# Dummy test
#
# Copyright (c) 2013 Michael Weibel <michael.weibel@gmail.com>
#
# License: MIT
#
# Requirements to use:
# Don't overload the HSR servers with the cronjob!
#
# To run, invoke `ruby test.rb`
#

require 'nokogiri'
require 'test/unit'
require './didipasshsr'

class DidIPassHSRTest < Test::Unit::TestCase
	TEST_GRADES = {
		'Test 1 for DidIPassHSR' => '****',
		'Test 2 for DidIPassHSR' => '5.5',
		'Test 3 for DidIPassHSR' => '4.5',
		'Test 4 for DidIPassHSR' => '3.0',
		'Test 5 for DidIPassHSR' => '6.0',
		'Test 6 for DidIPassHSR' => '1.0',
	}
	TEST_SEMESTER = 'TestSemester'
	LOGDEV = RUBY_PLATFORM =~ /mswin|mingw/ ? 'NUL:' : '/dev/null'
	MY_ENV = {
		'CACHE' => 'Dummy',
		'CACHE_PATH' => './.test-cache',
		'NOTIFIER' => 'Dummy',
		'LOGDEV' => LOGDEV
	}

	def setup
		@runner = DidIPassHSR::Runner.new(MY_ENV)
	end

	def test_parse
		html = File.read(File.join(Dir.pwd, 'test', 'Semesterreport.html'))

		page = Nokogiri::HTML::Document.parse(html)

		semester, new_grades = @runner.parse(page)

		assert_equal TEST_SEMESTER, semester, "Semester is not equal to TEST_SEMESTER"
		assert_equal TEST_GRADES, new_grades, "Grades are not equal to TEST_GRADES"
	end

	def test_notify_and_cache
		assert_equal 5, _notifier, "Number of sent notifications are not correct"
		assert_equal 0, _notifier, "All notifications should be cached now"
	end


	def _notifier
		num_grades = @runner.notify(TEST_SEMESTER, TEST_GRADES)
	end
end