# Ourin-owned protocol fixture; not upstream Rishu code.
use strict;
use warnings;
use IO::Socket::INET;
open my $modefile, '<', 'mode.txt' or die $!;
chomp(my $mode = <$modefile>);
if ($mode eq 'never-connect') { sleep 30; exit; }
my ($flag, $port) = @ARGV;
die 'expected --port' unless $flag eq '--port';
my $sock = IO::Socket::INET->new(PeerAddr => '127.0.0.1', PeerPort => $port, Proto => 'tcp') or die $!;
$sock->autoflush(1);
while (my $first = <$sock>) {
    my @lines;
    while (my $line = <$sock>) { last if $line eq "\r\n"; push @lines, $line; }
    if ($first =~ /^PROXY LOAD /) {
        if ($mode eq 'load-hang') { sleep 30; next; }
        print $sock "RISHU/1.1 200 OK\r\nContent-Length: 2\r\n\r\nOK";
    } elsif ($first =~ /^PROXY REQUEST /) {
        if ($mode eq 'hang') { sleep 30; next; }
        if ($mode eq 'exit') { exit; }
        if ($mode eq 'bad-length') { print $sock "RISHU/1.1 200 OK\r\nContent-Length: -1\r\n\r\n"; next; }
        if ($mode eq 'flood') { print $sock 'x' x 1100000; next; }
        my ($ref) = map { /^Reference0: (.*)\r\n$/ ? $1 : () } @lines;
        my ($charset) = map { /^Charset: (.*)\r\n$/ ? $1 : () } @lines;
        my ($verb) = map { /^Command: (\w+)/ ? $1 : () } @lines;
        print $sock "RISHU/1.1 200 OK\r\nOriginal-Response: SHIORI/3.0 200 OK\r\nCharset: $charset\r\nValue: ".($ref // '')."\r\nReference0: $verb\r\n\r\n";
    } elsif ($first =~ /^PROXY UNLOAD /) {
        open my $marker, '>', 'unloaded.marker' or die $!;
        close $marker;
        print $sock "RISHU/1.1 200 OK\r\nContent-Length: 1\r\n\r\n1";
    } elsif ($first =~ /^PROXY EXIT /) { exit; }
}
