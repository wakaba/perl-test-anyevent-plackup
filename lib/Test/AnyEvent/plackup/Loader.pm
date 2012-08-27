package Test::AnyEvent::plackup::Loader;
use strict;
use warnings;
use parent 'Plack::Loader';

sub load {
    my ($class, $server, @args) = @_;
    push @args, server_ready => sub {
        kill 'USR1', getppid();
    };
    return $class->SUPER::load($server, @args);
}

1;
