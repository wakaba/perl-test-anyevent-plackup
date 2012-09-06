use strict;
use warnings;
use Path::Class;
use lib file(__FILE__)->dir->parent->subdir('lib')->stringify;
use lib glob file(__FILE__)->dir->parent->subdir('t_deps', 'modules', '*', 'lib')->stringify;
use Test::X1;
use Test::More;
use Test::AnyEvent::plackup;
use AnyEvent;
use Web::UserAgent::Functions qw(http_get);

test {
    my $c = shift;

    my $code = q{
        return sub {
            return [200, ['Content-Type' => 'text/plain'], ['hoge fuga']];
        };
    };

    my $server1 = Test::AnyEvent::plackup->new;
    $server1->set_app_code($code);
    my ($start_cv1) = $server1->start_server;

    my $server2 = Test::AnyEvent::plackup->new;
    $server2->set_app_code($code);
    my ($start_cv2) = $server2->start_server;

    my $cv = AE::cv;
    $cv->begin;

    for ([$start_cv1, $server1], [$start_cv2, $server2]) {
        my ($start_cv, $server) = @$_;
        $cv->begin;
        $start_cv->cb(sub {
            test {
                my $port = $server->port;
                http_get url => qq<http://localhost:$port/>, anyevent => 1, cb => sub {
                    my (undef, $res) = @_;
                    test {
                        is $res->code, 200;
                        $cv->end;
                    } $c;
                };
            } $c;
        });
    }

    $cv->end;
    $cv->cb(sub {
        test {
            done $c;
            undef $c;
        } $c;
    });
} n => 2;

run_tests;
