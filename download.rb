system "clear"

# ruby
require 'net/http'
require 'uri'
require 'pp'
require 'securerandom'
require 'fileutils'
require 'open-uri'

# gems
require 'progressbar'
require 'selenium-webdriver'
require 'highline/import'

# local
require './conf.rb'

class PB
	def self.start total
		return unless $progress_bars
		puts ""
		@@pbar = ProgressBar.create(:format => "%E |%w>%i| (%c / %C)",
									:progress_mark  => "=",
									:remainder_mark => " ",
									:total => total)
	end

	def self.increment
		return unless $progress_bars
		@@pbar.increment
	end

	def self.stop
		return unless $progress_bars
		@@pbar.finish
		puts "", ""
	end
end

def create_driver
	caps = Selenium::WebDriver::Remote::Capabilities.chrome(
	"chromeOptions" => {
		"args" => [
			"--disable-web-security",
			"--incognito"
		],
		'prefs' => {
			'download.default_directory' => $output_dir,
			'download.prompt_for_download' => false
        }
	})
	return Selenium::WebDriver.for :chrome, desired_capabilities: caps
end

def login
	puts "Opening Chrome... "
	@driver.get "https://www.facebook.com"
	puts "    done", "", ""


	puts "Entering user ID and password... "
	@driver.find_element(:id => "email").send_keys $email
	@driver.find_element(:id => "pass").send_keys $pass
	@driver.find_element(:id => "pass").send_keys :enter
	puts "    done", "", ""
end

def get_username
	puts "Getting account username... "
	@driver.get "https://www.facebook.com/settings?tab=account&section=username&view"
	@username = @driver.find_element(:css => "table.uiInfoTable input.inputtext")["value"]
	puts "    done (#{@username})", ""
end

def click_elements elements
	elements.each_with_index do |element, i|
		begin
			element.location_once_scrolled_into_view
			element.click
		rescue
			sleep 0.1
			pp element.text
			begin
				element.location_once_scrolled_into_view
				element.click
			rescue
				sleep 0.2
				pp element.text
				begin
					element.location_once_scrolled_into_view
					element.click
				rescue
					sleep 0.3
					pp element.text
					element.location_once_scrolled_into_view
					element.click
				end
			end
		end

		sleep 0.3
		PB.increment
		break if $quick_mode and i >= $how_quick
	end
end

def open_all_years
	puts "", "", "Opening all years..."
	@driver.get "https://m.facebook.com/#{@username}/allactivity?log_filter=cluster_200"
	async_elements = @driver.find_elements(:css => ".timeline > div > div .async_elem")

	async_elements.delete_if { |x| x.text !~ /^\d{4}$/ }

	PB.start async_elements.length
	click_elements async_elements
	PB.stop
end

def open_all_months
	puts "", "Opening all months..."
	async_elements = @driver.find_elements(:css => ".timeline > div > div .collapse")

	async_elements.delete_if { |x| x.text =~ /^\d{4}$/ }
	async_elements.delete_if { |x| x.text =~ /^No stories available$/ }

	PB.start async_elements.length
	click_elements async_elements
	PB.stop
end

def expand_months
	puts "", "Expanding months fully..."
	loop do
		async_elements = @driver.find_elements(:css => ".timeline > div > div > div > div .async_elem")
		async_elements.delete_if { |x| x.text.strip == "" }

		break if async_elements.length == 0
		
		# todo this results in multiple progress bars because of the outer loop
		PB.start async_elements.length
		click_elements async_elements
		$progress_bars_before = $progress_bars
		$progress_bars = false
	end
	$progress_bars = $progress_bars_before
	PB.stop
end

def scan_for_tags
	puts "", "Scanning page for tagged photos... "
	photo_links = @driver.find_elements(:xpath => "//div[@class='timeline']//a[text()='photo']")
	photo_links.collect! { |x| x.attribute("href") }
	puts "    Found #{photo_links.length} photos", "", ""
	return photo_links
end

def try_for_time
	start = Time.now
	loop do
		begin
			return yield
		rescue 
			raise "Timeout. Waited for #{$timeoutInSeconds} seconds" if (Time.now - start >= $timeoutInSeconds)
			sleep 0.2
		end
	end
end

def download_hq photo_links
	puts "", "Downloading high quality photos... "
	FileUtils.rm_rf($output_dir)
	Dir.mkdir($output_dir)
	hq_links = {}
	PB.start photo_links.length
	$skipped = []
	photo_links.each_with_index do |link, i|
		@driver.get link

		begin
			sleep 1 # this should make the skipping unnecessary

			# todo this still doesnt work!!!!
			try_for_time {
				@driver.execute_script(
					"var x=document.getElementsByClassName('pagingReady');
					x[0].classList.add('pagingActivated');"
				)
			}
		rescue
			$skipped.push link
			PB.increment
			next
		end

		try_for_time { 
			@driver.find_element(:xpath => "//span[@class='uiButtonText' and text() = 'Options']").click
		}

		try_for_time {
			@driver.find_element(:xpath => "//a[@data-action-type='download_photo']").click
		}

		time = @driver.find_element(:css, 'div > span > span > a > abbr').attribute("data-utime")

		time = Time.at(time.to_i)
		filename = time.to_date.to_s + " - " + @driver.title + " " + SecureRandom.hex(1)
		filename.gsub!("-", ':')
		filename.gsub!(/[^:0-9A-Za-z\s]/, '')
		filename.gsub!(":", '-')

		PB.increment 

		hq_links[link] = filename
		break if $quick_mode and i >= $how_quick
	end
	PB.stop 

	return hq_links
end

beginning_time = Time.now
@driver = create_driver
login
get_username
open_all_years
open_all_months
expand_months
photo_links = scan_for_tags
photo_links.each { |link| link.gsub! "https://m.", "https://www." }
begin
	downloaded = download_hq photo_links
ensure
	sleep 5 # ensure all downloads are complete
	@driver.quit
	puts "Renaming files..."



	downloaded.each do |url, filename|
		fbid = url[/\?fbid=(\d+)&/, 1]
		raise "Could not find fbid in #{url}" if fbid == nil
		Dir.foreach($output_dir) do |item|
			next if item == '.' or item == '..'
			raise "Could not find item #{item}" if item == nil
			if item.include? fbid
				ext = item[/(\.\w+)$/, 1]
				FileUtils.mv $output_dir+"/"+item, $output_dir+"/"+filename+ext
				break
			end
		end
	end

	puts "    done", "", ""

	end_time = Time.now
	elapsed = end_time - beginning_time
	sec = elapsed % 60
	min = elapsed / 60
	puts "----------------------------",
		 "  Finished in #{min.floor} min #{sec.floor} sec",
		 "",
		 "     Downloaded #{downloaded.length} photos",
		 "     Skipped #{$skipped.length}",
		 "",
		 "     " + `du -sh #{$output_dir}`,
		 "----------------------------",
		 "", ""
end

