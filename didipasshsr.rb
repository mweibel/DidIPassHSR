#!/usr/bin/env ruby
#
# Check your grades of the current semester
#
# Copyright (c) 2013 Michael Weibel <michael.weibel@gmail.com>
#
# Special thanks to @pstadler for the scheduler setup :)
#
# License: MIT
#
# Requirements to use:
# Don't overload the HSR servers with the cronjob!
#
require 'rubygems'
require 'bundler'
require 'JSON'

Bundler.require(:default, (ENV['RACK_ENV'] ||= :development.to_s).to_sym)

module DidIPassHSR

	class Runner
		SEMESTER_XPATH = '//div[@id="13xB_gr"]/table[1]/tr[2]/td[1]/table/tr[7]/td[2]/div'
		GRADES_XPATH = '//div[@id="13xB_gr"]/table[1]/tr[4]/td[1]/table/tr'

		LOGIN_URL = 'https://adfs.hsr.ch/adfs/ls/?wa=wsignin1.0&wtrealm=https%3a%2f%2funterricht.hsr.ch%3a443%2f&wctx=https%3a%2f%2funterricht.hsr.ch%2f'
		REPORT_URL = 'https://unterricht.hsr.ch/MyStudy/Reporting/TermReport'

		def initialize(env)
			@env = env
			if not env['DRY_RUN']
				@notifier = Notifiers.const_get("#{env['NOTIFIER']}Notifier").new(env)
				abort 'Error: Invalid Notifier' if not @notifier.valid?
			else
				@notifier = Notifiers::DryNotifier.new(env)
			end

			@cache = Cache.const_get("#{env['CACHE']}Cache").new(env)
			@mechanize_agent = Mechanize.new
		end

		def run()
			@mechanize_agent.add_auth(LOGIN_URL, @env['HSR_USERNAME'], @env['HSR_PASSWORD'])
			@mechanize_agent.get(LOGIN_URL) do |page|
				login(page)
				report = fetch_report()
				semester, grades = parse(report)
				return notify(semester, grades)
			end
		end

		def login(page)
			form = page.form('hiddenform')
			if form
				form['ctl00_ContentPlaceHolder1_UsernameTextBox'] = @env['HSR_USERNAME']
				form['ctl00_ContentPlaceHolder1_PasswordTextBox'] = @env['HSR_PASSWORD']

				@mechanize_agent.submit(form, form.buttons.first)
			end
		end

		def fetch_report()
			return @mechanize_agent.get(REPORT_URL)
		end

		def parse(report)
			# could be beautified, but firebug's xpath copy function is so useful
			semester = report.search(SEMESTER_XPATH).text
			semester = semester.gsub(/[^a-zA-Z0-9]/u, '-')

			grades = {}
			report.search(GRADES_XPATH)[3..-3].each do |tr|
				tds = tr.search('td')
				description = tds[2].search('div/div/div/a').text
				grade = tds[3].children[0].text
				grades[description] = grade
			end

			return semester, grades
		end

		def notify(semester, grades)
			notified = 0
			sem_cache = @cache.get(semester)
			grades.each do |desc, new_grade|
				cached_grade = sem_cache[desc]
				if (not cached_grade or cached_grade == "***") and new_grade != "***"
					@notifier.notify(desc, new_grade)
					sem_cache[desc] = new_grade
					notified += 1
				end
			end
			@cache.set(semester, sem_cache)

			return notified
		end
	end

	module Cache
		class Interface
			def initialize(env)
				raise NotImplementedError
			end

			def get(semester)
				raise NotImplementedError
			end

			def set(semester, grades)
				raise NotImplementedError
			end
		end

		class FileCache < Interface
			def initialize(env)
				if not env['CACHE_PATH']
					@path = File.join(Dir.pwd, ".cache")
				else
					@path = env['CACHE_PATH']
				end
				if not Dir.exists?(@path)
					Dir.mkdir(@path)
				end
			end

			def get(semester)
				filename = File.join(@path, "#{semester}.cache")
				if not File.exists?(filename)
					return {}
				end
				file = File.open(filename)

				grades = {}
				while (line = file.gets)
					desc, grade = line.split("::")
					grades[desc] = grade
				end
				file.close

				return grades
			end

			def set(semester, grades)
				file = File.open(File.join(@path, "#{semester}.cache"), "w")
				grades.each do |desc, grade|
					file.write("#{desc}::#{grade}\n")
				end
				file.close
			end
		end

		class RedisCache < Interface

			def initialize(env)
				uri = URI.parse(ENV['REDISTOGO_URL'] || ENV['REDISCLOUD_URL'] || ENV['MYREDIS_URL'] || 'http://localhost:6379')
				@cache = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
			end

			def get(semester)
				cached = @cache.get(semester)
				if cached != nil
					JSON.parse(cached)
				end
				return {}
			end

			def set(semester, grades)
				return @cache.set(semester, grades.to_json())
			end
		end
	end

	module Notifiers
		class Interface
			def initialize(env)
				raise NotImplementedError
			end

			def valid?
				raise NotImplementedError
			end

			def notify(semester, grade)
				raise NotImplementedError
			end
		end

		class DryNotifier < Interface
			def initialize(env)
				puts "Dry run..."
			end

			def valid?
				return true
			end

			def notify(semester, grade)
				puts "#{semester} - #{grade}"
			end
		end


		class ProwlNotifier < Interface

			def initialize(env)
				@p = Prowl.new(:apikey => env['PROWL_API_KEY'], :application => 'Did I Pass')
			end

			def valid?
				return @p.valid?
			end

			def notify(semester, grade)
				if grade < 4
					event = 'NAY!'
				elsif grade > 5
					event = 'WOW!'
				else
					event = 'YAY!'
				end

				description = "#{semester} - #{grade}"

				@p.add(:event => event, :description => description)
			end
		end
	end
end
