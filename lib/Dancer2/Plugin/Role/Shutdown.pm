use strictures 2;

package # for internal use only
    Dancer2::Plugin::Role::Shutdown;

# ABSTRACT: Role for L<Dancer2::Plugin::Shutdown>

use Carp qw(croak);
use Class::Load qw(load_class);
use Scalar::Util qw(blessed);
use Moo::Role 2;

use constant NORMAL => 0;
use constant GRACEFUL => 1;

# VERSION

=attr shared

=cut

has shared => (
    is => 'rwp',
    default => sub { {} },
);

=attr validator

=cut

has validator => (
    is => 'rw',
    default => sub {
        sub {
            my ($app, $rest, $sessid) = @_;
            return unless $sessid;
            my $sx = $app->session->expires // 0;
            $app->session->expires($rest) if $rest > $sx;
            $app->response->header(Warning => "199 Application shuts down in $rest seconds");
            return 1;
        }
    }
);

=func has_valid_session

=cut

sub has_valid_session {
    my $app = shift; 

    my $engine = $app->session_engine // return;

    return if $app->has_destroyed_session;

    my $session_cookie = $app->cookie( $engine->cookie_name ) // return;
    my $session_id = $session_cookie->value // return;

    eval  { $engine->retrieve( id => $session_id ) };
    return if $@;

    return $session_id;
}

=func session_status

=cut

sub session_status {
    my $app = shift; 

    my $engine = $app->session_engine // return "unsupported";

    return "destroyed" if $app->has_destroyed_session;

    my $session_cookie = $app->cookie( $engine->cookie_name ) // return "missing";
    my $session_id = $session_cookie->value // return "empty";

    eval  { $engine->retrieve( id => $session_id ) };
    return "invalid" if $@;

    return "ok";
}

=method before_hook

=cut

sub before_hook {
    my $self = shift;
    return unless $self->shared->{state};
    my $app  = $self->app;
    my $time = $self->shared->{final};
    my $rest = $time - time;
    if ($rest < 0) {
        $self->status(503);
        $self->halt;
    } elsif ($self->shared->{state} == GRACEFUL) {
        if (my $validator = $self->validator) {
            my $sessid = has_valid_session($app);
            unless ($validator->($app, $rest, $sessid)) {
                $self->status(503);
                $self->halt;
            }
        }
    } else {
      croak "bad state: ".$self->shared->{state};
    }
}

sub _shutdown_at {
    my $self = shift;
    croak "a validator isn't installed yet" unless ref $self->validator eq 'CODE';
    my $time = shift // 0;
    if ($time < time) {
        $time += time;
    }
    $self->shared->{final} = $time;
    $self->shared->{state} = GRACEFUL;
    return $time;
}

1;
