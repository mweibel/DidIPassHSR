#!/usr/bin/env ruby
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

require 'rubygems'
require 'bundler'
require 'nokogiri'
require './didipasshsr'

Bundler.require(:default, (ENV['RACK_ENV'] ||= :test.to_s).to_sym)

TEST_GRADES = {
	'Test 1 for DidIPassHSR' => '***',
	'Test 2 for DidIPassHSR' => '5.5',
	'Test 3 for DidIPassHSR' => '4.5',
	'Test 4 for DidIPassHSR' => '3.0'
}
TEST_SEMESTER = 'TestSemester'

runner = DidIPassHSR::Runner.new(ENV)
# clear cache
runner.cache.flush

#
# You think this is ugly or not a valid test? Contribute.
#
def test_parse(runner)
	puts "Test Parse...."

	html = File.read(File.join(Dir.pwd, 'test', 'Semesterreport.html'))

	page = Nokogiri::HTML::Document.parse(html)

	semester, new_grades = runner.parse(page)

	if semester == TEST_SEMESTER and TEST_GRADES == new_grades
		puts 'SUCCESS'
	else
		puts 'FAIL'
	end

	puts "\n"
end


def test_notify(runner, expected)
	puts "Test Notify..."

	num_grades = runner.notify(TEST_SEMESTER, TEST_GRADES)
	if num_grades ==  expected
		puts 'SUCCESS'
	else
		puts 'FAIL'
	end
	if expected > 0
		puts "\n"
		puts 'You may want to check the recipient now.'
	end
	puts "\n"
	return num_grades
end

def test_cache(runner)
	puts "Test cache (calling Test notify with expected = 0)..."

	test_notify(runner, 0)
end

# run it
test_parse(runner)
test_notify(runner, 3)
test_cache(runner)
