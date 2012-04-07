package Poet::Util;
use Carp;
use Class::MOP;
use Fcntl qw( :DEFAULT :seek );
use File::Find;
use File::Spec::Functions ();
use File::Temp qw(tempdir);
use JSON;
use Try::Tiny;
use strict;
use warnings;
use base qw(Exporter);

our @EXPORT_OK =
  qw(can_load catdir catfile checksum find_wanted json_decode json_encode read_file taint_is_on tempdir_simple trim uniq write_file );

my $Fetch_Flags          = O_RDONLY | O_BINARY;
my $Store_Flags          = O_WRONLY | O_CREAT | O_BINARY;
my $File_Spec_Using_Unix = $File::Spec::ISA[0] eq 'File::Spec::Unix';

# Map null, true and false to real Perl values
if ( JSON->VERSION < 2 ) {
    $JSON::UnMapping = 1;
}

sub can_load {

    # Load $class_name if possible. Return 1 if successful, 0 if it could not be
    # found, and rethrow load error (other than not found).
    #
    my ($class_name) = @_;

    my $result;
    try {
        Class::MOP::load_class($class_name);
        $result = 1;
    }
    catch {
        if ( /Can\'t locate .* in \@INC/ && !/Compilation failed/ ) {
            $result = 0;
        }
        else {
            die $_;
        }
    };
    return $result;
}

sub catdir {
    return $File_Spec_Using_Unix
      ? join( "/", @_ )
      : File::Spec::Functions::catdir(@_);
}

sub catfile {
    return $File_Spec_Using_Unix
      ? join( "/", @_ )
      : File::Spec::Functions::catfile(@_);
}

sub checksum {
    my ($str) = @_;

    # Adler32 algorithm
    my $s1 = 1;
    my $s2 = 1;
    for my $c ( unpack( "C*", $str ) ) {
        $s1 = ( $s1 + $c ) % 65521;
        $s2 = ( $s2 + $s1 ) % 65521;
    }
    return ( $s2 << 16 ) + $s1;
}

# From File::Find::Wanted
sub find_wanted {
    my $func = shift;
    my @files;

    local $_;
    find( sub { push @files, $File::Find::name if &$func }, @_ );

    return @files;
}

# Maintain compatibility with both JSON 1 and 2. Borrowed from Data::Serializer::JSON.
#
sub json_decode {
    my ($text) = @_;
    return JSON->VERSION < 2
      ? JSON->new->jsonToObj($text)
      : JSON->new->decode($text);
}

sub json_encode {
    my ($data) = @_;
    return JSON->VERSION < 2
      ? JSON->new->objToJson($data)
      : JSON->new->utf8->encode($data);
}

sub read_file {
    my ($file) = @_;

    # Fast slurp, adapted from File::Slurp::read, with unnecessary options removed
    #
    my $buf = "";
    my $read_fh;
    unless ( sysopen( $read_fh, $file, $Fetch_Flags ) ) {
        croak "read_file '$file' - sysopen: $!";
    }
    my $size_left = -s $read_fh;
    while (1) {
        my $read_cnt = sysread( $read_fh, $buf, $size_left, length $buf );
        if ( defined $read_cnt ) {
            last if $read_cnt == 0;
            $size_left -= $read_cnt;
            last if $size_left <= 0;
        }
        else {
            croak "read_file '$file' - sysread: $!";
        }
    }
    return $buf;
}

sub tempdir_simple {
    my ($template) = @_;

    return tempdir( $template, TMPDIR => 1, CLEANUP => 0 );
}

sub trim {
    my ($str) = @_;
    if ( defined($str) ) {
        for ($str) { s/^\s+//; s/\s+$// }
    }
    return $str;
}

# From List::MoreUtils
sub uniq (@) {
    my %h;
    map { $h{$_}++ == 0 ? $_ : () } @_;
}

sub taint_is_on {
    return ${^TAINT} ? 1 : 0;
}

sub write_file {
    my ( $file, $data, $file_create_mode ) = @_;

    ($file) = $file =~ /^(.*)/s if taint_is_on();    # Untaint blindly
    $file_create_mode = oct(666) if !defined($file_create_mode);

    # Fast spew, adapted from File::Slurp::write, with unnecessary options removed
    #
    {
        my $write_fh;
        unless ( sysopen( $write_fh, $file, $Store_Flags, $file_create_mode ) )
        {
            croak "write_file '$file' - sysopen: $!";
        }
        my $size_left = length($data);
        my $offset    = 0;
        do {
            my $write_cnt = syswrite( $write_fh, $data, $size_left, $offset );
            unless ( defined $write_cnt ) {
                croak "write_file '$file' - syswrite: $!";
            }
            $size_left -= $write_cnt;
            $offset += $write_cnt;
        } while ( $size_left > 0 );
        truncate( $write_fh, sysseek( $write_fh, 0, SEEK_CUR ) )
    }
}

1;
