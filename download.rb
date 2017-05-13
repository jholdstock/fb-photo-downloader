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
	PB.start elements.length

	elements.each_with_index do |element, i|
		begin
			element.location_once_scrolled_into_view
			element.click
		rescue
			sleep 0.5
			begin
				element.location_once_scrolled_into_view
				element.click
			rescue
				raise "element with text '#{element.text}' couldnt be clicked"
			end
		end

		sleep 1
		PB.increment
		break if $quick_mode and i >= $how_quick
	end
	PB.stop
end

def open_all_years
	puts "", "", "Opening all years..."
	@driver.get "https://m.facebook.com/#{@username}/allactivity?log_filter=cluster_200"
	async_elements = @driver.find_elements(:css => ".timeline > div > div .async_elem")
	async_elements.delete_if { |x| x.text !~ /^\d{4}$/ }

	async_elements.reverse!
	click_elements async_elements
end

def open_all_months
	puts "", "Opening all months..."
	async_elements = @driver.find_elements(:css => ".timeline > div > div .collapse")

	async_elements.delete_if { |x| x.text =~ /^\d{4}$/ }
	async_elements.delete_if { |x| x.text =~ /^No stories available$/ }

	async_elements.reverse!
	click_elements async_elements
end

def expand_months
	puts "", "Expanding months fully..."
	loop do
		async_elements = @driver.find_elements(:css => ".timeline > div > div > div > div .async_elem")

		break if async_elements.length == 0
		
		# todo this results in multiple progress bars because of the outer loop
		click_elements async_elements
	end
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
	PB.start photo_links.length
	downloaded = {}
	$skipped = []
	photo_links.each_with_index do |link, i|
		@driver.get link

		begin
			try_for_time {
				@driver.execute_script(
					"try {
						var x=document.getElementsByClassName('pagingReady');
						x[0].classList.add('pagingActivated');
					} catch(e) {
						var x = document.getElementsByClassName('fullScreenAvailable');
						x[0].classList.add('pagingActivated');
					}"
				)
			}

		try_for_time { 
			@driver.find_element(:xpath => "//span[@class='uiButtonText' and text() = 'Options']").click
		}

		try_for_time {
			@driver.find_element(:xpath => "//a[@data-action-type='download_photo']").click
		}

		time = @driver.find_element(:css, 'div > span > span > a > abbr').attribute("data-utime")

		time = Time.at(time.to_i)
		# todo dont use driver.title
		filename = time.to_date.to_s + " - " + @driver.title + " " + SecureRandom.hex(1)
		filename.gsub!("-", ':')
		filename.gsub!(/[^:0-9A-Za-z\s]/, '')
		filename.gsub!(":", '-')

		downloaded[link] = filename

		rescue
			$skipped.push link
		end

		PB.increment 

		break if $quick_mode and i >= $how_quick
	end
	PB.stop 

	return downloaded
end

def rename_files downloaded
	puts "Renaming files..."

	downloaded.each do |url, filename|
		renamed = false
		fbid = url[/\?fbid=(\d+)&/, 1]
		if fbid == nil
			fbid = url[/\.\d+\/(\d+)\/\?/, 1]
		end

		raise "Could not find fbid in #{url}" if fbid == nil
		Dir.foreach($output_dir) do |item|
			next if item == '.' or item == '..'
			if item.include? fbid
				ext = item[/(\.\w+)$/, 1]
				FileUtils.mv $output_dir+"/"+item, $output_dir+"/"+filename+ext
				renamed = true
				break
			end
		end

		raise "failed to rename image fbid=#{fbid} and url=#{url}" if renamed == false
	end
end

def delete_duplicates
	count = 0
	Dir.foreach($output_dir) do |item|
		next if item == '.' or item == '..'
		if item =~ /\d{4}_/
			FileUtils.rm $output_dir+"/"+item
			puts "    rm #{item}"
			count += 1
		end
	end
	return count
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
	sleep 3 # ensure all downloads are complete
	@driver.quit

	rename_files downloaded
	duplicates = delete_duplicates

	puts "    done", "", ""

	end_time = Time.now
	elapsed = end_time - beginning_time
	sec = elapsed % 60
	min = elapsed / 60
	puts "----------------------------",
		 "  Finished in #{min.floor} min #{sec.floor} sec",
		 "",
		 "     Downloaded #{downloaded.length} photos",
		 "     Deleted #{duplicates} duplicates",
		 "     Skipped #{$skipped.length}",
		 "",
		 "     " + `du -sh #{$output_dir}`,
		 "----------------------------",
		 "", ""
end

