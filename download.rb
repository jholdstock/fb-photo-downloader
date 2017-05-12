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
		return if !@progress_bars
		puts ""
		@@pbar = ProgressBar.create(:format => "%E |%w>%i| (%c / %C)",
									:progress_mark  => "=",
									:remainder_mark => " ",
									:total => total)
	end

	def self.increment
		return if !@progress_bars
		@@pbar.increment
	end

	def self.stop
		return if !@progress_bars
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
			'download.default_directory' => @output_dir,
			'download.prompt_for_download' => true
        }
	})
	return Selenium::WebDriver.for :chrome, desired_capabilities: caps
end

def login
	print "", "Opening Chrome... "  
	@driver.get "https://www.facebook.com"
	puts "done\n", "", ""


	print "Entering user ID and password... "  
	@driver.find_element(:id => "email").send_keys @email
	@driver.find_element(:id => "pass").send_keys @pass
	@driver.find_element(:id => "pass").send_keys :enter
	puts "done\n", "", ""
end

def get_username
	print "Getting account username... "  
	@driver.get "https://www.facebook.com/settings?tab=account&section=username&view"
	@username = @driver.find_element(:css => "table.uiInfoTable input.inputtext")["value"]
	puts "done (#{@username})\n", ""
end

def click_elements elements
	elements.each_with_index do |element, i|
		element.location_once_scrolled_into_view
		begin
			element.click
		rescue
			sleep 0.1
			begin
				element.click
			rescue
				sleep 0.2
				begin
					element.click
				rescue
					sleep 0.3
					element.click
				end
			end
		end

		sleep 0.3
		PB.increment
		break if @quick_mode and i >= @how_quick
	end
end

def open_all_years
	puts "", "Open all years..."
	@driver.get "https://m.facebook.com/#{@username}/allactivity?log_filter=cluster_200"
	async_elements = @driver.find_elements(:css => ".timeline > div > div .async_elem")

	async_elements.delete_if { |x| x.text !~ /^\d{4}$/ }

	PB.start async_elements.length
	click_elements async_elements
	PB.stop
end

def open_all_months
	puts "", "Open all months..."
	async_elements = @driver.find_elements(:css => ".timeline > div > div .collapse")

	async_elements.delete_if { |x| x.text =~ /^\d{4}$/ }
	async_elements.delete_if { |x| x.text =~ /^No stories available$/ }

	PB.start async_elements.length
	click_elements async_elements
	PB.stop
end

def expand_months
	puts "", "Fully expand months..."
	loop do
		async_elements = @driver.find_elements(:css => ".timeline > div > div > div > div .async_elem")
		async_elements.delete_if { |x| x.text =~ /^No more from/ }
		break if async_elements.length == 0
		
		# todo this results in multiple progress bars because of the outer loop
		PB.start async_elements.length
		click_elements async_elements
		PB.stop
	end
end

def scan_for_tags
	puts "", "Scan page for tagged photos... "
	photo_links = @driver.find_elements(:xpath => "//div[@class='timeline']//a[text()='photo']")
	photo_links.collect! { |x| x.attribute("href") }
	puts "\t Found #{photo_links.length} photos", "", ""
	return photo_links
end

def try_for_time
	start = Time.now
	loop do
		begin
			return yield
		rescue 
			raise "Timeout. Waited for #{@timeoutInSeconds} seconds" if (Time.now - start >= @timeoutInSeconds)
			sleep 0.2
		end
	end
end

def download_hq photo_links
	puts "Downloading high quality photos... "
	hq_links = {}
	PB.start photo_links.length
	skipped = []
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
			skipped.push link
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

		break if @quick_mode and i >= @how_quick
	end
	PB.stop 

	if skipped.length > 0
		print "Skipped: " 
		pp skipped
		puts ""
	end

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
download_hq photo_links


end_time = Time.now
elapsed = end_time - beginning_time
sec = elapsed % 60
min = elapsed / 60
puts "--------------------------", " Finished in #{min.floor} min #{sec.floor} sec", "--------------------------", "", ""