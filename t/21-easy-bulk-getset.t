#!perl
use strict;
use utf8;
use warnings qw(all);

use lib qw(inc);

use Test::More;
diag('setopt()/getinfo() are *forced* to fail so warnings are OK here!');

use AnyEvent::Net::Curl::Queued;
use AnyEvent::Net::Curl::Queued::Easy;
use Test::HTTP::Server;
use URI;

use Net::Curl::Easy qw(:constants);

my $server = Test::HTTP::Server->new;
# disable proxy!
@ENV{qw(http_proxy ftp_proxy all_proxy)} = ('' x 3);

my $url = URI->new($server->uri . 'echo/head');

my $easy = new AnyEvent::Net::Curl::Queued::Easy({ initial_url => $url });
isa_ok($easy, qw(AnyEvent::Net::Curl::Queued::Easy));
can_ok($easy, qw(
    getinfo
    perform
    setopt
));

$easy->init;

my $useragent = "Net::Curl/$Net::Curl::VERSION Perl/$] ($^O)";
$easy->setopt(
    CURLOPT_ENCODING,   '',
    CURLOPT_USERAGENT,  $useragent,
);

my $referer = $server->uri;
$easy->setopt(
    referer             => $referer,
    'http-version'      => CURL_HTTP_VERSION_1_0,
);

$easy->setopt({
    PostFields          => 'test1=12345&test2=QWERTY',
});

# make Devel::Cover happy
$easy->setopt();
$easy->setopt($easy);

ok($easy->perform == Net::Curl::Easy::CURLE_OK, 'perform()');

my $buf = ${$easy->data};
like($buf, qr{^POST\b}, 'POST');
like($buf, qr{\bHTTP/1\.0\b}, 'HTTP/1.0');
like($buf, qr{\bAccept-Encoding:\s+}s, 'Accept-Encoding');
like($buf, qr{\bUser-Agent:\s+\Q$useragent}s, 'User-Agent');
like($buf, qr{\bReferer:\s+\Q$referer}s, 'Referer');
like($buf, qr{\bContent-Type:\s+application/x-www-form-urlencoded\b}s, 'Content-Type');

my @names = qw(
    content_type
    effective_url
    primary_ip
    response_code
    size_download
    INVALID.NAME
);

my $info = {
    map { $_ => 0 }
    @names
};

$easy->getinfo($info);

ok($info->{content_type} =~ m{^text/plain\b}, 'text/plain');
ok($info->{effective_url} eq $url->as_string, 'URL');
ok($info->{primary_ip} eq $url->host, 'host');
ok($info->{response_code} == 200, '200 OK');

my $info2 = $easy->getinfo({%{$info}});
my @info = $easy->getinfo(\@names);

my $i = 0;
for (@names) {
    if (m{^\w+$}) {
        ok($info->{$_} eq $info2->{$_}, "field '$_' match for getinfo(HASH)");
        ok($info->{$_} eq $info[$i], "field '$_' match for getinfo(ARRAY)");
    } else {
        is($info->{$_}, 0, 'getinfo(HASHREF) with INVALID.NAME');
        is($info2->{$_}, undef, 'getinfo(HASH) with INVALID.NAME');
        is($info[$i], undef, 'getinfo(ARRAY) with INVALID.NAME');
    }
    ++$i;
}

is($easy->getinfo($easy), undef, 'getinfo(bad object)');
is($easy->getinfo('INVALID.NAME'), undef, 'getinfo("INVALID.NAME")');

done_testing(28);
