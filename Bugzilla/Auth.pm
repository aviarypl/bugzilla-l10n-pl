# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Netscape Communications
# Corporation. Portions created by Netscape are
# Copyright (C) 1998 Netscape Communications Corporation. All
# Rights Reserved.
#
# Contributor(s): Bradley Baetz <bbaetz@acm.org>
#                 Erik Stambaugh <erik@dasbistro.com>

package Bugzilla::Auth;

use strict;
use base qw(Exporter);
@Bugzilla::Auth::EXPORT = qw(bz_crypt);

use Bugzilla::Config;
use Bugzilla::Constants;

# The verification method that was successfully used upon login, if any
my $current_verify_class = undef;

# 'inherit' from the main verify method
BEGIN {
    for my $verifyclass (split /,\s*/, Param("user_verify_class")) {
        if ($verifyclass =~ /^([A-Za-z0-9_\.\-]+)$/) {
            $verifyclass = $1;
        } else {
            die "Badly-named user_verify_class '$verifyclass'";
        }
        require "Bugzilla/Auth/Verify/" . $verifyclass . ".pm";
    }
}

sub bz_crypt ($) {
    my ($password) = @_;

    # The list of characters that can appear in a salt.  Salts and hashes
    # are both encoded as a sequence of characters from a set containing
    # 64 characters, each one of which represents 6 bits of the salt/hash.
    # The encoding is similar to BASE64, the difference being that the
    # BASE64 plus sign (+) is replaced with a forward slash (/).
    my @saltchars = (0..9, 'A'..'Z', 'a'..'z', '.', '/');

    # Generate the salt.  We use an 8 character (48 bit) salt for maximum
    # security on systems whose crypt uses MD5.  Systems with older
    # versions of crypt will just use the first two characters of the salt.
    my $salt = '';
    for ( my $i=0 ; $i < 8 ; ++$i ) {
        $salt .= $saltchars[rand(64)];
    }

    # Crypt the password.
    my $cryptedpassword = crypt($password, $salt);

    # Return the crypted password.
    return $cryptedpassword;
}

# PRIVATE

# A number of features, like password change requests, require the DB
# verification method to be on the list.
sub has_db {
    for (split (/[\s,]+/, Param("user_verify_class"))) {
        if (/^DB$/) {
            return 1;
        }
    }
    return 0;
}

# Returns the network address for a given ip
sub get_netaddr {
    my $ipaddr = shift;

    # Check for a valid IPv4 addr which we know how to parse
    if (!$ipaddr || $ipaddr !~ /^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/) {
        return undef;
    }

    my $addr = unpack("N", pack("CCCC", split(/\./, $ipaddr)));

    my $maskbits = Param('loginnetmask');

    $addr >>= (32-$maskbits);
    $addr <<= (32-$maskbits);
    return join(".", unpack("CCCC", pack("N", $addr)));
}

# This is a replacement for the inherited authenticate function
# go through each of the available methods for each function
sub authenticate {
    my $class = shift;
    my @args   = @_;
    my @firstresult = ();
    my @result = ();
    for my $method (split /,\s*/, Param("user_verify_class")) {
        $method = "Bugzilla::Auth::Verify::" . $method;
        @result = $method->authenticate(@args);
        @firstresult = @result unless @firstresult;

        if (($result[0] != AUTH_NODATA)&&($result[0] != AUTH_LOGINFAILED)) {
            $current_verify_class = $method;
            return @result;
        }
    }
    @result = @firstresult;
    # no auth match

    # see if we can set $current to the first verify method that
    # will allow a new login

    for my $method (split /,\s*/, Param("user_verify_class")) {
        $method = "Bugzilla::Auth::Verify::" . $method;
        if ($method->can_edit('new')) {
            $current_verify_class = $method;
        }
    }

    return @result;
}

sub can_edit {
    my ($class, $type) = @_;
    if ($current_verify_class) {
        return $current_verify_class->can_edit($type);
    }
    # $current_verify_class will not be set if the user isn't logged in.  That
    # happens when the user is trying to create a new account, which (for now)
    # is hard-coded to work with DB.
    elsif (has_db) {
        return Bugzilla::Auth::Verify::DB->can_edit($type);
    }
    return 0;
}

1;

__END__

=head1 NAME

Bugzilla::Auth - Authentication handling for Bugzilla users

=head1 SYNOPSIS

  # Class Functions
  $crypted = bz_crypt($password);

=head1 DESCRIPTION

Handles authentication for Bugzilla users.

Authentication from Bugzilla involves two sets of modules. One set is
used to obtain the data (from CGI, email, etc), and the other set uses
this data to authenticate against the datasource (the Bugzilla DB, LDAP,
cookies, etc).

Modules for obtaining the data are located under L<Bugzilla::Auth::Login>, and
modules for authenticating are located in L<Bugzilla::Auth::Verify>.

=head1 METHODS

C<Bugzilla::Auth> contains several helper methods to be used by
authentication or login modules.

=over 4

=item C<bz_crypt($password)>

Takes a string and returns a C<crypt>ed value for it, using a random salt.

Please always use this function instead of the built-in perl "crypt"
when initially encrypting a password.

=begin undocumented

Random salts are generated because the alternative is usually
to use the first two characters of the password itself, and since
the salt appears in plaintext at the beginning of the encrypted
password string this has the effect of revealing the first two
characters of the password to anyone who views the encrypted version.

