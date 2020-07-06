package Archive::BagIt::Fast;

use strict;
use warnings;
use parent "Archive::BagIt::Base";

# VERSION

use IO::AIO;
use Time::HiRes qw(time);
=head1 NAME

Archive::BagIt::Fast - For people who are willing to rely on some other modules in order to get better performance

=cut

sub calc_digests {
    my ($self, $bagit, $digestobj, $filenames_ref, $opts) = @_;
    my $MMAP_MIN = $opts->{mmap_min} || 8000000;

    my @digest_hashes = map {
        my $localname = $_;
        my $fullname = $bagit ."/". $localname;
        my $tmp;
        open(my $fh, "<:raw", "$fullname") or die ("Cannot open $fullname");
        stat $fh;
        $self->{stats}->{files}->{"$fullname"}->{size}= -s _;
        $self->{stats}->{size} += -s _;
        my $start_time = time();
        my $digest;
        if (-s _ < $MMAP_MIN ) {
            sysread $fh, my $data, -s _;
            $digest = $digestobj->_digest->add($data)->hexdigest;
        }
        elsif ( -s _ < 1500000000) {
            IO::AIO::mmap my $data, -s _, IO::AIO::PROT_READ, IO::AIO::MAP_SHARED, $fh or die "mmap: $!";
            $digest = $digestobj->_digest->add($data)->hexdigest;
        }
        else {
            $digest = $digestobj->_digest->addfile($fh)->hexdigest; # FIXME: use plugins instead
        }
        my $finish_time = time();
        $self->{stats}->{files}->{"$fullname"}->{verify_time}= ($finish_time - $start_time);
        $self->{stats}->{verify_time} += ($finish_time-$start_time);
        close($fh);
        $tmp->{calculated_digest} = $digest;
        $tmp->{local_name} = $localname;
        $tmp->{full_name} = $fullname;
        $tmp;
    } @{$filenames_ref};
    return \@digest_hashes;
}

1;
