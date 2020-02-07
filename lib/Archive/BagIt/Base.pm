use strict;
use warnings;

package Archive::BagIt::Base;

use Moose;
use namespace::autoclean;

use utf8;
use open ':std', ':encoding(utf8)';
use Encode qw(decode);
use File::Find;
use File::Spec;
use Digest::MD5;
use Class::Load qw(load_class);

# VERSION

use Sub::Quote;

my $DEBUG=0;

=head1 NAME

Achive::BagIt::Base - The common base for both Bagit and dotBagIt

=cut

has 'bag_path' => (
    is => 'rw',
);

has 'bag_path_arr' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_bag_path_arr',
);

has 'metadata_path' => (
    is=> 'ro',
    lazy => 1,
    builder => '_build_metadata_path',
);

sub _build_metadata_path { 
    my ($self) = @_; 
    return $self->bag_path; 
}


has 'metadata_path_arr' => (
    is =>'ro',
    lazy => 1,
    builder => '_build_metadata_path_arr',
);

has 'rel_metadata_path' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_rel_metadata_path',
);

has 'payload_path' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_payload_path',
);

sub _build_payload_path { 
    my ($self) = @_; 
    return $self->bag_path."/data"; 
}

has 'payload_path_arr' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_payload_path_arr',
);

has 'rel_payload_path' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_rel_payload_path',
);

has 'checksum_algos' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_checksum_algos',
);

has 'bag_version' => (
    is       => 'ro',
    lazy     => 1,
    builder  => '_build_bag_version',
);

has 'forced_fixity_algorithm' => (
    is   => 'ro',
    lazy => 1,
    builder  => '_build_forced_fixity_algorithm',
);

has 'bag_checksum' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_bag_checksum',
);

has 'manifest_files' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_manifest_files',
);

has 'tagmanifest_files' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_tagmanifest_files',
);

has 'manifest_entries' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_manifest_entries',
);

has 'tagmanifest_entries' => (
    is => 'ro',
    lazy => 1,
    builder => '_build_tagmanifest_entries',
);

has 'payload_files' => ( # relatively to bagit base
    is => 'ro',
    lazy => 1,
    builder => '_build_payload_files',
);

has 'non_payload_files' => (
    is=>'ro',
    lazy => 1,
    builder => '_build_non_payload_files',
);

has 'plugins' => (
    is=>'rw',
    isa=>'HashRef',
);

has 'manifests' => (
    is=>'rw',
    isa=>'HashRef',
);

has 'algos' => (
    is=>'rw',
    isa=>'HashRef',

);

=head2 BUILDARGS

The constructor sub, will create a bag with a single argument
=cut

around 'BUILDARGS' , sub {
    my $orig = shift;
    my $class = shift;
    if (@_ == 1 && !ref $_[0]) {
        return $class->$orig(bag_path=>$_[0]);
    }
    else {
        return $class->$orig(@_);
    }
};

sub BUILD {
    my ($self, $args) = @_;
    $self->load_plugins(("Archive::BagIt::Plugin::Manifest::MD5", "Archive::BagIt::Plugin::Manifest::SHA512"));
}
sub _build_bag_path_arr {
    my ($self) = @_;
    my @split_path = File::Spec->splitdir($self->bag_path);
    return @split_path;
}

sub _build_payload_path_arr {
    my ($self) = @_;
    my @split_path = File::Spec->splitdir($self->payload_path);
    return @split_path;
}

sub _build_rel_payload_path {
    my ($self) = @_;
    my $rel_path = File::Spec->abs2rel( $self->payload_path, $self->bag_path ) ;
    return $rel_path;
}

sub _build_metadata_path_arr {
    my ($self) = @_;
    my @split_path = File::Spec->splitdir($self->metadata_path);
    return @split_path;
}

sub _build_rel_metadata_path {
    my ($self) = @_;
    my $rel_path = File::Spec->abs2rel( $self->metadata_path, $self->bag_path ) ;
    return $rel_path;
}

sub _build_checksum_algos {
    my($self) = @_;
    my $checksums = [ 'md5', 'sha1', 'sha256', 'sha512' ];
    return $checksums;
}

sub _build_bag_checksum {
  my($self) =@_;
  my $bagit = $self->{'bag_path'};
  open(my $SRCFILE, "<:raw",  $bagit."/manifest-md5.txt");
  my $srchex=Digest::MD5->new->addfile($SRCFILE)->hexdigest;
  close($SRCFILE);
  return $srchex;
}

sub _build_manifest_files {
  my($self) = @_;
  my @manifest_files;
  foreach my $algo (@{$self->checksum_algos}) {
    my $manifest_file = $self->metadata_path."/manifest-$algo.txt";
    if (-f $manifest_file) {
      push @manifest_files, $manifest_file;
    }
  }
  #print Dumper(@manifest_files);
  return \@manifest_files;
}

