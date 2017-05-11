require 'net/http'
require 'uri'
require 'progressbar'
require 'selenium-webdriver'
require 'pp'
require 'securerandom'
require 'fileutils'

require './conf.rb'

def download_file url, filename
    url_base = url.split('/')[2]
    url_path = '/'+url.split('/')[3..-1].join('/')
    counter = 0

    Net::HTTP.start(url_base) do |http|
        response = http.request_head(URI.escape(url_path))
        pbar = ProgressBar.create(:format => "%a |%b>%i| %p%% %t",
                                  :progress_mark  => "=",
                                  :remainder_mark => " ")
        fileSize = response['content-length'].to_f

        File.open(filename, 'w') do |f|
            http.get(URI.escape(url_path)) do |str|
                f.write str
                counter += str.length.to_f 
                pbar.progress = (counter/fileSize)*100
            end
        end
        pbar.finish
    end
end

def create_driver
	caps = Selenium::WebDriver::Remote::Capabilities.chrome(
	  "chromeOptions" => {
	    "args" => [
	      "--disable-web-security",
	      "--incognito"
	    ],
	  }
	)
	return Selenium::WebDriver.for :chrome, desired_capabilities: caps
end

def login
	print "Opening Chrome... "  
	@driver.get "https://www.facebook.com"
	puts "done\n", ""


	print "Entering user ID and password... "  
	@driver.find_element(:id => "email").send_keys @email
	@driver.find_element(:id => "pass").send_keys @pass
	@driver.find_element(:id => "pass").send_keys :enter
	puts "done\n", ""
end

def get_username
	print "Getting account username... "  
	@driver.get "https://www.facebook.com/settings?tab=account&section=username&view"
	@username = @driver.find_element(:css => "table.uiInfoTable input.inputtext")["value"]
	puts "done (#{@username})\n", ""
end

def open_all_years
	puts "Open all years...", ""
	@driver.get "https://m.facebook.com/#{@username}/allactivity?log_filter=cluster_200"
	async_elements = @driver.find_elements(:css => ".timeline > div > div .async_elem")
	inc = 0
	pbar = ProgressBar.create(:format => "%a |%b>%i| %p%% %t",
                      :progress_mark  => "=",
                      :remainder_mark => " ")
	async_elements.each do |element|
	  text = element.text
	  next if text !~ /^\d{4}$/
	  element.click
	  #debug puts "\t#{text}"
	  sleep 0.5
	  inc += 1
 	  pbar.progress = (inc.to_f/async_elements.length.to_f)*100
	  break if @quick_mode and inc >=2
	end
	pbar.finish
end

def open_all_months
	puts "", "", "Open all months...", ""
	async_elements = @driver.find_elements(:css => ".timeline > div > div .collapse")

# I think this is a breaking change. Only found 332 photos running like this. Missing or dupes?
	async_elements.delete_if { |x| x.text =~ /^\d{4}$/ }
	async_elements.delete_if { |x| x.text =~ /^No stories available$/ }




	inc = 0
	pbar = ProgressBar.create(:format => "%a |%b>%i| %p%% %t",
                      :progress_mark  => "=",
                      :remainder_mark => " ")
	async_elements.each do |element|
	  text = element.text
	  element.click
	  #debug puts "\t#{text}"
	  sleep 0.5
	  inc += 1
 	  pbar.progress = (inc.to_f/async_elements.length.to_f)*100
	  break if @quick_mode and inc >=2
	end
	pbar.finish
end


def expand_months
	puts "", "", "Fully expand months...", ""
	loop do
	  async_elements = @driver.find_elements(:css => ".timeline > div > div > div > div .async_elem")
	  async_elements.delete_if { |x| x.text =~ /^No more from/ }
	  break if async_elements.length == 0

    	inc = 0
    	pbar = ProgressBar.create(:format => "%a |%b>%i| %p%% %t",
                      :progress_mark  => "=",
                      :remainder_mark => " ")
	    async_elements.each do |element|
	    text = element.text
	    element.click
	    # debug puts "\t#{text}"
	    sleep 0.5
	    inc += 1
 	  	pbar.progress = (inc.to_f/async_elements.length.to_f)*100
	  end
	  pbar.finish
	end
end

@quick_mode = false
@output_dir = "output"

@driver = create_driver
login
get_username
open_all_years
open_all_months
expand_months


puts "", "Scan page for tags... "
photo_links = @driver.find_elements(:xpath => "//div[@class='timeline']//a[text()='photo']")
photo_links.collect! { |x| x.attribute("href") }
puts "\t Tagged in #{photo_links.length} photos", ""

# post_links = links.select { |x| x.text == "post" }
# post_links.collect!  { |x| x.attribute("href") }
# puts "\t Tagged in #{post_links.length} posts", ""

puts "Get HQ photo links... "
hq_links = {}

print "\tTagged photos... "
inc = 0
pbar = ProgressBar.create(:format => "%a |%b>%i| %p%% %t",
                      :progress_mark  => "=",
                      :remainder_mark => " ")
photo_links.each do |link|
  @driver.get link
  img_url = @driver.find_element(:xpath, './/a[contains(., "View full size")]').attribute("href")
  json = @driver.find_element(:css, 'div > span > div > div > abbr').attribute("data-store")
  name = @driver.find_element(:css, 'div > div > a > strong.actor').text
  json_hash = JSON.parse json
  time = json_hash["time"]
  time = Time.at(time)
  fileName = time.to_date.to_s + " " + name + " - " + @driver.title + " " + SecureRandom.hex(1)
  fileName.gsub!("-", ':')
  fileName.gsub!(/[^:0-9A-Za-z\s]/, '')
  fileName.gsub!(":", '-')
  hq_links[fileName] = img_url
  inc += 1
  pbar.progress = (inc.to_f/photo_links.length.to_f)*100
  break if @quick_mode and inc >=10
end
pbar.finish

# print "\tTagged posts... "
# post_links.each do |link|
# 	@driver.get link
# 	full_size = @driver.find_elements(:css, 'div > div >  a > div > div i')
# 	pp full_size
# 	sleep 10000

# 	if full_size.length == 0
# 		puts "No photo - skipping"
# 		next
# 	end
# 	puts "TODO Get date and photo url. Add to hq_links hash"
# 	sleep 30000
# end
# puts "done"

FileUtils.rm_rf(@output_dir)
Dir.mkdir(@output_dir)

puts "", "Download HQ photos... "
hq_links.each do |key, value|
    download_file value, "output/"+key+".jpg"
end

puts "", "--------", "FINISHED", "--------"
