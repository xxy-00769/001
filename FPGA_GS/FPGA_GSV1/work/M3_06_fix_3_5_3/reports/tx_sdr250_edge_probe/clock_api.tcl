puts "CLOCK_COMMANDS=[info commands *clock*]"
puts "SENSE_COMMANDS=[info commands *sense*]"
if {[llength [info commands set_clock_sense]]} {
    catch {set_clock_sense -help} sense_help
    puts "SENSE_HELP=$sense_help"
}