sub _build_tagmanifest_files {
  my ($self) = @_;
  my @tagmanifest_files;
  foreach my $algo (@{$self->checksum_algos}) {
    my $tagmanifest_file = $self->metadata_path."/tagmanifest-$algo.txt";
    if (-f $tagmanifest_file) {
      push @tagmanifest_files, $tagmanifest_file;
    }
  }
  return \@tagmanifest_files;

}

sub _build_tagmanifest_entries {
  my ($self) = @_;

  my @tagmanifests = @{$self->tagmanifest_files};
  my $tagmanifest_entries = {};
  foreach my $tagmanifest_file (@tagmanifests) {
    die("Cannot open $tagmanifest_file: $!") unless (open(my $TAGMANIFEST,"<:encoding(utf8)", $tagmanifest_file));
    while (my $line = <$TAGMANIFEST>) {
      chomp($line);
      my($digest,$file) = split(/\s+/, $line, 2);
      $tagmanifest_entries->{$file} = $digest;
    }
    close($TAGMANIFEST);

  }
  return $tagmanifest_entries;
}

sub _build_manifest_entries {
  my ($self) = @_;

  my @manifests = @{$self->manifest_files};
  my $manifest_entries = {};
  foreach my $manifest_file (@manifests) {
    die("Cannot open $manifest_file: $!") unless (open (my $MANIFEST, "<:encoding(utf8)", $manifest_file));
    while (my $line = <$MANIFEST>) {
        chomp($line);
        my ($digest,$file);
        ($digest, $file) = $line =~ /^([a-f0-9]+)\s+(.+)/;
        if(!$file) {
          die ("This is not a valid manifest file");
        } else {
          print "file: $file \n" if $DEBUG;
          $manifest_entries->{$file} = $digest;
        }
    }
    close($MANIFEST);
  }

  return $manifest_entries;

}

sub _build_payload_files{
  my($self) = @_;

  my $payload_dir = $self->payload_path;
  my $payload_reldir = $self->rel_payload_path;

  my @payload=();
  File::Find::find( sub{
    $File::Find::name = decode ('utf8', $File::Find::name);
    $_ = decode ('utf8', $_);
    if (-f $_) {
        #my $rel_path=File::Spec->catdir($self->rel_payload_path,File::Spec->abs2rel($File::Find::name, $payload_dir));
        #print "pushing ".$rel_path." payload_dir: $payload_dir ($_) \n";
        #push(@payload,$rel_path);
        my $localpath = $payload_reldir eq "." ? $_ : "$payload_reldir/$_";
        push @payload, $localpath; # relative to bagit base dir
    }
    elsif($self->metadata_path_arr > $self->payload_path_arr && -d _ && $_ eq $self->rel_metadata_path) {
        #print "pruning ".$File::Find::name."\n";
        $File::Find::prune=1;
    }
    else {
        #payload directories
    }
    #print "name: ".$File::Find::name."\n";
  }, $payload_dir);

  #print p(@payload);

  return wantarray ? @payload : \@payload;

}

sub _build_bag_version {
    my($self) = @_;
    my $bagit = $self->metadata_path;
    my $file = join("/", $bagit, "bagit.txt");
    open(my $BAGIT, "<", $file) or die("Cannot read $file: $!");
    my $version_string = <$BAGIT>;
    my $encoding_string = <$BAGIT>;
    close($BAGIT);
    $version_string =~ /^BagIt-Version: ([0-9.]+)$/;
    return $1 || 0;
}

sub _build_non_payload_files {
  my($self) = @_;

  my @non_payload = ();

  File::Find::find( sub{
    $File::Find::name = decode('utf8', $File::Find::name);
    $_=decode ('utf8', $_);
    if (-f $_) {
        my $rel_path=File::Spec->catdir($self->rel_metadata_path,File::Spec->abs2rel($File::Find::name, $self->metadata_path));
        #print "pushing ".$rel_path." payload_dir: $payload_dir \n";
        push(@non_payload,$rel_path);
    }
    elsif($self->metadata_path_arr < $self->payload_path_arr && -d _ && $_ eq $self->rel_payload_path) {
        #print "pruning ".$File::Find::name."\n";
        $File::Find::prune=1;
    }
    else {
        #payload directories
    }
    #print "name: ".$File::Find::name."\n";
  }, $self->metadata_path);

  return wantarray ? @non_payload : \@non_payload;

}

sub _build_forced_fixity_algorithm {
    my ($self) = @_;
    if ($self->bag_version() >= 1.0) {
        return Archive::BagIt::Plugin::Algorithm::SHA512->new(bagit => $self);
    }
    else {
        return Archive::BagIt::Plugin::Algorithm::MD5->new(bagit => $self);
    }
}

