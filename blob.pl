#!/usr/bin/perl

# branch=master buildnumber=4096 (got_revision=xxx)

@dirs = qw(build builds install tmp);

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

    my (@d) = ();

    mkdir('build');

    for (@dirs) {
	push(@d, $_) if -d $_;
    }

    system("git --git-dir=blob.git --work-tree=. add -A --ignore-errors @d");
    if (open(my $FH, "| git --git-dir=blob.git --work-tree=. commit @_ -F -")) {
	print $FH $msg;
	close($FH);
    }
}
