# Self-authored test dictionary; the pinned krht repository has no Tcl example.
namespace eval ghost {
    variable directory ""
    variable bootCount 0
}
proc _request {message} {
    if {![string match "GET SHIORI/*" $message] && ![string match "NOTIFY SHIORI/*" $message]} {
        # krht's original load() calls _request(directory), not _load.
        set ghost::directory $message
        set path [file join $ghost::directory state.txt]
        if {[file exists $path]} {
            set channel [open $path r]
            set ghost::bootCount [string trim [read $channel]]
            close $channel
            if {![string is integer -strict $ghost::bootCount]} {error "invalid saved counter"}
        }
        return true
    }
    if {[string match "NOTIFY *" $message]} {
        return "SHIORI/3.0 204 No Content\r\nCharset: UTF-8\r\n\r\n"
    }
    set id ""
    regexp {(?m)^ID: ([^\r\n]*)} $message ignored id
    switch -- $id {
        version {set value "0.1"}
        name {set value "Ourin krht Tcl example"}
        OnArchitecture {set value "[info patchlevel]/$::tcl_platform(machine)"}
        OnBoot {
            incr ghost::bootCount
            set value [format {\0\s[0]Tcl起動 %d。\e} $ghost::bootCount]
        }
        OnEcho {
            set value ""
            regexp {(?m)^Reference0: ([^\r\n]*)} $message ignored value
        }
        OnClose {set value {\0終了します。\-}}
        default {return "SHIORI/3.0 204 No Content\r\nCharset: UTF-8\r\n\r\n"}
    }
    return "SHIORI/3.0 200 OK\r\nCharset: UTF-8\r\nSender: krht\r\nValue: $value\r\n\r\n"
}
proc _unload {} {
    set channel [open [file join $ghost::directory state.txt] w]
    puts $channel $ghost::bootCount
    close $channel
    return true
}
