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
# Contributor(s): Dave Miller <davem00@aol.com>
#                 Gayathri Swaminath <gayathrik00@aol.com>
#                 Jeroen Ruigrok van der Werven <asmodai@wxs.nl>
#                 Dave Lawrence <dkl@redhat.com>
#                 Tomas Kopal <Tomas.Kopal@altap.cz>

=head1 NAME

Bugzilla::DB::Pg - Bugzilla database compatibility layer for PostgreSQL

=head1 DESCRIPTION

This module overrides methods of the Bugzilla::DB module with PostgreSQL
specific implementation. It is instantiated by the Bugzilla::DB module
and should never be used directly.

For interface details see L<Bugzilla::DB> and L<DBI>.

=cut

package Bugzilla::DB::Pg;

use strict;

use Bugzilla::Error;
use DBD::Pg;

# This module extends the DB interface via inheritance
use base qw(Bugzilla::DB);

use constant BLOB_TYPE => { pg_type => DBD::Pg::PG_BYTEA };
use constant REQUIRED_VERSION => '7.03.0000';
use constant PROGRAM_NAME => 'PostgreSQL';
use constant MODULE_NAME  => 'Pg';

sub new {
    my ($class, $user, $pass, $host, $dbname, $port) = @_;

    # The default database name for PostgreSQL. We have
    # to connect to SOME database, even if we have
    # no $dbname parameter.
    $dbname ||= 'template1';

    # construct the DSN from the parameters we got
    my $dsn = "DBI:Pg:host=$host;dbname=$dbname";
    $dsn .= ";port=$port" if $port;
   
    my $self = $class->db_new($dsn, $user, $pass);

    # all class local variables stored in DBI derived class needs to have
    # a prefix 'private_'. See DBI documentation.
    $self->{private_bz_tables_locked} = 0;

    bless ($self, $class);

    return $self;
}

# if last_insert_id is supported on PostgreSQL by lowest DBI/DBD version
# supported by Bugzilla, this implementation can be removed.
sub bz_last_key {
    my ($self, $table, $column) = @_;

    my $seq = $table . "_" . $column . "_seq";
    my ($last_insert_id) = $self->selectrow_array("SELECT CURRVAL('$seq')");

    return $last_insert_id;
}

sub sql_regexp {
    return "~*";
}

sub sql_not_regexp {
    return "!~*" 
}

sub sql_limit {
    my ($self, $limit, $offset) = @_;

    if (defined($offset)) {
        return "LIMIT $limit OFFSET $offset";
    } else {
        return "LIMIT $limit";
    }
}

sub sql_to_days {
    my ($self, $date) = @_;

    return "TO_CHAR($date, 'J')::int";
}

sub sql_date_format {
    my ($self, $date, $format) = @_;
    
    $format = "%Y.%m.%d %H:%i:%s" if !$format;

    $format =~ s/\%Y/YYYY/g;
    $format =~ s/\%y/YY/g;
    $format =~ s/\%m/MM/g;
    $format =~ s/\%d/DD/g;
    $format =~ s/\%a/Dy/g;
    $format =~ s/\%H/HH24/g;
    $format =~ s/\%i/MI/g;
    $format =~ s/\%s/SS/g;

    return "TO_CHAR($date, " . $self->quote($format) . ")";
}

sub sql_interval {
    my ($self, $interval) = @_;
    
    return "INTERVAL '$interval'";
}

sub sql_string_concat {
    my ($self, @params) = @_;
    
    # Postgres 7.3 does not support concatenating of different types, so we
    # need to cast both parameters to text. Version 7.4 seems to handle this
    # properly, so when we stop support 7.3, this can be removed.
    return '(CAST(' . join(' AS text) || CAST(', @params) . ' AS text))';
}

sub bz_lock_tables {
    my ($self, @tables) = @_;
   
    # Check first if there was no lock before
    if ($self->{private_bz_tables_locked}) {
        ThrowCodeError("already_locked");
    } else {
        my %read_tables;
        my %write_tables;
        foreach my $table (@tables) {
            $table =~ /^([\d\w]+)([\s]+AS[\s]+[\d\w]+)?[\s]+(WRITE|READ)$/i;
            my $table_name = $1;
            if ($3 =~ /READ/i) {
                if (!exists $read_tables{$table_name}) {
                    $read_tables{$table_name} = undef;
                }
            }
            else {
                if (!exists $write_tables{$table_name}) {
                    $write_tables{$table_name} = undef;
                }
            }
        }
    
        # Begin Transaction
        $self->bz_start_transaction();
        
        Bugzilla->dbh->do('LOCK TABLE ' . join(', ', keys %read_tables) .
                          ' IN ROW SHARE MODE') if keys %read_tables;
        Bugzilla->dbh->do('LOCK TABLE ' . join(', ', keys %write_tables) .
                          ' IN ROW EXCLUSIVE MODE') if keys %write_tables;
        $self->{private_bz_tables_locked} = 1;
    }
}

sub bz_unlock_tables {
    my ($self, $abort) = @_;
    
    # Check first if there was previous matching lock
    if (!$self->{private_bz_tables_locked}) {
        # Abort is allowed even without previous lock for error handling
        return if $abort;
        ThrowCodeError("no_matching_lock");
    } else {
        $self->{private_bz_tables_locked} = 0;
        # End transaction, tables will be unlocked automatically
        if ($abort) {
            $self->bz_rollback_transaction();
        } else {
            $self->bz_commit_transaction();
        }
    }
}

1;
