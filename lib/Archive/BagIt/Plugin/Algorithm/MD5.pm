use strict;
use warnings;

#ABSTRACT: The default MD5 algorithm plugin

package Archive::BagIt::Plugin::Algorithm::MD5;

use Moo;
use namespace::autoclean;

with 'Archive::BagIt::Role::Algorithm';

has '+plugin_name' => (
    is => 'ro',
    default => 'Archive::BagIt::Plugin::Algorithm::MD5',
);

has '+name' => (
    is      => 'ro',
    #isa     => 'Str',
    default => 'md5',
);

has '_digest_md5' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_digest_md5',
    init_arg => undef,
);

sub _build_digest_md5 {
    my ($self) = @_;
    my $digest_md5 = new Digest::MD5;
    return $digest_md5;
}

sub get_hash_string {
    my ($self, $fh) = @_;
    my ($dev,$ino,$mode,$nlink,$uid,$gid,$rdev,$size,
        $atime,$mtime,$ctime,$blksize,$blocks)
        = stat $fh;
    my $buffer;
    while (read($fh, $buffer, $blksize)) {
        $self->_digest_md5->add($buffer);
    }
    return $self->_digest_md5->hexdigest;

}

sub verify_file {
    my ($self, $filename) = @_;
    open(my $fh, '<', $filename) || die ("Can't open '$filename', $!");
    binmode($fh);
    my $digest = $self->get_hash_string($fh);
    close $fh || die("could not close file '$filename', $!");
    return $digest;
}
__PACKAGE__->meta->make_immutable;
1;
