require 'rubygems'
require 'highline/import'

system "clear"

@beginning_time = Time.now

@quick_mode = false
@output_dir = "output"

@email = ""
puts "Using email: #{@email}", ""

@pass = ""
#@pass = ask("Enter password: ") { |q| q.echo = false }
puts ""