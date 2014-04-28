package Test::AnyEvent::plackup;
use strict;
use warnings;
our $VERSION = '2.0';
use File::Temp;
use AnyEvent;
use AnyEvent::Util;

sub new {
    return bless {options => {}, self_pid => $$}, $_[0];
}

# ------ Command construction ------

sub set_option {
    $_[0]->{options}->{$_[1]} = [$_[2]];
}

sub add_option {
    push @{$_[0]->{options}->{$_[1]} ||= []}, $_[2];
}

sub perl {
    if (@_ > 1) {
        $_[0]->{perl} = $_[1];
    }
    return $_[0]->{perl};
}

sub perl_inc {
    if (@_ > 1) {
        $_[0]->{perl_inc} = $_[1];
    }
    return $_[0]->{perl_inc} || [];
}

sub perl_options {
    if (@_ > 1) {
        $_[0]->{perl_options} = $_[1];
    }
    return $_[0]->{perl_options} || [];
}

sub _perl {
    my $self = shift;
    my $perl = $self->perl;
    my $perl_inc = $self->perl_inc;

    my $plackup_lib_dir_name = $INC{'Test/AnyEvent/plackup.pm'};
    $plackup_lib_dir_name =~ s{[/\\]Test[/\\]AnyEvent[/\\]plackup\.pm$}{};
    push @$perl_inc, $plackup_lib_dir_name;
    return (
        defined $perl ? $perl : 'perl',
        (map { "-I$_" } @$perl_inc),
        @{$self->perl_options},
    );
}

sub plackup {
    if (@_ > 1) {
        $_[0]->{plackup} = $_[1];
    }
    return $_[0]->{plackup} ||= do {
        my $plackup = `which plackup`;
        chomp $plackup;
        $plackup || 'plackup';
    };
}

sub app {
    if (@_ > 1) {
        $_[0]->set_option('--app' => $_[1]);
    }
    return $_[0]->{options}->{'--app'}->[0];
}

sub set_app_code {
    my ($self, $code) = @_;
    my $psgi_file_name = File::Temp->new(SUFFIX => '.psgi')->filename;
    $self->app($psgi_file_name);
    open my $psgi_file, '>:encoding(utf-8)', $psgi_file_name
        or die "$0: $psgi_file_name: $!";
    print $psgi_file $code;
    close $psgi_file;
    $self->{temp_psgi_file_name} = $psgi_file_name;
}

sub server {
    if (@_ > 1) {
        $_[0]->set_option('--server' => $_[1]);
    }
    return $_[0]->{options}->{'--server'}->[0];
}

sub port {
    if (@_ > 1) {
        $_[0]->set_option('--port' => $_[1]);
    }
    return defined $_[0]->{options}->{'--port'}->[0]
        ? $_[0]->{options}->{'--port'}->[0]
        : ($_[0]->{options}->{'--port'}->[0] = Test::AnyEvent::plackup::FindPort->find_listenable_port);
}

sub get_command {
    my $self = shift;
    my @cmd = (($self->_perl), $self->plackup);
    $self->port;
    for my $option (sort { $a cmp $b } keys %{$self->{options}}) {
        my $values = $self->{options}->{$option} or next;
        for my $value (@$values) {
            push @cmd, $option => $value;
        }
    }
    return \@cmd;
}

sub set_env {
    $_[0]->{envs}->{$_[1]} = $_[2];
}

sub envs {
    return (%ENV, %{$_[0]->{envs} or {}});
}

# ------ Server ------

sub onstdout {
    if (@_ > 1) {
        $_[0]->{onstdout} = $_[1];
    }
    return $_[0]->{onstdout};
}

sub onstderr {
    if (@_ > 1) {
        $_[0]->{onstderr} = $_[1];
    }
    return $_[0]->{onstderr};
}

sub pid {
    return $_[0]->{pid};
}

sub start_server {
    my $self = shift;

    local %ENV = ($self->envs);
    my $ready = File::Temp->newdir;
    my $ready_file_name = $ready->dirname . '/ready';
    $ENV{TEST_ANYEVENT_PLACKUP_READY_FILE_NAME} = $ready_file_name;
    
    my $command = $self->get_command;
    push @$command, '--loader' => '+Test::AnyEvent::plackup::Loader';
    my $pid;

    my $signal;
    my $w; $w = AnyEvent->signal(
        signal => 'USR1',
        cb => sub {
            if (-f $ready_file_name) {
                $signal++;
                undef $w;
                undef $ready;
            }
        },
    );

    #warn join ' ', @$command;
    my $cv = run_cmd
        $command,
        '>' => $self->onstdout || *STDOUT,
        '2>' => $self->onstderr || *STDERR,
        '$$' => \$pid,
    ;
    $self->{pid} = $pid;

    my $cv_start = AE::cv;
    my $cv_end = AE::cv;

    my $port = $self->port;
    my $time = 0;
    my $timer; $timer = AE::timer 0, 0.6, sub {
        $time += 0.6;
        if ($time > 20) {
            undef $timer;
            warn "plackup timeout!\n";
            $cv_start->send(1);
        }
        if ($signal) {
            $cv_start->send(0);
            undef $timer;
        }
    };

    $cv->cb(sub {
        my $return = $_[0]->recv;
        if ($return >> 8) {
            warn "Can't start plackup: " . $return;
        }
        undef $timer;
        $cv_end->send($return);
    });

    return ($cv_start, $cv_end);
}

sub stop_server {
    my $self = shift;
    if ($self->{pid}) {
        kill 15, $self->{pid}; # SIGTERM
        delete $self->{pid} if kill 0, $self->{pid};
    }
}

sub DESTROY {
    return unless ($_[0]->{self_pid} || 0) == $$;
    {
        local $@;
        eval { die };
        if ($@ =~ /during global destruction/) {
            warn "Detected (possibly) memory leak";
        }
    }
    $_[0]->stop_server if $_[0]->{pid};
    if ($_[0]->{temp_psgi_file_name}) {
        unlink $_[0]->{temp_psgi_file_name};
    }
}

package Test::AnyEvent::plackup::FindPort;
use Socket;

our $EphemeralStart = 1024;
our $EphemeralEnd = 5000;

our $UsedPorts = {};

sub is_listenable_port {
    my ($class, $port) = @_;
    return 0 unless $port;
    return 0 if $UsedPorts->{$port};
    
    my $proto = getprotobyname('tcp');
    socket(my $server, PF_INET, SOCK_STREAM, $proto) || die "socket: $!";
    setsockopt($server, SOL_SOCKET, SO_REUSEADDR, pack("l", 1)) || die "setsockopt: $!";
    bind($server, sockaddr_in($port, INADDR_ANY)) || return 0;
    listen($server, SOMAXCONN) || return 0;
    close($server);
    return 1;
}

sub find_listenable_port {
    my $class = shift;
    
    for (1..10000) {
        my $port = int rand($EphemeralEnd - $EphemeralStart);
        next if $UsedPorts->{$port};
        if ($class->is_listenable_port($port)) {
            $UsedPorts->{$port} = 1;
            return $port;
        }
    }

    die "Listenable port not found";
}

sub clear_cache {
    $UsedPorts = {};
}

1;
