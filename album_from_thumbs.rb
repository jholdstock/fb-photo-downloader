require 'selenium-webdriver'
require 'down'

driver = Selenium::WebDriver.for :chrome
#
# INSERT URL HERE
#
driver.get "https://m.facebook.com/media/set/?"
sleep 1

# Dismiss cookie prompt
el = driver.find_element :xpath => "//button[@value='Accept All']"
el.click
sleep 1

el = driver.find_element :xpath => "//a[@data-sigil='touchable ajaxify']"
el.click
sleep 1

# Ensure full page is loaded
last_pos = 0
matching = 0
while matching < 5
    driver.execute_script("window.scrollTo(0, document.body.scrollHeight);")
    new_pos = driver.execute_script('return window.pageYOffset;')
    puts "last #{last_pos} new #{new_pos}"
    if last_pos == new_pos
        matching +=1
    else
        matching = 0
    end
    last_pos = new_pos
    sleep 0.5
end
puts "fully scrolled"

pics = driver.find_elements :xpath => "//a[@data-sigil='photoset_thumbnail']"

puts "found #{pics.length}"

# Get urls for all pages
page_urls = []
pics.each do |pic|
    page_urls.push pic.attribute("href")
end

# Get urls for all pics

pic_urls = []
page_urls.each do |url|
    driver.get url
    el = driver.find_element :xpath => "//a[.='View full size']"

    pic_urls.push el.attribute("href")
end

i = 0
pic_urls.each do |url|
    i = i+1
    Down.download(url, destination: "./#{i}.jpg")
end

sleep 100