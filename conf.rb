@quick_mode = true
@how_quick = 1
@output_dir = "output"
@progress_bars = true

@email = ""
puts "Using email: #{@email}", ""

@pass = ""
#@pass = ask("Enter password: ") { |q| q.echo = false }
puts ""

if @quick_mode
	@timeoutInSeconds = 10
else
	@timeoutInSeconds = 30
end