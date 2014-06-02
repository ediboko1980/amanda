# vim:ft=perl
# Copyright (c) 2008-2012 Zmanda, Inc.  All Rights Reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
# or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
#
# Contact information: Zmanda Inc, 465 S. Mathilda Ave., Suite 300
# Sunnyvale, CA 94086, USA, or: http://www.zmanda.com

package Installcheck::Rest;

use Amanda::Paths;
use Amanda::Debug;
use WWW::Curl::Easy;
use JSON;

=head1 NAME

Installcheck::Rest - utilities to start/stop the Rest server.

=head1 SYNOPSIS

  use Installcheck::Rest;

  # start the Rest server.
  Installcheck::Rest::start();

  #make request to the Rest server.
  # ...

  # stop the Rest server.
  Installcheck::Rest::stop();

=cut

sub DESTROY {
    stop();
}

sub new {
    my $class = shift;

    my $curl = WWW::Curl::Easy->new;
    if (!defined $curl) {
	die("Can't run curl");
    }
    my $json = JSON->new->allow_nonref;

    my $pid = fork;
    if ($pid == 0) {
	Amanda::Debug::debug_dup_stderr_to_debug();
	exec("starman", "--env", "development", "--port", "5001", "$Amanda::Paths::amperldir/Amanda/Rest/Amanda/bin/app.pl");
	exit(-1);
    } elsif ($pid < 0) {
	die("Can't fork for rest server");
    }

    # Wait for the server to start
    sleep 1;

    use POSIX ":sys_wait_h";
    my $kid = waitpid($pid, WNOHANG);

    my $self = {
	pid  => $pid,
	curl => $curl,
	json => $json
    };
    if ($kid == $pid) {
	$self->{'error'} = $kid;
    }
    bless $self, $class;
    return $self;
}

sub stop {
    my $self = shift;

    if (defined $self->{'pid'}) {
	kill 'TERM', $self->{'pid'};
	$self->{'pid'} = undef;
    }
}

sub get {
    my $self = shift;
    my $url = shift;

    $self->{'curl'}->setopt(CURLOPT_HEADER, 0);
    $self->{'curl'}->setopt(CURLOPT_URL, $url);
    $self->{'curl'}->setopt(CURLOPT_POST, 0);

    my $response_body;
    $self->{'curl'}->setopt(CURLOPT_WRITEDATA,\$response_body);

    my $retcode = $self->{'curl'}->perform;

    if ($retcode == 0) {
	return {
	    http_code => $self->{'curl'}->getinfo(CURLINFO_HTTP_CODE),
	    body      => $self->{'json'}->decode($response_body),
	};
    } else {
	die("An error happened: $retcode ".$self->{'curl'}->strerror($retcode)." ".$self->{'curl'}->errbuf."\n");
    }
}

sub post {
    my $self = shift;
    my $url = shift;
    my $postfields = shift;

    $self->{'curl'}->setopt(CURLOPT_HEADER, 0);
    $self->{'curl'}->setopt(CURLOPT_URL, $url);
    $self->{'curl'}->setopt(CURLOPT_POST, 1);
    $self->{'curl'}->setopt(CURLOPT_POSTFIELDS, $postfields);
    $self->{'curl'}->setopt(CURLOPT_INFILESIZE_LARGE, 0);
    $self->{'curl'}->setopt(CURLOPT_HTTPHEADER, [
		"Content-Type: application/json; charset=utf-8" ]);

    my $response_body;
    $self->{'curl'}->setopt(CURLOPT_WRITEDATA,\$response_body);

    my $retcode = $self->{'curl'}->perform;

    if ($retcode == 0) {
	my $http_code = $self->{'curl'}->getinfo(CURLINFO_HTTP_CODE);
	if ($http_code >= 500) {
	    return {
		http_code => $http_code,
	    };
	} else {
	    return {
		http_code => $http_code,
		body      => $self->{'json'}->decode($response_body),
	    };
	}
    } else {
	die("An error happened: $retcode ".$self->{'curl'}->strerror($retcode)." ".$self->{'curl'}->errbuf."\n");
    }
}

1;