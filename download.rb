require 'net/http'
require 'uri'
require 'progressbar'
require 'selenium-webdriver'
require 'pp'
require 'securerandom'
require 'fileutils'
require 'open-uri'

require './conf.rb'

class PB
	def self.start total
		puts ""
		@@pbar = ProgressBar.create(:format => "%E |%w>%i| (%c / %C)",
									:progress_mark  => "=",
									:remainder_mark => " ",
									:total => total)
	end

	def self.increment
		@@pbar.increment
	end

	def self.stop
		@@pbar.finish
		puts "", ""
	end
end

def download_files hq_links
	puts "", "Download HQ photos... "
	PB.start hq_links.length
	hq_links.each do |filename, url|
		filename = "#{@output_dir}/#{filename}.jpg"

		open(filename, 'wb') do |file|
			file << open(url).read
		end

		PB.increment
	end
	PB.stop
end

def create_driver
	caps = Selenium::WebDriver::Remote::Capabilities.chrome(
	"chromeOptions" => {
		"args" => [
			"--disable-web-security",
			"--incognito"
		],
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

def open_all_years
	puts "", "Open all years..."
	@driver.get "https://m.facebook.com/#{@username}/allactivity?log_filter=cluster_200"
	async_elements = @driver.find_elements(:css => ".timeline > div > div .async_elem")
	PB.start async_elements.length
	async_elements.each_with_index do |element, i|
		text = element.text
		next if text !~ /^\d{4}$/
		element.click
		#debug puts "\t#{text}"
		sleep 0.5
		PB.increment
		break if @quick_mode and i >=2
	end
	PB.stop
end

def open_all_months
	puts "", "Open all months..."
	async_elements = @driver.find_elements(:css => ".timeline > div > div .collapse")

# I think this is a breaking change. Only found 332 photos running like this. Missing or dupes?
	async_elements.delete_if { |x| x.text =~ /^\d{4}$/ }
	async_elements.delete_if { |x| x.text =~ /^No stories available$/ }


	PB.start async_elements.length
	async_elements.each_with_index do |element, i|
		text = element.text
		element.click
		#debug puts "\t#{text}"
		sleep 0.5
		PB.increment 
		break if @quick_mode and i >=2
	end
	PB.stop
end


def expand_months
	puts "", "Fully expand months..."
	loop do
		async_elements = @driver.find_elements(:css => ".timeline > div > div > div > div .async_elem")
		async_elements.delete_if { |x| x.text =~ /^No more from/ }
		break if async_elements.length == 0
		
		PB.start async_elements.length
		async_elements.each_with_index do |element, i|
			text = element.text
			element.click
			# debug puts "\t#{text}"
			sleep 0.5
			PB.increment
		end
		PB.stop
	end
end

def scan_for_tags
	puts "", "Scan page for tags... "
	photo_links = @driver.find_elements(:xpath => "//div[@class='timeline']//a[text()='photo']")
	photo_links.collect! { |x| x.attribute("href") }
	puts "\t Tagged in #{photo_links.length} photos", "", ""    
	return photo_links
end

def get_hq_links photo_links
	puts "", "Get HQ photo links... "
	hq_links = {}
	PB.start photo_links.length
	photo_links.each_with_index do |link, i|
		@driver.get link
		img_url = @driver.find_element(:xpath, './/a[contains(., "View full size")]').attribute("href")
		json = @driver.find_element(:css, 'div > span > div > div > abbr').attribute("data-store")
		name = @driver.find_element(:css, 'div > div > a > strong.actor').text
		json_hash = JSON.parse json
		time = json_hash["time"]
		time = Time.at(time)
		filename = time.to_date.to_s + " " + name + " - " + @driver.title + " " + SecureRandom.hex(1)
		filename.gsub!("-", ':')
		filename.gsub!(/[^:0-9A-Za-z\s]/, '')
		filename.gsub!(":", '-')
		hq_links[filename] = img_url
		PB.increment 
		break if @quick_mode and i >=10
	end
	PB.stop 
	return hq_links
end

@driver = create_driver
login
get_username
open_all_years
open_all_months
expand_months

photo_links = scan_for_tags
hq_photo_links = get_hq_links photo_links

FileUtils.rm_rf(@output_dir)
Dir.mkdir(@output_dir)

download_files hq_photo_links


@end_time = Time.now
elapsed = @end_time - @beginning_time
sec = elapsed % 60
min = elapsed / 60
puts "---------------------------", " Finished in #{min.floor} min #{sec.floor} sec", "---------------------------", "", ""