#!perl
use strict;
use utf8;
use warnings qw(all);

use Test::More;

use AnyEvent::Net::Curl::Queued;
use AnyEvent::Net::Curl::Queued::Easy;

my $q = AnyEvent::Net::Curl::Queued->new;

$q->append(
    AnyEvent::Net::Curl::Queued::Easy->new({
        initial_url => 'http://255.255.255.255/',
        on_finish   => sub {
            my ($self, $result) = @_;
            ok($self->has_error, "error detected");
            ok($result == Net::Curl::Easy::CURLE_COULDNT_CONNECT, "couldn't connect");
        },
        retry => 3,
    })
);

$q->wait;

done_testing(6);