=head2 load_plugins

As default SHA512 and MD5 will be loaded and therefore used. If you want to create a bag only with one or a specific
checksum-algorithm, you could use this method to (re-)register it. It expects list of strings with namespace of type:
Archive::BagIt::Plugin::Algorithm::XXX where XXX is your chosen fixity algorithm.

=cut

sub load_plugins {
    my ($self, @plugins) = @_;
 
    #p(@plugins); 
    my $loaded_plugins = $self->plugins;  
    @plugins = grep { not exists $loaded_plugins->{$_} } @plugins; 

    return if @plugins == 0;
    foreach my $plugin (@plugins) {
        load_class ($plugin) or die ("Can't load $plugin");
        $plugin->new({bagit => $self});
    }

    return 1;
}

=head2 verify_bag

An interface to verify a bag.

You might also want to check Archive::BagIt::Fast to see a more direct way of accessing files (and thus faster).


=cut

sub verify_bag {
    my ($self,$opts) = @_;
    #removed the ability to pass in a bag in the parameters, but might want options
    #like $return all errors rather than dying on first one
    my $bagit = $self->bag_path;
    my $version = $self->bag_version(); # to call trigger
    my $manifest_file = $self->metadata_path."/manifest-".$self->forced_fixity_algorithm()->name().".txt"; # FIXME: use plugin instead
    my $payload_dir   = $self->payload_path;
    my $return_all_errors = $opts->{return_all_errors};
    my %invalids;
    my @payload       = @{$self->payload_files};

    die("$manifest_file is not a regular file for bagit $version") unless -f ($manifest_file);
    die("$payload_dir is not a directory") unless -d ($payload_dir);

    unless ($version > .95) {
        die ("Bag Version $version is unsupported");
    }

    # Read the manifest file
    #print Dumper($self->{entries});
    my %manifest = %{$self->manifest_entries};

    # Evaluate each file against the manifest
    my $digestobj = $self->forced_fixity_algorithm();
    foreach my $local_name (@payload) { # local_name is relative to bagit base
        my ($digest);
        unless ($manifest{"$local_name"}) {
          die ("file found not in manifest: [$local_name]");
        }
        if (! -r "$bagit/$local_name" ) {die ("Cannot open $bagit/$local_name");}
        $digest = $digestobj->verify_file( "$bagit/$local_name");
        print "digest of $bagit/$local_name: $digest\n" if $DEBUG;
        unless ($digest eq $manifest{$local_name}) {
          if($return_all_errors) {
            $invalids{$local_name} = $digest;
          }
          else {
            die ("file: $bagit/$local_name invalid");
          }
        }
        delete($manifest{$local_name});
    }
    if($return_all_errors && keys(%invalids) ) {
      foreach my $invalid (keys(%invalids)) {
        print "invalid: $invalid hash: ".$invalids{$invalid}."\n";
      }
      die ("bag verify for bagit $version failed with invalid files");
    }
    # Make sure there are no missing files
    if (keys(%manifest)) { die ("Missing files in bag".p(%manifest)); }

    return 1;
}

=head2 init_metadata

A constructor that will just create the metadata directory

This won't make a bag, but it will create the conditions to do that eventually

=cut

sub init_metadata {
    my ($class, $bag_path) = @_;
    unless ( -d $bag_path) { die ( "source bag directory doesn't exist"); }
    my $self = $class->new(bag_path=>$bag_path);
    warn "no payload path\n" if ! -d $self->payload_path;
    unless ( -d $self->payload_path) {
        rename ($bag_path, $bag_path.".tmp");
        mkdir  ($bag_path);
        rename ($bag_path.".tmp", $self->payload_path);
    }
    unless ( -d $self->metadata_path) {
        #metadata path is not the root path for some reason
        mkdir ($self->metadata_path);
    }
    foreach my $algorithm (keys %{$self->manifests}) {
        $self->manifests->{$algorithm}->create_bagit();
        $self->manifests->{$algorithm}->create_baginfo();
    }
    return $self;
}


=head2 make_bag

A constructor that will make and return a bag from a directory,

It expects a preliminary bagit-dir exists.
If there a data directory exists, assume it is already a bag (no checking for invalid files in root)


=cut

sub make_bag {
  my ($class, $bag_path) = @_;

  my $self = $class->init_metadata($bag_path);
  # it is important to create all manifest files first, because tagmanifest should include all manifest-xxx.txt
  foreach my $algorithm ( keys %{ $self->manifests }) {
        $self->manifests->{$algorithm}->create_manifest();
  }
  foreach my $algorithm ( keys %{ $self->manifests }) {

        $self->manifests->{$algorithm}->create_tagmanifest();
  }
  return $self;
}


__PACKAGE__->meta->make_immutable;

1;
