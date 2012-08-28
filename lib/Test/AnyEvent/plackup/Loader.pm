package Test::AnyEvent::plackup::Loader;
use strict;
use warnings;
use parent 'Plack::Loader';

sub load {
    my ($class, $server, @args) = @_;
    push @args, server_ready => sub {
        my $ready_file_name = $ENV{TEST_ANYEVENT_PLACKUP_READY_FILE_NAME};
        if ($ready_file_name) {
            open my $file, '>', $ready_file_name
                or die "$0: $ready_file_name: $!";
            close $file;
        }
        kill 'USR1', getppid();
    };
    return $class->SUPER::load($server, @args);
}

1;