=end undocumented

=item C<Bugzilla::Auth::get_netaddr($ipaddr)>

Given an ip address, this returns the associated network address, using
C<Param('loginnetmask')> as the netmask. This can be used to obtain data
in order to restrict weak authentication methods (such as cookies) to
only some addresses.

=back

=head1 AUTHENTICATION

Authentication modules check a user's credentials (username, password,
etc) to verify who the user is.  The methods that C<Bugzilla::Auth> uses for
authentication are wrappers that check all configured modules (via the
C<Param('user_info_class')> and C<Param('user_verify_class')>) in sequence.

=head2 METHODS

=over 4

=item C<authenticate($username, $pass)>

This method is passed a username and a password, and returns a list
containing up to four return values, depending on the results of the
authentication.

The first return value is one of the status codes defined in
L<Bugzilla::Constants|Bugzilla::Constants> and described below.  The
rest of the return values are status code-specific and are explained in
the status code descriptions.

=over 4

=item C<AUTH_OK>

Authentication succeeded. The second variable is the userid of the new
user.

=item C<AUTH_NODATA>

Insufficient login data was provided by the user. This may happen in several
cases, such as cookie authentication when the cookie is not present.

=item C<AUTH_ERROR>

An error occurred when trying to use the login mechanism. The second return
value may contain the Bugzilla userid, but will probably be C<undef>,
signifiying that the userid is unknown. The third value is a tag describing
the error used by the authentication error templates to print a description
to the user. The optional fourth argument is a hashref of values used as part
of the tag's error descriptions.

This error template must have a name/location of
I<account/auth/C<lc(authentication-type)>-error.html.tmpl>.

=item C<AUTH_LOGINFAILED>

An incorrect username or password was given. Note that for security reasons,
both cases return the same error code. However, in the case of a valid
username, the second argument may be the userid. The authentication
mechanism may not always be able to discover the userid if the password is
not known, so whether or not this argument is present is implementation
specific. For security reasons, the presence or lack of a userid value should
not be communicated to the user.

The third argument is an optional tag from the authentication server
describing the error. The tag can be used by a template to inform the user
about the error.  Similar to C<AUTH_ERROR>, an optional hashref may be
present as a fourth argument, to be used by the tag to give more detailed 
information.

=item C<AUTH_DISABLED>

The user successfully logged in, but their account has been disabled.
The second argument in the returned array is the userid, and the third
is some text explaining why the account was disabled. This text would
typically come from the C<disabledtext> field in the C<profiles> table.
Note that this argument is a string, not a tag.

=back

=item C<current_verify_class>

This scalar gets populated with the full name (eg.,
C<Bugzilla::Auth::Verify::DB>) of the verification method being used by the
current user.  If no user is logged in, it will contain the name of the first
method that allows new users, if any.  Otherwise, it carries an undefined
value.

=item C<can_edit>

This determines if the user's account details can be modified.  It returns a
reference to a hash with the keys C<userid>, C<login_name>, and C<realname>,
which determine whether their respective profile values may be altered, and
C<new>, which determines if new accounts may be created.

Each user verification method (chosen with C<Param('user_verify_class')> has
its own set of can_edit values.  Calls to can_edit return the appropriate
values for the current user's login method.

If a user is not logged in, C<can_edit> will contain the values of the first
verify method that allows new users to be created, if available.  Otherwise it
returns an empty hash.

=back

=head1 LOGINS

A login module can be used to try to log in a Bugzilla user in a
particular way. For example,
L<Bugzilla::Auth::Login::WWW::CGI|Bugzilla::Auth::Login::WWW::CGI>
logs in users from CGI scripts, first by using form variables, and then
by trying cookies as a fallback.

The login interface consists of the following methods:

=item C<login>, which takes a C<$type> argument, using constants found in
C<Bugzilla::Constants>.

The login method may use various authentication modules (described
above) to try to authenticate a user, and should return the userid on
success, or C<undef> on failure.

When a login is required, but data is not present, it is the job of the
login method to prompt the user for this data.

The constants accepted by C<login> include the following:

=over 4

=item C<LOGIN_OPTIONAL>

A login is never required to access this data. Attempting to login is
still useful, because this allows the page to be personalised. Note that
an incorrect login will still trigger an error, even though the lack of
a login will be OK.

=item C<LOGIN_NORMAL>

A login may or may not be required, depending on the setting of the
I<requirelogin> parameter.

=item C<LOGIN_REQUIRED>

A login is always required to access this data.

=back

=item C<logout>, which takes a C<Bugzilla::User> argument for the user
being logged out, and an C<$option> argument. Possible values for
C<$option> include:

=over 4

=item C<LOGOUT_CURRENT>

Log out the user and invalidate his currently registered session.

=item C<LOGOUT_ALL>

Log out the user, and invalidate all sessions the user has registered in
Bugzilla.

=item C<LOGOUT_KEEP_CURRENT>

Invalidate all sessions the user has registered excluding his current
session; this option should leave the user logged in. This is useful for
user-performed password changes.

=back

=head1 SEE ALSO

L<Bugzilla::Auth::Login::WWW::CGI>, L<Bugzilla::Auth::Login::WWW::CGI::Cookie>, L<Bugzilla::Auth::Verify::DB>

