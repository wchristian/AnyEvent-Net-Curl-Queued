package AnyEvent::Net::Curl::Queued;
use common::sense;

use AnyEvent;
use Moose;
use Moose::Util::TypeConstraints;
use Net::Curl::Share qw(:constants);

use AnyEvent::Net::Curl::Queued::Multi;

# active sessions counter
has active      => (
    traits      => ['Counter'],
    is          => 'ro',
    isa         => 'Int',
    default     => 0,
    handles     => {qw{
        inc_active  inc
        dec_active  dec
    }},
);

# AnyEvent condition variable
has cv          => (is => 'ro', isa => 'AnyEvent::CondVar', default => sub { AE::cv }, lazy => 1);

# max parallel connections
subtype 'MaxConn'
    => as Int
    => where { $_ >= 2 };
has max         => (is => 'ro', isa => 'MaxConn', default => 4);

# Net::Curl::Multi object
has multi       => (is => 'rw', isa => 'AnyEvent::Net::Curl::Queued::Multi');

# our queue
has queue       => (
    traits      => ['Array'],
    is          => 'ro',
    isa         => 'ArrayRef[Any]',
    default     => sub { [] },
    handles     => {qw{
        queue_push      push
        queue_unshift   unshift
        dequeue         shift
        count           count
    }},
);

# Net::Curl::Share object
has share       => (is => 'ro', isa => 'Net::Curl::Share', default => sub { Net::Curl::Share->new }, lazy => 1);

# stats accumulator
has stats       => (is => 'ro', isa => 'AnyEvent::Net::Curl::Queued::Stats', default => sub { AnyEvent::Net::Curl::Queued::Stats->new }, lazy => 1);

# default timeout
has timeout     => (is => 'ro', isa => 'Num', default => 10.0);

# prevent repeated accesses
has unique      => (is => 'ro', isa => 'HashRef[Str]', default => sub { {} });

sub BUILD {
    my ($self) = @_;

    $self->multi(
        AnyEvent::Net::Curl::Queued::Multi->new({
            timeout     => $self->timeout,
        })
    );

    $self->share->setopt(CURLSHOPT_SHARE, CURL_LOCK_DATA_COOKIE);   # 2
    $self->share->setopt(CURLSHOPT_SHARE, CURL_LOCK_DATA_DNS);      # 3
}

sub start {
    my ($self) = @_;

    # populate queue
    $self->add($self->dequeue)
        while
            $self->count
            and ($self->active < $self->max);
}

sub add {
    my ($self, $worker) = @_;

    # vivify the worker
    $worker = $worker->()
        if ref($worker) eq 'CODE';

    # self-reference & warmup
    $worker->queue($self);
    $worker->init;

    # check if already processed
    if (my $unique = $worker->unique) {
        return if ++$self->unique->{$unique} > 1;
    }

    # fire
    $self->inc_active;
    $self->cv->begin;
    $self->multi->add_handle($worker);
}

sub append {
    my ($self, $worker) = @_;

    $self->queue_push($worker);
    $self->start;
}

sub prepend {
    my ($self, $worker) = @_;

    $self->queue_unshift($worker);
    $self->start;
}

no Moose;
__PACKAGE__->meta->make_immutable;

1;
