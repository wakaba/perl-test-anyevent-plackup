use strict;
use warnings;
use Path::Class;
use lib file(__FILE__)->dir->parent->subdir('lib')->stringify;
use lib glob file(__FILE__)->dir->parent->subdir('t_deps', 'modules', '*', 'lib')->stringify;
use Test::X1;
use Test::More;
use Test::AnyEvent::plackup;
use Web::UserAgent::Functions qw(http_get);

test {
    my $c = shift;

    my $server = Test::AnyEvent::plackup->new;
    is_deeply $server->get_command, [
        'perl',
        '-I' . file(__FILE__)->dir->parent->subdir('lib'),
        do { my $v = `which plackup` || 'plackup'; chomp $v; $v },
        '--port' => $server->port,
    ];

    done $c;
} name => 'command default';

test {
    my $c = shift;

    my $server = Test::AnyEvent::plackup->new;
    $server->plackup('hoge/plackup');
    $server->app('path/to/app.psgi');
    $server->port(1244);
    $server->server('Twiggy');
    is_deeply $server->get_command, [
        'perl',
        '-I' . file(__FILE__)->dir->parent->subdir('lib'),
        'hoge/plackup',
        '--app' => 'path/to/app.psgi',
        '--port' => 1244,
        '--server' => 'Twiggy',
    ];

    done $c;
} name => 'command non-default';

test {
    my $c = shift;

    my $server = Test::AnyEvent::plackup->new;
    $server->perl('path/to/perl');
    is_deeply $server->get_command, [
        'path/to/perl',
        '-I' . file(__FILE__)->dir->parent->subdir('lib'),
        do { my $v = `which plackup` || 'plackup'; chomp $v; $v },
        '--port' => $server->port,
    ];

    done $c;
} name => 'command perl';

test {
    my $c = shift;

    my $server = Test::AnyEvent::plackup->new;
    $server->perl_inc(['path1', 'path2']);
    is_deeply $server->get_command, [
        'perl',
        '-Ipath1', '-Ipath2',
        '-I' . file(__FILE__)->dir->parent->subdir('lib'),
        do { my $v = `which plackup` || 'plackup'; chomp $v; $v },
        '--port' => $server->port,
    ];

    done $c;
} name => 'command perl lib';

test {
    my $c = shift;

    my $server = Test::AnyEvent::plackup->new;
    $server->perl('hoge');
    $server->perl_inc(['path1', 'path2']);
    is_deeply $server->get_command, [
        'hoge',
        '-Ipath1', '-Ipath2',
        '-I' . file(__FILE__)->dir->parent->subdir('lib'),
        do { my $v = `which plackup` || 'plackup'; chomp $v; $v },
        '--port' => $server->port,
    ];

    done $c;
} name => 'command perl and lib';

test {
    my $c = shift;

    my $code = q{
        use strict;
        use warnings;
        return sub {
            return [200, ['Content-Type' => 'text/plain'], ['hoge fuga']];
        };
    };

    my $server = Test::AnyEvent::plackup->new;
    $server->set_app_code($code);
    ok $server->app;

    my $f = file($server->app);
    is scalar $f->slurp, $code;

    undef $server;
    ok !-f $f;

    done $c;
} name => 'set_app_code';

test {
    my $c = shift;

    my $code = q{
        use strict;
        use warnings;
        return sub {
            return [200, ['Content-Type' => 'text/plain'], ['hoge fuga']];
        };
    };

    my $server = Test::AnyEvent::plackup->new;
    $server->set_app_code($code);

    my $cv = AE::cv;
    $cv->begin(sub { $_[0]->send });

    my ($start_cv, $end_cv) = $server->start_server;

    $cv->begin;
    my $port = $server->port;
    $start_cv->cb(sub {
        test {
            http_get 
                url => qq<http://localhost:$port/>,
                anyevent => 1,
                cb => sub {
                    my $res = $_[1];
                    test {
                        is $res->code, 200;
                        $server->stop_server;
                        $cv->end;
                    } $c;
                };
        } $c;
    });

    $cv->begin;
    $end_cv->cb(sub {
        my $return = $_[0]->recv;
        test {
            is $return >> 8, 0;
            http_get 
                url => qq<http://localhost:$port/>,
                anyevent => 1,
                cb => sub {
                    my $res = $_[1];
                    test {
                        like $res->code, qr/^59[56]$/;
                        $cv->end;
                    } $c;
                };
        } $c;
    });

    $cv->end;
    $cv->cb(sub {
        test {
            done $c;
        } $c;
    });
} name => 'server', n => 3;

test {
    my $c = shift;

    my $server = Test::AnyEvent::plackup->new;
    $server->app('hoge/fuga/notfound.psgi');

    my $cv = AE::cv;
    $cv->begin(sub { $_[0]->send });

    my ($start_cv, $end_cv) = $server->start_server;

    my $port = $server->port;
    $start_cv->cb(sub {
        test {
            ok 0;
        } $c;
    });

    $cv->begin;
    $end_cv->cb(sub {
        my $return = $_[0]->recv;
        test {
            ok $return >> 8;
            http_get 
                url => qq<http://localhost:$port/>,
                anyevent => 1,
                cb => sub {
                    my $res = $_[1];
                    test {
                        like $res->code, qr/^59[56]$/;
                        $cv->end;
                    } $c;
                };
        } $c;
    });

    $cv->end;
    $cv->cb(sub {
        test {
            undef $server;
            done $c;
        } $c;
    });
} name => 'server bad app', n => 2;

test {
    my $c = shift;
    my $server = Test::AnyEvent::plackup->new;

    my $path = $ENV{PATH};
    
    my %envs = ($server->envs);
    is_deeply \%envs, {%ENV};

    $server->set_env(PATH => 'hoge.fuga');
    my %envs2 = ($server->envs);
    is_deeply \%envs2, {%ENV, PATH => 'hoge.fuga'};
    is $envs2{PATH}, 'hoge.fuga';

    $server->set_env(PATH => undef);
    my %envs3 = ($server->envs);
    is_deeply \%envs3, {%ENV, PATH => undef};
    is $envs3{PATH}, undef;

    is $ENV{PATH}, $path;

    done $c;
} name => 'envs', n => 6;

run_tests;
