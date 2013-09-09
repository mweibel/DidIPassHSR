#!/usr/bin/env ruby
# -*- coding: utf-8 -*-
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
require 'logger'
require 'json'

Bundler.require(:default, (ENV['RACK_ENV'] ||= :development.to_s).to_sym)

module DidIPassHSR

	class Runner
		attr_accessor :notifier
		attr_accessor :cache

		SEMESTER_XPATH = '//div[@id="14xB_gr"]/table[1]//tr[2]/td[1]/table//tr[7]/td[2]/div'

		LOGIN_URL = 'https://adfs.hsr.ch/adfs/ls/?wa=wsignin1.0&wtrealm=https%3a%2f%2funterricht.hsr.ch%3a443%2f&wctx=https%3a%2f%2funterricht.hsr.ch%2f'
		REPORT_URL = 'https://unterricht.hsr.ch/MyStudy/Reporting/TermReport'

		def initialize(env)
			@env = env

			if env['LOGDEV']
				@log = Logger.new(env['LOGDEV'])
			else
				@log = Logger.new(STDOUT)
			end
			if env['LOG_SEVERITY']
				@log.level = env['LOG_SEVERITY']
			else
				@log.level = Logger::INFO
			end

			if not env['DRY_RUN']
				abort 'ERROR: NOTIFIER not set.' unless env['NOTIFIER']

				@notifier = Notifiers.const_get("#{env['NOTIFIER']}Notifier").new(env, @log)
			else
				@notifier = Notifiers::DummyNotifier.new(env, @log)
			end

			abort 'ERROR: CACHE not set.' unless env['CACHE']
			@cache = Cache.const_get("#{env['CACHE']}Cache").new(env, @log)
			@mechanize_agent = Mechanize.new
		end

		def run()
			abort 'ERROR: HSR_USERNAME not set.' unless @env['HSR_USERNAME']
			abort 'ERROR: HSR_PASSWORD not set.' unless @env['HSR_PASSWORD']

			@mechanize_agent.add_auth(LOGIN_URL, @env['HSR_USERNAME'], @env['HSR_PASSWORD'])
			begin
				@mechanize_agent.get(LOGIN_URL) do |page|
					@log.info "Loaded Page..."
					login(page)
					report = fetch_report()
					semester, grades = parse(report)
					return notify(semester, grades)
				end
			rescue OpenSSL::SSL::SSLError => e
				@log.error "Could not load the login url due to an SSL verify error."
				@log.error "Please specify a correct SSL_CERT_FILE env variable."
				@log.error "In case you're using OSX: brew install curl-ca-bundle."
				@log.error "Full message & stacktrace follow:"
				@log.error e.message
				e.backtrace.each { |line| logger.error line }
			end
		end

		def login(page)
			@log.info "Logging in..."
			form = page.form('aspnetForm')
			if form
				form['ctl00$ContentPlaceHolder1$UsernameTextBox'] = @env['HSR_USERNAME']
				form['ctl00$ContentPlaceHolder1$PasswordTextBox'] = @env['HSR_PASSWORD']
				@mechanize_agent.submit(form, form.buttons.first)
			end
		end

		def login_hiddenform(page)
			# ?? I don't know why but yes, that's how it works.
			form = page.form('hiddenform')
			if form
				@mechanize_agent.submit(form, form.buttons.first)
			end
		end

		def fetch_report()
			@log.info "Fetching report..."
			page = @mechanize_agent.get(REPORT_URL)
			login_hiddenform(page)
		end

		def parse(report)
			@log.info "Parsing report..."
			semester = report.search(SEMESTER_XPATH).text
			semester = semester.gsub(/[\r\n\t ]/, '').gsub(/[^a-zA-Z0-9]/u, '-')

			grades = {}
			report.search("div:contains('Übersicht Module')").last.parent.parent.parent.search('tr')[3..-3].each do |tr|
				tds = tr.search('td')
				description = tds[2].search('div/div/div/a').text
				grade = tds[3].children.text || tds[3].children[0].text
				grade = grade.gsub(/[^*a-zA-Z0-9.]/, '')

				# ugly fix for BN and nBN grades
				if grade == '*BN'
					grade = "6.0"
				elsif grade == '*nBN'
					grade = "1.0"
				end

				grades[description] = grade
			end

			return semester, grades
		end

		def notify(semester, grades)
			@log.info "Notifying..."
			notified = 0
			sem_cache = @cache.get(semester)
			grades.each do |desc, new_grade|
				cached_grade = sem_cache[desc]
				if (not cached_grade or cached_grade == "***") and new_grade != "***" and new_grade != cached_grade
					new_grade = new_grade.to_f
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
			def initialize(env, log)
				raise NotImplementedError
			end

			def get(semester)
				raise NotImplementedError
			end

			def set(semester, grades)
				raise NotImplementedError
			end

			def flush
				raise NotImplementedError
			end
		end

		class DummyCache < Interface
			def initialize(env, log)
				@cache = {}
				@log = log
			end

			def get(semester)
				return @cache[semester] || {}
			end

			def set(semester, grades)
				@cache[semester] = grades
			end

			def flush
				@cache = {}
			end
		end

		class FileCache < Interface
			def initialize(env, log)
				@log = log

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

			def flush
				require 'fileutils'
				FileUtils.rm_rf(File.join(@path, "."), secure: true)
			end
		end

		class RedisCache < Interface
			require 'redis'

			def initialize(env, log)
				@log = log
				uri = URI.parse(ENV['REDISTOGO_URL'] || ENV['REDISCLOUD_URL'] || ENV['MYREDIS_URL'] || 'http://localhost:6379')
				@cache = Redis.new(:host => uri.host, :port => uri.port, :password => uri.password)
			end

			def get(semester)
				cached = @cache.get(semester)
				if cached != nil
					return JSON.parse(cached)
				end
				return {}
			end

			def set(semester, grades)
				ret = @cache.set(semester, grades.to_json())
				return ret
			end

			def flush
				@cache.flushall
			end
		end
	end

	module Notifiers
		class Interface
			def initialize(env, log)
				raise NotImplementedError
			end

			def notify(semester, grade)
				raise NotImplementedError
			end
		end

		class DummyNotifier < Interface
			def initialize(env, log)
				@log = log
				@log.info ""
			end

			def notify(desc, grade)
				@log.info "#{desc} - #{grade}"
			end
		end


		class ProwlNotifier < Interface
			require 'prowl'

			def initialize(env, log)
				@log = log
				abort 'ERROR: PROWL_API_KEY not set.' unless env['PROWL_API_KEY']

				@p = Prowl.new(:apikey => env['PROWL_API_KEY'], :application => 'Did I Pass')

				abort 'Invalid PROWL_API_KEY' unless @p.valid?
			end

			def notify(desc, grade)
				if grade < 4
					event = 'NAY!'
				elsif grade >= 5
					event = 'WOW!'
				else
					event = 'YAY!'
				end

				description = "#{desc} - #{grade}"

				@p.add(:event => event, :description => description)
			end
		end

		class EmailNotifier < Interface
			require 'mail'

			def initialize(env, log)
				@log = log
				abort 'Error: NOTIFICATION_EMAIL variable not set' unless ENV['NOTIFICATION_EMAIL']
				Mail.defaults do
					delivery_method :smtp, { :address => 'smtp.sendgrid.net',
											 :port => 587,
											 :authentication => 'plain',
											 :user_name => ENV['SENDGRID_USERNAME'],
											 :password => ENV['SENDGRID_PASSWORD'],
											 :domain => 'heroku.com',
											 :enable_starttls_auto => true }
				end
			end

			def notify(desc, grade)
				if grade < 4
					subj = 'NAY!'
				elsif grade > 5
					subj = 'WOW!'
				else
					subj = 'YAY!'
				end

				body_text = "Module '#{desc}' - Grade #{grade}.\n\nSee #{Runner::REPORT_URL} for more."
				body_html = "<b>Module <i>#{desc}</i> - Grade #{grade}.</b><br/>\n<br/>\nSee <a href='#{Runner::REPORT_URL}'>the report</a> for more infos."

				mail = Mail.deliver do
					to ENV['NOTIFICATION_EMAIL']
					from 'Did I Pass <michael.weibel+didipass@gmail.com>'
					subject "[DidIPass] #{subj}"
					text_part do
						body body_text
					end
					html_part do
						content_type 'text/html; charset=UTF-8'
						body body_html
					end
				end
				@log.info "Email probably sent."
			end
		end
	end
end
