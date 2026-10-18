package Presenter::Output;
use strict;
use warnings;
use Storable qw(dclone);

# Pure state machine: callers supply milliseconds and own the event loop.
sub new { bless {revision => 0, stage => 'hidden', run => undef, pending => undef}, shift }
sub snapshot {
    my ($self, $now) = @_;
    return dclone({revision => $self->{revision}, serverNow => $now,
        phase => $self->{stage}, run => $self->{run}, pending => $self->{pending}});
}
sub _start {
    my ($self, $cue, $now) = @_;
    $self->{run} = {cue => dclone($cue), startedAt => $now,
        enterMs => $cue->{enterMs}, exitMs => $cue->{exitMs},
        exitAt => $now + $cue->{enterMs} + $cue->{holdMs}, exitFrom => 1};
    $self->{stage} = 'entering';
    $self->{revision}++;
}
sub _exit {
    my ($self, $now) = @_;
    my $run = $self->{run} or return;
    return if $now >= $run->{exitAt};
    $run->{exitFrom} = ($now - $run->{startedAt}) / $run->{enterMs};
    $run->{exitFrom} = 1 if $run->{exitFrom} > 1;
    $run->{exitAt} = $now;
    $self->{stage} = 'exiting';
    $self->{revision}++;
}
sub tick {
    my ($self, $now) = @_;
    my $before = $self->{revision};
    my $run = $self->{run} or return 0;
    if ($now >= $run->{exitAt} + $run->{exitMs}) {
        my $pending = delete $self->{pending};
        $self->{run} = undef;
        $self->{pending} = undef;
        $self->{stage} = 'hidden';
        $self->{revision}++;
        $self->_start($pending, $now) if $pending;
    } else {
        my $stage = $now >= $run->{exitAt} ? 'exiting'
                  : $now >= $run->{startedAt} + $run->{enterMs} ? 'holding' : 'entering';
        if ($stage ne $self->{stage}) { $self->{stage} = $stage; $self->{revision}++ }
    }
    return $self->{revision} != $before;
}
sub command {
    my ($self, $action, $cue, $now) = @_;
    $self->tick($now);
    if ($action eq 'clear') {
        @$self{qw(run pending stage)} = (undef, undef, 'hidden');
        $self->{revision}++;
    } elsif ($action eq 'hide') {
        $self->{pending} = undef;
        $self->_exit($now);
        $self->{revision}++;
    } elsif ($action eq 'trigger' || $action eq 'show') {
        my $run = $self->{run};
        if (!$run) { $self->_start($cue, $now) }
        elsif ($run->{cue}{id} eq $cue->{id}) {
            # Explicit show is idempotent. Trigger takes an active cue out.
            if ($action eq 'trigger') {
                $self->{pending} = undef;
                $self->_exit($now);
                $self->{revision}++;
            }
        } else {
            $self->{pending} = dclone($cue);
            $self->_exit($now);
            $self->{revision}++;
        }
    } else { die "Unknown action\n" }
    return $self->snapshot($now);
}
1;
