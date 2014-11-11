#!/usr/bin/perl

# branch=master buildnumber=4096 (got_revision=xxx)

@dirs = qw(build builds install tmp);

foreach (@ARGV) {
    die unless /^([^=]+)=(.*)$/;
    $arg{$1} = $2;
    $msg .= "$_\n";
}

if ($arg{'fetch'} ne '') {
    &fetch;
} elsif ($arg{'got_revision'} ne '') {
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

# cd ${root}
# fetch={builder} got_revision={rev} ref=llvm-project.git
sub fetch {
    my $blob_git = "$ENV{PWD}/../$arg{'fetch'}/blob.git";
    my $blob_hash, $bn, $rev;
    my $tree_rev = '';
    my ($target_rev) = $arg{'got_revision'} =~ /r(\d+)/;
    open(my $FH, "git --git-dir=$blob_git log --oneline --no-decorate --date-order --all --max-count=32 |") || die "Cannot peek $arg{'fetch'}/blob.git";
    for (<$FH>) {
	next unless ($blob_hash, $bn, $rev) = /^([0-9A-Fa-f]+)\s+OK\s+(\d+)-r(\d+)/;
	print "hash=$blob_hash bn=$bn rev=$rev\n";
	if ($rev == $target_rev) {
	    $tree_rev = "r$target_rev";
	    last;
	}
	if ($rev <= $target_rev) {
	    # Inspect valid ref.
	    next unless (`git --git-dir=$arg{'ref'} rev-list --no-walk --abbrev-commit refs/tags/t/r$rev` =~ /^([0-9A-Fa-f]+)/);
	    $tree_rev = $1;
	    last;
	}
    }
    close($FH);
    if ($tree_rev eq '') {
	print "Skip.";
	exit 0;
    }
    print "hash=$blob_hash bn=$bn rev=$rev<=$target_rev tree=$tree_rev\n";

    # Expand blobs
    my $fetch_git = "git --git-dir=$arg{'fetch'}/.git --work-tree=$arg{'fetch'}";
    if (! -d $arg{'fetch'}) {
	system("git init $arg{'fetch'}") && die;
	open(my $FH, "> $arg{'fetch'}/.git/objects/info/alternates") || die;
	print $FH "$blob_git/objects";
	close($FH);
	system("$fetch_git checkout -f $blob_hash") && die;
    } else {
	system("$fetch_git --no-pager diff --shortstat $blob_hash");
	system("$fetch_git checkout -f $blob_hash") && die;
	system("$fetch_git clean -fxd") && die;
    }

    # Exit if empty
    exit 0 unless -d "build";

    # Checkout the tree.
    system("git --git-dir=llvm-project/.git --work-tree=llvm-project reset --hard $tree_rev") && die;

    # Update build tree with blob
    my @srcs;
    for (qw(build/lib build/tools/clang/lib)) {
	push(@srcs, $_) if -d "$arg{'fetch'}/$_";
    }
    die unless @srcs;
    system("(cd $arg{'fetch'}; find @srcs -type f -name '*.o' -o -name '*.inc' -o -name '*.def' | xargs cp -u --parent --target-directory=..)");
    system("git --git-dir=blob.git --work-tree=. status -s @srcs");

    # Checkout the tree with got_revision.
    system("git --git-dir=llvm-project/.git --work-tree=llvm-project reset --hard $arg{'got_revision'}") && die;

    exit 0;
}
