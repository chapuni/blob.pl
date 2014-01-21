#!/usr/bin/perl

use IO::Socket;

# branch=master buildnumber=4096 (got_revision=xxx)

if ($ARGV[0] eq "START") {
    shift(@ARGV);
    system("start perl $0 @ARGV");
    exit(0);
}

for (qw(build builds install tmp)) {
    push(@dirs, $_) if -d $_;
}

if (open(my $FH, "blob.git/port.txt")) {
    $port = <$FH>;
    chomp($port);
    close($FH);
}

if ($ARGV[0] eq "PUSH") {
    shift(@argv);
    &server_push(@ARGV);
    die;
}

if ($ARGV[0] eq "ADD") {
    shift(@ARGV);
    &server_add(@ARGV);
    &client_add(@ARGV);
    die;
}

foreach (@ARGV) {
    die unless /^([^=]+)=(.*)$/;
    $arg{$1} = $2;
    $msg .= "$_\n";
}

if ($arg{'got_revision'} ne '') {
    &post;
} else {
    &pre;
}

die;

sub pre {

    $ref = &ref;

    if (open($FH, "blob.git/HEAD")) {
	$cur = <$FH>;
	chomp $cur;
	close($FH);
    } else {
	system("git init --bare blob.git") && die "git-init failed";
	print STDERR "* Blob is created.\n";
    }

    $msg = sprintf("%d-prebuild\n\n", $arg{'buildnumber'}) . $msg;
    &commit($msg);

    exit 0 if ($cur eq $ref);

    open($FH, "> blob.git/HEAD") || die;
    printf $FH "$ref\n";
    close($FH);

    if ($cur eq '') {
	print STDERR "* New branch $ref is created.\n";
    } else {
	print STDERR "* Branch is changed from $cur to $ref\n";
    }

    system("rm -rf @dirs");

    exit 0;
}

sub post {
    $msg = sprintf("%s %d-%s\n\n",
		   $arg{'build_successful'},
		   $arg{'buildnumber'},
		   $arg{'got_revision'}) . $msg;
    &commit($msg, "--allow-empty");
    exit 0;
}

sub ref {
    my $branch = $arg{'branch'};

    $branch = 'misc' if $branch eq '';

    my $t = time;

    ($sec, $min, $hour, $mday, $mon, $year, $wday, $d) = @a = gmtime($t);

    # UCT Monday midnight
    $t -= 86400 * (($wday + 6) % 7);

    ($sec, $min, $hour, $mday, $mon, $year, $wday, $d) = @a = gmtime($t);

    return sprintf("ref: refs/heads/%04d%02d%02d/%s", 1900 + $year, 1 + $mon, $mday, $branch);
}

sub commit {
    my $msg = shift @_;

    mkdir('build');

    &client_quit(@ARGV);

    system("git --git-dir=blob.git --work-tree=. add -A --ignore-errors @dirs");
    if (open(my $FH, "| git --git-dir=blob.git --work-tree=. commit @_ -F -")) {
	print $FH $msg;
	close($FH);
    }
}

# Push(udp)
sub server_push {
    my @argv = @_;
    if ($argv[0] =~ /^PORT=(\d+)/) {
	$port = $1;
	shift(@argv);
    } elsif ($port eq '') {
	die "* Did you specify PORT=n ?";
    }

    # Server
    $sock = IO::Socket::INET->new(
	LocalAddr => "localhost",
	LocalPort => $port,
	ReuseAddr => 0,
	Proto     => "udp",
	Blocking  => 0,
	);

    if (!$sock) {
	$sock = IO::Socket::INET->new(
	    PeerAddr => "localhost",
	    PeerPort => $port,
	    Proto    => "udp",
	    ) || die;
	print STDERR "Requesting push\n";
	$sock->send("push\n");
	$sock->close;
	exit(0);
    }

    while (1) {
	printf STDERR "PROCESSING\n";
	if (system("git --git-dir=blob.git push")) {
	    print STDERR "$! -- $@\n";
	    sleep(5);
	    die;
	}
	if ($sock->recv($buf, 1024)) {
	    while ($sock->recv($buf, 1024)) {
	    }
	    next;
	}
	print STDERR "WAITING...\n";
	sleep(10);
	if ($sock->recv($buf, 1024)) {
	    while ($sock->recv($buf, 1024)) {
	    }
	    next;
	}
	print STDERR "EXIT\n";
	$sock->close();
	exit(0);
    }
}

# Add(tcp)
sub server_add {
    my @argv = @_;
    my @argv = @_;
    if ($argv[0] =~ /^PORT=(\d+)/) {
	$port = $1;
	shift(@argv);
    } elsif ($port eq '') {
	die "* Did you specify PORT=n ?";
    }

    # Server
    $sock = IO::Socket::INET->new(
	LocalAddr => "localhost",
	LocalPort => $port,
	#ReuseAddr => 1,
	Proto     => "tcp",
	);

    return unless $sock;
    $sock->listen || die;

    #system("git --git-dir=blob.git --work-tree=. add -A --ignore-errors @argv");

    print STDERR "START...<@argv>\n";

    while (my $h = $sock->accept()) {
	printf STDERR "ACCEPTED\n";

	my $line = $h->getline();
	chomp $line;
	if ($line eq '(QUIT)') {
	    $h->print("BYE\n");
	    $h->close();
	    $sock->close();
	    print STDERR "(QUIT)TERMINATED.\n";
	    sleep(10);
	    exit(0);
	}

	print STDERR "<$line>\n";
	$h->print("ACCEPTED $line\n");
	$h->close();
	#system("git --git-dir=blob.git --work-tree=. add -A --ignore-errors $line");
    }
    $sock->close();
    print STDERR "WHAT HAPPENED?\n";
    sleep(10);
    exit(0);
}

# Add(tcp client)
sub client_connect {
    # Connect to Server
    $sock = IO::Socket::INET->new(
	PeerAddr => "localhost",
	PeerPort => $port,
	Proto    => "tcp",
	);

    return $sock;
}

sub client_add {
    my @argv = @_;
    if ($argv[0] =~ /^PORT=(\d+)/) {
	$port = $1;
	shift(@argv);
    } elsif ($port eq '') {
	die "* Did you specify PORT=n ?";
    }

    my $sock = &client_connect();
    return unless $sock;

    $sock->print("@argv\n");
    print STDERR "SENT<@argv>\n";
    printf STDERR "RECV<%s>\n", $sock->getline;
    $sock->close();
    exit(0);
}

sub client_quit {
    my @argv = @_;
    if ($argv[0] =~ /^PORT=(\d+)/) {
	$port = $1;
	shift(@argv);
    } elsif ($port eq '') {
	die "* Did you specify PORT=n ?";
    }

    my $sock = &client_connect();
    return unless $sock;

    $sock->print("(QUIT)\n");
    print STDERR "SENT<@argv>\n";
    printf("RECV<%s>\n", $sock->getline);
    $sock->close();
    exit(0);

    #system("git --git-dir=blob.git --work-tree=. add -A --ignore-errors @argv");
}

#EOF
