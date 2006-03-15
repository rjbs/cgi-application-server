
package CGI::Application::Server;

use strict;
use warnings;
use Carp;

use Carp         'confess';
use Scalar::Util 'blessed', 'reftype';

our $VERSION = '0.01';

use base qw(HTTP::Server::Simple::CGI HTTP::Server::Simple::Static);

use HTTP::Response;
use HTTP::Status;

use IO::Capture::Stdout;

# HTTP::Server::Simple methods

sub new {
	my $class = shift;
	my $self  = $class->SUPER::new(@_); 
	$self->{entry_points} = {};	
	$self->{document_root}  = '.';
	return $self;
}

# accessors

sub document_root {
	my ($self, $document_root) = @_;
	if (defined $document_root) {
		(-d $document_root)
			|| confess "The server root ($document_root) is not found";
		$self->{document_root} = $document_root;
	}
	$self->{document_root};
}

sub entry_points {
	my ($self, $entry_points) = @_;
	if (defined $entry_points) {
		(reftype($entry_points) && reftype($entry_points) eq 'HASH')
			|| confess "The entry points map must be a HASH reference, not $entry_points";
		$self->{entry_points} = $entry_points;
	}
	$self->{entry_points};	
}

# check request

sub is_valid_entry_point {
	my ($self, $uri) = @_;
	foreach my $entry_point (keys %{$self->{entry_points}}) {
		return $self->{entry_points}->{$entry_point}
			if index($uri, $entry_point) == 0;
	}
	return undef;
}

sub handle_request {
	my ($self, $cgi) = @_;
	if (my $entry_point = $self->is_valid_entry_point($ENV{REQUEST_URI})) {
        my $capture = IO::Capture::Stdout->new;
        $capture->start;
		$entry_point->new->run;		
        $capture->stop;
        my $stdout = join "\x0d\x0a", $capture->read;
        my $response = $self->_build_response( $stdout );
        print $response->as_string;
	}
	else {
    	return $self->serve_static($cgi, $self->document_root);
	} 
}

# Shamelessly stolen from HTTP::Request::AsCGI by chansen
sub _build_response {
    my ( $self, $stdout ) = @_;

    $stdout =~ s{(.*\x0d?\x0a\x0d?\x0a)}{}xsm;
    my $headers = $1;

    unless ( defined $headers ) {
        $headers = "HTTP/1.1 500 Internal Server Error\x0d\x0a";
    }

    unless ( $headers =~ /^HTTP/ ) {
        $headers = "HTTP/1.1 200 OK\x0d\x0a" . $headers;
    }

    my $response = HTTP::Response->parse($headers);
    $response->date( time() ) unless $response->date;

    my $message = $response->message;
    my $status  = $response->header('Status');

    if ( $message && $message =~ /^(.+)\x0d$/ ) {
        $response->message($1);
    }

    if ( $status && $status =~ /^(\d\d\d)\s?(.+)?$/ ) {

        my $code    = $1;
        my $message = $2 || HTTP::Status::status_message($code);

        $response->code($code);
        $response->message($message);
    }
    
    my $length = length $stdout;

    if ( $response->code == 500 && !$length ) {

        $response->content( $response->error_as_HTML );
        $response->content_type('text/html');

        return $response;
    }

    $response->add_content($stdout);
    $response->content_length($length);

    return $response;
}


1;

__END__

=pod

=head1 NAME

CGI::Application::Server - A HTTP::Server::Simple subclass for developing CGI::Application

=head1 SYNOPSIS

  use CGI::Application::Server;

  my $server = CGI::Application::Server->new();
  $server->document_root('./htdocs');
  $server->entry_points({
	  '/index.cgi' => 'MyCGIApp',
	  '/admin'     => 'MyCGIApp::Admin'
  });
  $server->run();

=head1 DESCRIPTION

This is a simple L<HTTP::Server::Simple> subclass for use during 
development with L<CGI::Appliaction>. 

=head1 METHODS

=over 4

=item B<new ($port)>

This acts just like C<new> for L<HTTP::Server::Simple>, except it 
will initialize instance slots that we use.

=item B<handle_request>

This will check the request uri and dispatch appropriately, either 
to an entry point, or serve a static file (html, jpeg, gif, etc).

=item B<entry_points (?$entry_points)>

This accepts a HASH reference in C<$entry_points>, which maps 
server entry points (uri) to L<CGI::Application> class names. 
See the L<SYNOPSIS> above for an example.

=item B<is_valid_entry_point ($uri)>

This attempts to match the C<$uri> to an entry point.

=item B<document_root (?$document_root)>

This is the server's document root where all static files will 
be served from.

=back

=head1 BUGS

All complex software has bugs lurking in it, and this module is no 
exception. If you find a bug please either email me, or add the bug
to cpan-RT.

=head1 CODE COVERAGE

I use L<Devel::Cover> to test the code coverage of my tests, below 
is the L<Devel::Cover> report on this module's test suite.

=head1 ACKNOWLEDGEMENTS

=head1 AUTHOR

Stevan Little E<lt>stevan@iinteractive.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright 2006 by Infinity Interactive, Inc.

L<http://www.iinteractive.com>

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself. 

=cut
