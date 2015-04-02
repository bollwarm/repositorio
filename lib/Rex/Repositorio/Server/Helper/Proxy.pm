package Rex::Repositorio::Server::Helper::Proxy;

use base 'Mojolicious::Plugin';

# VERSION

sub register {
  my ( $self, $app ) = @_;

  $app->helper(
    proxy_to => sub {
      my $c       = shift;
      my $url     = Mojo::URL->new(shift);
      my $cb      = shift || sub { };
      my $filter  = shift;
      my $headers = shift || {};

      $c->inactivity_timeout(900);

      my $ua = $c->ua;
      $ua->max_redirects(5);

      if ( $c->repo->{ca} ) {
        $ua->ca( $c->repo->{ca} );
      }
      if ( $c->repo->{key} ) {
        $ua->key( $c->repo->{key} );
      }
      if ( $c->repo->{cert} ) {
        $ua->cert( $c->repo->{cert} );
      }

      my %args = @_;
      $url->query( $c->req->params ) if ( $args{with_query_params} );

      if ( Mojo::IOLoop->is_running ) {
        $c->render_later;
        $ua->get(
          $url, $headers,
          sub {
            my ( $self, $tx ) = @_;
            _proxy_tx( $c, $tx, $cb, $filter );
          }
        );
      }
      else {
        my $tx = $ua->get( $url, $headers );
        _proxy_tx( $c, $tx, $cb, $filter );
      }
    }
  );
}

sub _proxy_tx {
  my ( $self, $tx, $cb, $filter ) = @_;
  if ( my $res = $tx->success ) {
    if ( ref $filter eq "CODE" ) {
      $filter->( $self, $tx );
    }

    $self->tx->res($res);
    $self->rendered;
    $cb->( $self, $tx );
  }
  else {
    my $error = $tx->error;
    $self->tx->res->headers->add( 'X-Remote-Status',
      $error->{code} . ': ' . $error->{message} );
    $self->render( status => 500, text => 'Failed to fetch data from backend' );
  }
}

1;
