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
# Contributor(s): Gervase Markham <gerv@gerv.net>
#                 Terry Weissman <terry@mozilla.org>
#                 Dan Mosedale <dmose@mozilla.org>
#                 Stephan Niemz <st.n@gmx.net>
#                 Andreas Franke <afranke@mathweb.org>
#                 Myk Melez <myk@mozilla.org>
#                 Michael Schindler <michael@compressconsult.com>

use strict;

# The caller MUST require CGI.pl and globals.pl before using this

use vars qw($userid);

package Bugzilla::Search;
use base qw(Exporter);
@Bugzilla::Search::EXPORT = qw(IsValidQueryType);

use Bugzilla::Config;
use Bugzilla::Error;
use Bugzilla::Util;

use Date::Format;
use Date::Parse;

# Create a new Search
# Note that the param argument may be modified by Bugzilla::Search
sub new {
    my $invocant = shift;
    my $class = ref($invocant) || $invocant;
  
    my $self = { @_ };  
    bless($self, $class);
    
    $self->init();
    
    return $self;
}

sub init {
    my $self = shift;
    my $fieldsref = $self->{'fields'};
    my $params = $self->{'params'};
    my $user = $self->{'user'} || Bugzilla->user;

    my $debug = 0;
        
    my @fields;
    my @supptables;
    my @wherepart;
    my @having;
    @fields = @$fieldsref if $fieldsref;
    my @specialchart;
    my @andlist;

    &::GetVersionTable();
    
    # First, deal with all the old hard-coded non-chart-based poop.
    if (lsearch($fieldsref, 'map_assigned_to.login_name') >= 0 || 
        lsearch($fieldsref, 'map_assigned_to.realname') >= 0) {
        push @supptables, "profiles AS map_assigned_to";
        push @wherepart, "bugs.assigned_to = map_assigned_to.userid";
    }

    if (lsearch($fieldsref, 'map_reporter.login_name') >= 0 || 
        lsearch($fieldsref, 'map_reporter.realname') >= 0) {
        push @supptables, "profiles AS map_reporter";
        push @wherepart, "bugs.reporter = map_reporter.userid";
    }

    if (lsearch($fieldsref, 'map_qa_contact.login_name') >= 0 || 
        lsearch($fieldsref, 'map_qa_contact.realname') >= 0) {
        push @supptables, "LEFT JOIN profiles map_qa_contact ON bugs.qa_contact = map_qa_contact.userid";
    }

    if (lsearch($fieldsref, 'map_products.name') >= 0) {
        push @supptables, "products AS map_products";
        push @wherepart, "bugs.product_id = map_products.id";
    }

    if (lsearch($fieldsref, 'map_components.name') >= 0) {
        push @supptables, "components AS map_components";
        push @wherepart, "bugs.component_id = map_components.id";
    }

    my $minvotes;
    if (defined $params->param('votes')) {
        my $c = trim($params->param('votes'));
        if ($c ne "") {
            if ($c !~ /^[0-9]*$/) {
                ThrowUserError("illegal_at_least_x_votes",
                                  { value => $c });
            }
            push(@specialchart, ["votes", "greaterthan", $c - 1]);
        }
    }

    if ($params->param('bug_id')) {
        my $type = "anyexact";
        if ($params->param('bugidtype') && $params->param('bugidtype') eq 'exclude') {
            $type = "nowords";
        }
        push(@specialchart, ["bug_id", $type, join(',', $params->param('bug_id'))]);
    }

    # If the user has selected all of either status or resolution, change to
    # selecting none. This is functionally equivalent, but quite a lot faster.
    # Also, if the status is __open__ or __closed__, translate those
    # into their equivalent lists of open and closed statuses.
    if ($params->param('bug_status')) {
        my @bug_statuses = $params->param('bug_status');
        if (scalar(@bug_statuses) == scalar(@::legal_bug_status) 
            || $bug_statuses[0] eq "__all__")
        {
            $params->delete('bug_status');
        }
        elsif ($bug_statuses[0] eq '__open__') {
            $params->param('bug_status', map(&::IsOpenedState($_) ? $_ : undef, 
                                             @::legal_bug_status));
        }
        elsif ($bug_statuses[0] eq "__closed__") {
            $params->param('bug_status', map(&::IsOpenedState($_) ? undef : $_, 
                                             @::legal_bug_status));
        }
    }
    
    if ($params->param('resolution')) {
        my @resolutions = $params->param('resolution');
        
        if (scalar(@resolutions) == scalar(@::legal_resolution)) {
            $params->delete('resolution');
        }
    }
    
    my @legal_fields = ("product", "version", "rep_platform", "op_sys",
                        "bug_status", "resolution", "priority", "bug_severity",
                        "assigned_to", "reporter", "component",
                        "target_milestone", "bug_group");

    foreach my $field ($params->param()) {
        if (lsearch(\@legal_fields, $field) != -1) {
            push(@specialchart, [$field, "anyexact",
                                 join(',', $params->param($field))]);
        }
    }

    if ($params->param('keywords')) {
        my $t = $params->param('keywords_type');
        if (!$t || $t eq "or") {
            $t = "anywords";
        }
        push(@specialchart, ["keywords", $t, $params->param('keywords')]);
    }

    if (lsearch($fieldsref, "(SUM(ldtime.work_time)*COUNT(DISTINCT ldtime.bug_when)/COUNT(bugs.bug_id)) AS actual_time") != -1) {
        push(@supptables, "longdescs AS ldtime");
        push(@wherepart, "ldtime.bug_id = bugs.bug_id");
    }

    foreach my $id ("1", "2") {
        if (!defined ($params->param("email$id"))) {
            next;
        }
        my $email = trim($params->param("email$id"));
        if ($email eq "") {
            next;
        }
        my $type = $params->param("emailtype$id");
        if ($type eq "exact") {
            $type = "anyexact";
            foreach my $name (split(',', $email)) {
                $name = trim($name);
                if ($name) {
                    &::DBNameToIdAndCheck($name);
                }
            }
        }

        my @clist;
        foreach my $field ("assigned_to", "reporter", "cc", "qa_contact") {
            if ($params->param("email$field$id")) {
                push(@clist, $field, $type, $email);
            }
        }
        if ($params->param("emaillongdesc$id")) {
                push(@clist, "commenter", $type, $email);
        }
        if (@clist) {
            push(@specialchart, \@clist);
        } else {
            ThrowUserError("missing_email_type",
                           { email => $email });
        }
    }

    my $chfieldfrom = trim(lc($params->param('chfieldfrom'))) || '';
    my $chfieldto = trim(lc($params->param('chfieldto'))) || '';
    $chfieldfrom = '' if ($chfieldfrom eq 'now');
    $chfieldto = '' if ($chfieldto eq 'now');
    my @chfield = $params->param('chfield');
    my $chvalue = trim($params->param('chfieldvalue')) || '';

    # 2003-05-20: The 'changedin' field is no longer in the UI, but we continue
    # to process it because it will appear in stored queries and bookmarks.
    my $changedin = trim($params->param('changedin')) || '';
    if ($changedin) {
        if ($changedin !~ /^[0-9]*$/) {
            ThrowUserError("illegal_changed_in_last_x_days",
                              { value => $changedin });
        }

        if (!$chfieldfrom
            && !$chfieldto
            && scalar(@chfield) == 1
            && $chfield[0] eq "[Bug creation]")
        {
            # Deal with the special case where the query is using changedin
            # to get bugs created in the last n days by converting the value
            # into its equivalent for the chfieldfrom parameter.
            $chfieldfrom = "-" . ($changedin - 1) . "d";
        }
        else {
            # Oh boy, the general case.  Who knows why the user included
            # the changedin parameter, but do our best to comply.
            push(@specialchart, ["changedin", "lessthan", $changedin + 1]);
        }
    }

    if ($chfieldfrom ne '' || $chfieldto ne '') {
        my $sql_chfrom = $chfieldfrom ? &::SqlQuote(SqlifyDate($chfieldfrom)):'';
        my $sql_chto   = $chfieldto   ? &::SqlQuote(SqlifyDate($chfieldto))  :'';
        my $sql_chvalue = $chvalue ne '' ? &::SqlQuote($chvalue) : '';
        if(!@chfield) {
            push(@wherepart, "bugs.delta_ts >= $sql_chfrom") if ($sql_chfrom);
            push(@wherepart, "bugs.delta_ts <= $sql_chto") if ($sql_chto);
        } else {
            my $bug_creation_clause;
            my @list;
            foreach my $f (@chfield) {
                if ($f eq "[Bug creation]") {
                    # Treat [Bug creation] differently because we need to look
                    # at bugs.creation_ts rather than the bugs_activity table.
                    my @l;
                    push(@l, "bugs.creation_ts >= $sql_chfrom") if($sql_chfrom);
                    push(@l, "bugs.creation_ts <= $sql_chto") if($sql_chto);
                    $bug_creation_clause = "(" . join(' AND ', @l) . ")";
                } else {
                    push(@list, "\nactcheck.fieldid = " . &::GetFieldID($f));
                }
            }

            # @list won't have any elements if the only field being searched
            # is [Bug creation] (in which case we don't need bugs_activity).
            if(@list) {
                push(@supptables, "bugs_activity actcheck");
                push(@wherepart, "actcheck.bug_id = bugs.bug_id");
                if($sql_chfrom) {
                    push(@wherepart, "actcheck.bug_when >= $sql_chfrom");
                }
                if($sql_chto) {
                    push(@wherepart, "actcheck.bug_when <= $sql_chto");
                }
                if($sql_chvalue) {
                    push(@wherepart, "actcheck.added = $sql_chvalue");
                }
            }

            # Now that we're done using @list to determine if there are any
            # regular fields to search (and thus we need bugs_activity),
            # add the [Bug creation] criterion to the list so we can OR it
            # together with the others.
            push(@list, $bug_creation_clause) if $bug_creation_clause;

            push(@wherepart, "(" . join(" OR ", @list) . ")");
        }
    }

    foreach my $f ("short_desc", "long_desc", "bug_file_loc",
                   "status_whiteboard") {
        if (defined $params->param($f)) {
            my $s = trim($params->param($f));
            if ($s ne "") {
                my $n = $f;
                my $q = &::SqlQuote($s);
                my $type = $params->param($f . "_type");
                push(@specialchart, [$f, $type, $s]);
            }
        }
    }

    if (defined $params->param('content')) {
        # Append a new chart implementing content quicksearch
        my $chart;
        for ($chart = 0 ; $params->param("field$chart-0-0") ; $chart++) {};
        $params->param("field$chart-0-0", 'content');
        $params->param("type$chart-0-0", 'matches');
        $params->param("value$chart-0-0", $params->param('content'));
        $params->param("field$chart-0-1", 'short_desc');
        $params->param("type$chart-0-1", 'allwords');
        $params->param("value$chart-0-1", $params->param('content'));
    }

    my $chartid;
    my $sequence = 0;
    # $type_id is used by the code that queries for attachment flags.
    my $type_id = 0;
    my $f;
    my $ff;
    my $t;
    my $q;
    my $v;
    my $term;
    my %funcsbykey;
    my @funcdefs =
        (
         "^(assigned_to|reporter)," => sub {
             push(@supptables, "profiles AS map_$f");
             push(@wherepart, "bugs.$f = map_$f.userid");
             $f = "map_$f.login_name";
         },
         "^qa_contact," => sub {
             push(@supptables,
                  "LEFT JOIN profiles map_qa_contact ON bugs.qa_contact = map_qa_contact.userid");
             $f = "map_$f.login_name";
         },

         "^cc,(anyexact|substring)" => sub {
             my $list;
             $list = $self->ListIDsForEmail($t, $v);
             my $chartseq;
             $chartseq = $chartid;
             if ($chartid eq "") {
                 $chartseq = "CC$sequence";
                 $sequence++;
             }
             if ($list) {
                 push(@supptables, "LEFT JOIN cc cc_$chartseq ON bugs.bug_id = cc_$chartseq.bug_id AND cc_$chartseq.who IN($list)");
                 $term = "cc_$chartseq.who IS NOT NULL";
             } else {
                 push(@supptables, "LEFT JOIN cc cc_$chartseq ON bugs.bug_id = cc_$chartseq.bug_id");

                 push(@supptables, "LEFT JOIN profiles map_cc_$chartseq ON cc_$chartseq.who = map_cc_$chartseq.userid");
                 $ff = $f = "map_cc_$chartseq.login_name";
                 my $ref = $funcsbykey{",$t"};
                 &$ref;
             }
         },
         "^cc," => sub {
             my $chartseq;
             $chartseq = $chartid;
             if ($chartid eq "") {
                 $chartseq = "CC$sequence";
                 $sequence++;
             }
            push(@supptables, "LEFT JOIN cc cc_$chartseq ON bugs.bug_id = cc_$chartseq.bug_id");

            push(@supptables, "LEFT JOIN profiles map_cc_$chartseq ON cc_$chartseq.who = map_cc_$chartseq.userid");
            $f = "map_cc_$chartseq.login_name";
         },

         "^long_?desc,changedby" => sub {
             my $table = "longdescs_$chartid";
             push(@supptables, "longdescs $table");
             push(@wherepart, "$table.bug_id = bugs.bug_id");
             my $id = &::DBNameToIdAndCheck($v);
             $term = "$table.who = $id";
         },
         "^long_?desc,changedbefore" => sub {
             my $table = "longdescs_$chartid";
             push(@supptables, "longdescs $table");
             push(@wherepart, "$table.bug_id = bugs.bug_id");
             $term = "$table.bug_when < " . &::SqlQuote(SqlifyDate($v));
         },
         "^long_?desc,changedafter" => sub {
             my $table = "longdescs_$chartid";
             push(@supptables, "longdescs $table");
             push(@wherepart, "$table.bug_id = bugs.bug_id");
             $term = "$table.bug_when > " . &::SqlQuote(SqlifyDate($v));
         },
         "^content,matches" => sub {
             # "content" is an alias for columns containing text for which we
             # can search a full-text index and retrieve results by relevance, 
             # currently just bug comments (and summaries to some degree).
             # There's only one way to search a full-text index
             # ("MATCH (...) AGAINST (...)"), so we only accept the "matches"
             # operator, which is specific to full-text index searches.

             # Add the longdescs table to the query so we can search comments.
             my $table = "longdescs_$chartid";
             push(@supptables, "INNER JOIN longdescs $table ON bugs.bug_id " . 
                               "= $table.bug_id");
             if (Param("insidergroup") 
                 && !&::UserInGroup(Param("insidergroup")))
             {
                 push(@wherepart, "$table.isprivate < 1");
             }

             # Create search terms to add to the SELECT and WHERE clauses.
             # $term1 searches comments.
             # $term2 searches summaries, which contributes to the relevance
             # ranking in SELECT but doesn't limit which bugs get retrieved.
             my $term1 = "MATCH($table.thetext) AGAINST(".&::SqlQuote($v).")";
             my $term2 = "MATCH(bugs.short_desc) AGAINST(".&::SqlQuote($v).")";

             # The term to use in the WHERE clause.
             $term = $term1;

             # In order to sort by relevance (in case the user requests it),
             # we SELECT the relevance value and give it an alias so we can
             # add it to the SORT BY clause when we build it in buglist.cgi.
             #
             # Note: MySQL calculates relevance for each comment separately,
             # so we need to do some additional calculations to get an overall
             # relevance value, which we do by calculating the average (mean)
             # comment relevance and then adding the summary relevance, if any.
             # This weights summary relevance heavily, which makes sense
             # since summaries are short and thus highly significant.
             #
             # Note: We should be calculating the average relevance of all
             # comments for a bug, not just matching comments, but that's hard
             # (see http://bugzilla.mozilla.org/show_bug.cgi?id=145588#c35).
             my $select_term =
               "(SUM($term1)/COUNT($term1) + $term2) AS relevance";

             # Users can specify to display the relevance field, in which case
             # it'll show up in the list of fields being selected, and we need
             # to replace that occurrence with our select term.  Otherwise
             # we can just add the term to the list of fields being selected.
             if (grep($_ eq "relevance", @fields)) {
                 @fields = map($_ eq "relevance" ? $select_term : $_ , @fields);
             }
             else {
                 push(@fields, $select_term);
             }
         },
         "^content," => sub {
             ThrowUserError("search_content_without_matches");
         },
         "^commenter," => sub {    
             my $chartseq;
             my $list;
             $list = $self->ListIDsForEmail($t, $v);
             $chartseq = $chartid;
             if ($chartid eq "") {
                 $chartseq = "LD$sequence";
                 $sequence++;
             }
             my $table = "longdescs_$chartseq";
             my $extra = "";
             if (Param("insidergroup") && !&::UserInGroup(Param("insidergroup"))) {
                 $extra = "AND $table.isprivate < 1";
             }
             if ($list) {
                 push(@supptables, "LEFT JOIN longdescs $table ON $table.bug_id = bugs.bug_id $extra AND $table.who IN ($list)");
                 $term = "$table.who IS NOT NULL";
             } else {
                 push(@supptables, "LEFT JOIN longdescs $table ON $table.bug_id = bugs.bug_id $extra");
                 push(@supptables, "LEFT JOIN profiles map_$table ON $table.who = map_$table.userid");
                 $ff = $f = "map_$table.login_name";
                 my $ref = $funcsbykey{",$t"};
                 &$ref;
             }
         },
         "^long_?desc," => sub {
             my $table = "longdescs_$chartid";
             push(@supptables, "longdescs $table");
             if (Param("insidergroup") && !&::UserInGroup(Param("insidergroup"))) {
                 push(@wherepart, "$table.isprivate < 1") ;
             }
             push(@wherepart, "$table.bug_id = bugs.bug_id");
             $f = "$table.thetext";
         },
         "^work_time,changedby" => sub {
             my $table = "longdescs_$chartid";
             push(@supptables, "longdescs $table");
             push(@wherepart, "$table.bug_id = bugs.bug_id");
             my $id = &::DBNameToIdAndCheck($v);
             $term = "(($table.who = $id";
             $term .= ") AND ($table.work_time <> 0))";
         },
         "^work_time,changedbefore" => sub {
             my $table = "longdescs_$chartid";
             push(@supptables, "longdescs $table");
             push(@wherepart, "$table.bug_id = bugs.bug_id");
             $term = "(($table.bug_when < " . &::SqlQuote(SqlifyDate($v));
             $term .= ") AND ($table.work_time <> 0))";
         },
         "^work_time,changedafter" => sub {
             my $table = "longdescs_$chartid";
             push(@supptables, "longdescs $table");
             push(@wherepart, "$table.bug_id = bugs.bug_id");
             $term = "(($table.bug_when > " . &::SqlQuote(SqlifyDate($v));
             $term .= ") AND ($table.work_time <> 0))";
         },
         "^work_time," => sub {
             my $table = "longdescs_$chartid";
             push(@supptables, "longdescs $table");
             push(@wherepart, "$table.bug_id = bugs.bug_id");
             $f = "$table.work_time";
         },
         "^percentage_complete," => sub {
             my $oper;
             if ($t eq "equals") {
                 $oper = "=";
             } elsif ($t eq "greaterthan") {
                 $oper = ">";
             } elsif ($t eq "lessthan") {
                 $oper = "<";
             } elsif ($t eq "notequal") {
                 $oper = "<>";
             } elsif ($t eq "regexp") {
                 $oper = "REGEXP";
             } elsif ($t eq "notregexp") {
                 $oper = "NOT REGEXP";
             } else {
                 $oper = "noop";
             }
             if ($oper ne "noop") {
                 my $table = "longdescs_$chartid";
                 push(@supptables, "longdescs $table");
                 push(@wherepart, "$table.bug_id = bugs.bug_id");
                 my $field = "(100*((SUM($table.work_time)*COUNT(DISTINCT $table.bug_when)/COUNT(bugs.bug_id))/((SUM($table.work_time)*COUNT(DISTINCT $table.bug_when)/COUNT(bugs.bug_id))+bugs.remaining_time))) AS percentage_complete_$table";
                 push(@fields, $field);
                 push(@having, 
                      "percentage_complete_$table $oper " . &::SqlQuote($v));
             }
             $term = "0=0";
         },
         "^bug_group,(?!changed)" => sub {
            push(@supptables, "LEFT JOIN bug_group_map bug_group_map_$chartid ON bugs.bug_id = bug_group_map_$chartid.bug_id");

            push(@supptables, "LEFT JOIN groups groups_$chartid ON groups_$chartid.id = bug_group_map_$chartid.group_id");
            $f = "groups_$chartid.name";
         },
         "^attachments\..*," => sub {
             my $table = "attachments_$chartid";
             push(@supptables, "attachments $table");
             if (Param("insidergroup") && !&::UserInGroup(Param("insidergroup"))) {
                 push(@wherepart, "$table.isprivate = 0") ;
             }
             push(@wherepart, "bugs.bug_id = $table.bug_id");
             $f =~ m/^attachments\.(.*)$/;
             my $field = $1;
             if ($t eq "changedby") {
                 $v = &::DBNameToIdAndCheck($v);
                 $q = &::SqlQuote($v);
                 $field = "submitter_id";
                 $t = "equals";
             } elsif ($t eq "changedbefore") {
                 $v = SqlifyDate($v);
                 $q = &::SqlQuote($v);
                 $field = "creation_ts";
                 $t = "lessthan";
             } elsif ($t eq "changedafter") {
                 $v = SqlifyDate($v);
                 $q = &::SqlQuote($v);
                 $field = "creation_ts";
                 $t = "greaterthan";
             }
             if ($field eq "ispatch" && $v ne "0" && $v ne "1") {
                 ThrowUserError("illegal_attachment_is_patch");
             }
             if ($field eq "isobsolete" && $v ne "0" && $v ne "1") {
                 ThrowUserError("illegal_is_obsolete");
             }
             $f = "$table.$field";
         },
         "^flagtypes.name," => sub {
             # Matches bugs by flag name/status.
             # Note that--for the purposes of querying--a flag comprises
             # its name plus its status (i.e. a flag named "review" 
             # with a status of "+" can be found by searching for "review+").
             
             # Don't do anything if this condition is about changes to flags,
             # as the generic change condition processors can handle those.
             return if ($t =~ m/^changed/);
             
             # Add the flags and flagtypes tables to the query.  We do 
             # a left join here so bugs without any flags still match 
             # negative conditions (f.e. "flag isn't review+").
             my $flags = "flags_$chartid";
             push(@supptables, "LEFT JOIN flags $flags " . 
                               "ON bugs.bug_id = $flags.bug_id " .
                               "AND $flags.is_active = 1");
             my $flagtypes = "flagtypes_$chartid";
             push(@supptables, "LEFT JOIN flagtypes $flagtypes " . 
                               "ON $flags.type_id = $flagtypes.id");
             
             # Generate the condition by running the operator-specific function.
             # Afterwards the condition resides in the global $term variable.
             $ff = "CONCAT($flagtypes.name, $flags.status)";
             &{$funcsbykey{",$t"}};
             
             # If this is a negative condition (f.e. flag isn't "review+"),
             # we only want bugs where all flags match the condition, not 
             # those where any flag matches, which needs special magic.
             # Instead of adding the condition to the WHERE clause, we select
             # the number of flags matching the condition and the total number
             # of flags on each bug, then compare them in a HAVING clause.
             # If the numbers are the same, all flags match the condition,
             # so this bug should be included.
             if ($t =~ m/not/) {
                push(@fields, "SUM($ff IS NOT NULL) AS allflags_$chartid");
                push(@fields, "SUM($term) AS matchingflags_$chartid");
                push(@having, "allflags_$chartid = matchingflags_$chartid");
                $term = "0=0";
             }
         },
         "^requestees.login_name," => sub {
             my $flags = "flags_$chartid";
             push(@supptables, "LEFT JOIN flags $flags " .
                               "ON bugs.bug_id = $flags.bug_id " .
                               "AND $flags.is_active = 1");
             push(@supptables, "LEFT JOIN profiles requestees_$chartid " .
                               "ON $flags.requestee_id = requestees_$chartid.userid");
             $f = "requestees_$chartid.login_name";
         },
         "^setters.login_name," => sub {
             my $flags = "flags_$chartid";
             push(@supptables, "LEFT JOIN flags $flags " .
                               "ON bugs.bug_id = $flags.bug_id " .
                               "AND $flags.is_active = 1");
             push(@supptables, "LEFT JOIN profiles setters_$chartid " .
                               "ON $flags.setter_id = setters_$chartid.userid");
             $f = "setters_$chartid.login_name";
         },
         
         "^changedin," => sub {
             $f = "(to_days(now()) - to_days(bugs.delta_ts))";
         },

         "^component,(?!changed)" => sub {
             $f = $ff = "components.name";
             $funcsbykey{",$t"}->();
             $term = build_subselect("bugs.component_id",
                                     "components.id",
                                     "components",
                                     $term);
         },

         "^product,(?!changed)" => sub {
             # Generate the restriction condition
             $f = $ff = "products.name";
             $funcsbykey{",$t"}->();
             $term = build_subselect("bugs.product_id",
                                     "products.id",
                                     "products",
                                     $term);
         },

         "^keywords," => sub {
             &::GetVersionTable();
             my @list;
             my $table = "keywords_$chartid";
             foreach my $value (split(/[\s,]+/, $v)) {
                 if ($value eq '') {
                     next;
                 }
                 my $id = &::GetKeywordIdFromName($value);
                 if ($id) {
                     push(@list, "$table.keywordid = $id");
                 }
                 else {
                     ThrowUserError("unknown_keyword",
                                    { keyword => $v });
                 }
             }
             my $haveawordterm;
             if (@list) {
                 $haveawordterm = "(" . join(' OR ', @list) . ")";
                 if ($t eq "anywords") {
                     $term = $haveawordterm;
                 } elsif ($t eq "allwords") {
                     my $ref = $funcsbykey{",$t"};
                     &$ref;
                     if ($term && $haveawordterm) {
                         $term = "(($term) AND $haveawordterm)";
                     }
                 }
             }
             if ($term) {
                 push(@supptables, "keywords $table");
                 push(@wherepart, "$table.bug_id = bugs.bug_id");
             }
         },

         "^dependson," => sub {
                my $table = "dependson_" . $chartid;
                push(@supptables, "dependencies $table");
                $ff = "$table.$f";
                my $ref = $funcsbykey{",$t"};
                &$ref;
                push(@wherepart, "$table.blocked = bugs.bug_id");
         },

         "^blocked," => sub {
                my $table = "blocked_" . $chartid;
                push(@supptables, "dependencies $table");
                $ff = "$table.$f";
                my $ref = $funcsbykey{",$t"};
                &$ref;
                push(@wherepart, "$table.dependson = bugs.bug_id");
         },

         "^owner_idle_time,(greaterthan|lessthan)" => sub {
                my $table = "idle_" . $chartid;
                $v =~ /^(\d+)\s*([hHdDwWmMyY])?$/;
                my $quantity = $1;
                my $unit = lc $2;
                my $unitinterval = 'DAY';
                if ($unit eq 'h') {
                    $unitinterval = 'HOUR';
                } elsif ($unit eq 'w') {
                    $unitinterval = ' * 7 DAY';
                } elsif ($unit eq 'm') {
                    $unitinterval = 'MONTH';
                } elsif ($unit eq 'y') {
                    $unitinterval = 'YEAR';
                }
                my $cutoff = "DATE_SUB(NOW(), 
                              INTERVAL $quantity $unitinterval)";
                my $assigned_fieldid = &::GetFieldID('assigned_to');
                push(@supptables, "LEFT JOIN longdescs comment_$table " .
                                  "ON comment_$table.who = bugs.assigned_to " .
                                  "AND comment_$table.bug_id = bugs.bug_id " .
                                  "AND comment_$table.bug_when > $cutoff");
                push(@supptables, "LEFT JOIN bugs_activity activity_$table " .
                                  "ON (activity_$table.who = bugs.assigned_to " .
                                  "OR activity_$table.fieldid = $assigned_fieldid) " .
                                  "AND activity_$table.bug_id = bugs.bug_id " .
                                  "AND activity_$table.bug_when > $cutoff");
                if ($t =~ /greater/) {
                    push(@wherepart, "(comment_$table.who IS NULL " .
                                     "AND activity_$table.who IS NULL)");
                } else {
                    push(@wherepart, "(comment_$table.who IS NOT NULL " .
                                     "OR activity_$table.who IS NOT NULL)");
                }
                $term = "0=0";
         },

         ",equals" => sub {
             $term = "$ff = $q";
         },
         ",notequals" => sub {
             $term = "$ff != $q";
         },
         ",casesubstring" => sub {
             # mysql 4.0.1 and lower do not support CAST
             # mysql 3.*.* had a case-sensitive INSTR
             # (checksetup has a check for unsupported versions)
             my $server_version = Bugzilla::DB->server_version;
             if ($server_version =~ /^3\./) {
                 $term = "INSTR($ff ,$q)";
             } else {
                 $term = "INSTR(CAST($ff AS BINARY), CAST($q AS BINARY))";
             }
         },
         ",substring" => sub {
             $term = "INSTR(LOWER($ff), " . lc($q) . ")";
         },
         ",substr" => sub {
             $funcsbykey{",substring"}->();
         },
         ",notsubstring" => sub {
             $term = "INSTR(LOWER($ff), " . lc($q) . ") = 0";
         },
         ",regexp" => sub {
             $term = "LOWER($ff) REGEXP $q";
         },
         ",notregexp" => sub {
             $term = "LOWER($ff) NOT REGEXP $q";
         },
         ",lessthan" => sub {
             $term = "$ff < $q";
         },
         ",matches" => sub {
             ThrowUserError("search_content_without_matches");
         },
         ",greaterthan" => sub {
             $term = "$ff > $q";
         },
         ",anyexact" => sub {
             my @list;
             foreach my $w (split(/,/, $v)) {
                 if ($w eq "---" && $f !~ /milestone/) {
                     $w = "";
                 }
                 push(@list, &::SqlQuote($w));
             }
             if (@list) {
                 $term = "$ff IN (" . join (',', @list) . ")";
             }
         },
         ",anywordssubstr" => sub {
             $term = join(" OR ", @{GetByWordListSubstr($ff, $v)});
         },
         ",allwordssubstr" => sub {
             $term = join(" AND ", @{GetByWordListSubstr($ff, $v)});
         },
         ",nowordssubstr" => sub {
             my @list = @{GetByWordListSubstr($ff, $v)};
             if (@list) {
                 $term = "NOT (" . join(" OR ", @list) . ")";
             }
         },
         ",anywords" => sub {
             $term = join(" OR ", @{GetByWordList($ff, $v)});
         },
         ",allwords" => sub {
             $term = join(" AND ", @{GetByWordList($ff, $v)});
         },
         ",nowords" => sub {
             my @list = @{GetByWordList($ff, $v)};
             if (@list) {
                 $term = "NOT (" . join(" OR ", @list) . ")";
             }
         },
         ",changedbefore" => sub {
             my $table = "act_$chartid";
             my $ftable = "fielddefs_$chartid";
             push(@supptables, "bugs_activity $table");
             push(@supptables, "fielddefs $ftable");
             push(@wherepart, "$table.bug_id = bugs.bug_id");
             push(@wherepart, "$table.fieldid = $ftable.fieldid");
             $term = "($ftable.name = '$f' AND $table.bug_when < $q)";
         },
         ",changedafter" => sub {
             my $table = "act_$chartid";
             my $ftable = "fielddefs_$chartid";
             push(@supptables, "bugs_activity $table");
             push(@supptables, "fielddefs $ftable");
             push(@wherepart, "$table.bug_id = bugs.bug_id");
             push(@wherepart, "$table.fieldid = $ftable.fieldid");
             $term = "($ftable.name = '$f' AND $table.bug_when > $q)";
         },
         ",changedfrom" => sub {
             my $table = "act_$chartid";
             my $ftable = "fielddefs_$chartid";
             push(@supptables, "bugs_activity $table");
             push(@supptables, "fielddefs $ftable");
             push(@wherepart, "$table.bug_id = bugs.bug_id");
             push(@wherepart, "$table.fieldid = $ftable.fieldid");
             $term = "($ftable.name = '$f' AND $table.removed = $q)";
         },
         ",changedto" => sub {
             my $table = "act_$chartid";
             my $ftable = "fielddefs_$chartid";
             push(@supptables, "bugs_activity $table");
             push(@supptables, "fielddefs $ftable");
             push(@wherepart, "$table.bug_id = bugs.bug_id");
             push(@wherepart, "$table.fieldid = $ftable.fieldid");
             $term = "($ftable.name = '$f' AND $table.added = $q)";
         },
         ",changedby" => sub {
             my $table = "act_$chartid";
             my $ftable = "fielddefs_$chartid";
             push(@supptables, "bugs_activity $table");
             push(@supptables, "fielddefs $ftable");
             push(@wherepart, "$table.bug_id = bugs.bug_id");
             push(@wherepart, "$table.fieldid = $ftable.fieldid");
             my $id = &::DBNameToIdAndCheck($v);
             $term = "($ftable.name = '$f' AND $table.who = $id)";
         },
         );
    my @funcnames;
    while (@funcdefs) {
        my $key = shift(@funcdefs);
        my $value = shift(@funcdefs);
        if ($key =~ /^[^,]*$/) {
            die "All defs in %funcs must have a comma in their name: $key";
        }
        if (exists $funcsbykey{$key}) {
            die "Duplicate key in %funcs: $key";
        }
        $funcsbykey{$key} = $value;
        push(@funcnames, $key);
    }

    # first we delete any sign of "Chart #-1" from the HTML form hash
    # since we want to guarantee the user didn't hide something here
    my @badcharts = grep /^(field|type|value)-1-/, $params->param();
    foreach my $field (@badcharts) {
        $params->delete($field);
    }

    # now we take our special chart and stuff it into the form hash
    my $chart = -1;
    my $row = 0;
    foreach my $ref (@specialchart) {
        my $col = 0;
        while (@$ref) {
            $params->param("field$chart-$row-$col", shift(@$ref));
            $params->param("type$chart-$row-$col", shift(@$ref));
            $params->param("value$chart-$row-$col", shift(@$ref));
            if ($debug) {
                print qq{<p>$params->param("field$chart-$row-$col") | $params->param("type$chart-$row-$col") | $params->param("value$chart-$row-$col")*</p>\n};
            }
            $col++;

        }
        $row++;
    }


# A boolean chart is a way of representing the terms in a logical
# expression.  Bugzilla builds SQL queries depending on how you enter
# terms into the boolean chart. Boolean charts are represented in
# urls as tree-tuples of (chart id, row, column). The query form
# (query.cgi) may contain an arbitrary number of boolean charts where
# each chart represents a clause in a SQL query.
#
# The query form starts out with one boolean chart containing one
# row and one column.  Extra rows can be created by pressing the
# AND button at the bottom of the chart.  Extra columns are created
# by pressing the OR button at the right end of the chart. Extra
# charts are created by pressing "Add another boolean chart".
#
# Each chart consists of an arbitrary number of rows and columns.
# The terms within a row are ORed together. The expressions represented
# by each row are ANDed together. The expressions represented by each
# chart are ANDed together.
#
#        ----------------------
#        | col2 | col2 | col3 |
# --------------|------|------|
# | row1 |  a1  |  a2  |      |
# |------|------|------|------|  => ((a1 OR a2) AND (b1 OR b2 OR b3) AND (c1))
# | row2 |  b1  |  b2  |  b3  |
# |------|------|------|------|
# | row3 |  c1  |      |      |
# -----------------------------
#
#        --------
#        | col2 |
# --------------|
# | row1 |  d1  | => (d1)
# ---------------
#
# Together, these two charts represent a SQL expression like this
# SELECT blah FROM blah WHERE ( (a1 OR a2)AND(b1 OR b2 OR b3)AND(c1)) AND (d1)
#
# The terms within a single row of a boolean chart are all constraints
# on a single piece of data.  If you're looking for a bug that has two
# different people cc'd on it, then you need to use two boolean charts.
# This will find bugs with one CC matching 'foo@blah.org' and and another
# CC matching 'bar@blah.org'.
#
# --------------------------------------------------------------
# CC    | equal to
# foo@blah.org
# --------------------------------------------------------------
# CC    | equal to
# bar@blah.org
#
# If you try to do this query by pressing the AND button in the
# original boolean chart then what you'll get is an expression that
# looks for a single CC where the login name is both "foo@blah.org",
# and "bar@blah.org". This is impossible.
#
# --------------------------------------------------------------
# CC    | equal to
# foo@blah.org
# AND
# CC    | equal to
# bar@blah.org
# --------------------------------------------------------------

# $chartid is the number of the current chart whose SQL we're constructing
# $row is the current row of the current chart

# names for table aliases are constructed using $chartid and $row
#   SELECT blah  FROM $table "$table_$chartid_$row" WHERE ....

# $f  = field of table in bug db (e.g. bug_id, reporter, etc)
# $ff = qualified field name (field name prefixed by table)
#       e.g. bugs_activity.bug_id
# $t  = type of query. e.g. "equal to", "changed after", case sensitive substr"
# $v  = value - value the user typed in to the form
# $q  = sanitized version of user input (SqlQuote($v))
# @supptables = Tables and/or table aliases used in query
# %suppseen   = A hash used to store all the tables in supptables to weed
#               out duplicates.
# @supplist   = A list used to accumulate all the JOIN clauses for each
#               chart to merge the ON sections of each.
# $suppstring = String which is pasted into query containing all table names

    # get a list of field names to verify the user-submitted chart fields against
    my %chartfields;
    &::SendSQL("SELECT name FROM fielddefs");
    while (&::MoreSQLData()) {
        my ($name) = &::FetchSQLData();
        $chartfields{$name} = 1;
    }

    $row = 0;
    for ($chart=-1 ;
         $chart < 0 || $params->param("field$chart-0-0") ;
         $chart++) {
        $chartid = $chart >= 0 ? $chart : "";
        for ($row = 0 ;
             $params->param("field$chart-$row-0") ;
             $row++) {
            my @orlist;
            for (my $col = 0 ;
                 $params->param("field$chart-$row-$col") ;
                 $col++) {
                $f = $params->param("field$chart-$row-$col") || "noop";
                $t = $params->param("type$chart-$row-$col") || "noop";
                $v = $params->param("value$chart-$row-$col");
                $v = "" if !defined $v;
                $v = trim($v);
                if ($f eq "noop" || $t eq "noop" || $v eq "") {
                    next;
                }
                # chart -1 is generated by other code above, not from the user-
                # submitted form, so we'll blindly accept any values in chart -1
                if ((!$chartfields{$f}) && ($chart != -1)) {
                    ThrowCodeError("invalid_field_name", {field => $f});
                }

                # This is either from the internal chart (in which case we
                # already know about it), or it was in %chartfields, so it is
                # a valid field name, which means that it's ok.
                trick_taint($f);
                $q = &::SqlQuote($v);
                my $func;
                $term = undef;
                foreach my $key (@funcnames) {
                    if ("$f,$t" =~ m/$key/) {
                        my $ref = $funcsbykey{$key};
                        if ($debug) {
                            print "<p>$key ($f , $t ) => ";
                        }
                        $ff = $f;
                        if ($f !~ /\./) {
                            $ff = "bugs.$f";
                        }
                        &$ref;
                        if ($debug) {
                            print "$f , $t , $term</p>";
                        }
                        if ($term) {
                            last;
                        }
                    }
                }
                if ($term) {
                    push(@orlist, $term);
                }
                else {
                    # This field and this type don't work together.
                    ThrowCodeError("field_type_mismatch",
                                   { field => $params->param("field$chart-$row-$col"),
                                     type => $params->param("type$chart-$row-$col"),
                                   });
                }
            }
            if (@orlist) {
                @orlist = map("($_)", @orlist) if (scalar(@orlist) > 1);
                push(@andlist, "(" . join(" OR ", @orlist) . ")");
            }
        }
    }
    my %suppseen = ("bugs" => 1);
    my $suppstring = "bugs";
    my @supplist = (" ");
    foreach my $str (@supptables) {
        if (!$suppseen{$str}) {
            if ($str =~ /^(LEFT|INNER) JOIN/i) {
                $str =~ /^(.*?)\s+ON\s+(.*)$/i;
                my ($leftside, $rightside) = ($1, $2);
                if ($suppseen{$leftside}) {
                    $supplist[$suppseen{$leftside}] .= " AND ($rightside)";
                } else {
                    $suppseen{$leftside} = scalar @supplist;
                    push @supplist, " $leftside ON ($rightside)";
                }
            } else {
                $suppstring .= ", $str";
                $suppseen{$str} = 1;
            }
        }
    }
    $suppstring .= join('', @supplist);
    
    # Make sure we create a legal SQL query.
    @andlist = ("1 = 1") if !@andlist;
   
    my $query = "SELECT " . join(', ', @fields) .
                " FROM $suppstring" .
                " LEFT JOIN bug_group_map " .
                " ON bug_group_map.bug_id = bugs.bug_id ";

    if ($user) {
        if (%{$user->groups}) {
            $query .= " AND bug_group_map.group_id NOT IN (" . join(',', values(%{$user->groups})) . ") ";
        }

        $query .= " LEFT JOIN cc ON cc.bug_id = bugs.bug_id AND cc.who = " . $user->id;
    }

    $query .= " WHERE " . join(' AND ', (@wherepart, @andlist)) .
              " AND ((bug_group_map.group_id IS NULL)";

    if ($user) {
        my $userid = $user->id;
        $query .= "    OR (bugs.reporter_accessible = 1 AND bugs.reporter = $userid) " .
              "    OR (bugs.cclist_accessible = 1 AND cc.who IS NOT NULL) " .
              "    OR (bugs.assigned_to = $userid) ";
        if (Param('useqacontact')) {
            $query .= "OR (bugs.qa_contact = $userid) ";
        }
    }

    $query .= ") GROUP BY bugs.bug_id";

    if (@having) {
        $query .= " HAVING " . join(" AND ", @having);
    }

    if ($debug) {
        print "<p><code>" . value_quote($query) . "</code></p>\n";
        exit;
    }
    
    $self->{'sql'} = $query;
}

###############################################################################
# Helper functions for the init() method.
###############################################################################
sub SqlifyDate {
    my ($str) = @_;
    $str = "" if !defined $str;
    if ($str eq "") {
        my ($sec, $min, $hour, $mday, $month, $year, $wday) = localtime(time());
        return sprintf("%4d-%02d-%02d 00:00:00", $year+1900, $month+1, $mday);
    }
    if ($str =~ /^-?(\d+)([dDwWmMyY])$/) {   # relative date
        my ($amount, $unit, $date) = ($1, lc $2, time);
        my ($sec, $min, $hour, $mday, $month, $year, $wday)  = localtime($date);
        if ($unit eq 'w') {                  # convert weeks to days
            $amount = 7*$amount + $wday;
            $unit = 'd';
        }
        if ($unit eq 'd') {
            $date -= $sec + 60*$min + 3600*$hour + 24*3600*$amount;
            return time2str("%Y-%m-%d %H:%M:%S", $date);
        }
        elsif ($unit eq 'y') {
            return sprintf("%4d-01-01 00:00:00", $year+1900-$amount);
        }
        elsif ($unit eq 'm') {
            $month -= $amount;
            while ($month<0) { $year--; $month += 12; }
            return sprintf("%4d-%02d-01 00:00:00", $year+1900, $month+1);
        }
        return undef;                      # should not happen due to regexp at top
    }
    my $date = str2time($str);
    if (!defined($date)) {
        ThrowUserError("illegal_date", { date => $str });
    }
    return time2str("%Y-%m-%d %H:%M:%S", $date);
}

# ListIDsForEmail returns a string with a comma-joined list
# of userids matching email addresses
# according to the type specified.
# Currently, this only supports exact, anyexact, and substring matches.
# Substring matches will return up to 50 matching userids
# If a match type is unsupported or returns too many matches,
# ListIDsForEmail returns an undef.
sub ListIDsForEmail {
    my ($self, $type, $email) = (@_);
    my $old = $self->{"emailcache"}{"$type,$email"};
    return undef if ($old && $old eq "---");
    return $old if $old;
    my @list = ();
    my $list = "---";
    if ($type eq 'anyexact') {
        foreach my $w (split(/,/, $email)) {
            $w = trim($w);
            my $id = &::DBname_to_id($w);
            if ($id > 0) {
                push(@list,$id)
            }
        }
        $list = join(',', @list);
    } elsif ($type eq 'substring') {
        &::SendSQL("SELECT userid FROM profiles WHERE INSTR(login_name, " .
            &::SqlQuote($email) . ") LIMIT 51");
        while (&::MoreSQLData()) {
            my ($id) = &::FetchSQLData();
            push(@list, $id);
        }
        if (@list < 50) {
            $list = join(',', @list);
        }
    }
    $self->{"emailcache"}{"$type,$email"} = $list;
    return undef if ($list eq "---");
    return $list;
}

sub build_subselect {
    my ($outer, $inner, $table, $cond) = @_;
    my $q = "SELECT $inner FROM $table WHERE $cond";
    #return "$outer IN ($q)";
    &::SendSQL($q);
    my @list;
    while (&::MoreSQLData()) {
        push (@list, &::FetchOneColumn());
    }
    return "1=2" unless @list; # Could use boolean type on dbs which support it
    return "$outer IN (" . join(',', @list) . ")";
}

sub GetByWordList {
    my ($field, $strs) = (@_);
    my @list;

    foreach my $w (split(/[\s,]+/, $strs)) {
        my $word = $w;
        if ($word ne "") {
            $word =~ tr/A-Z/a-z/;
            $word = &::SqlQuote(quotemeta($word));
            $word =~ s/^'//;
            $word =~ s/'$//;
            $word = '(^|[^a-z0-9])' . $word . '($|[^a-z0-9])';
            push(@list, "lower($field) regexp '$word'");
        }
    }

    return \@list;
}

# Support for "any/all/nowordssubstr" comparison type ("words as substrings")
sub GetByWordListSubstr {
    my ($field, $strs) = (@_);
    my @list;

    foreach my $word (split(/[\s,]+/, $strs)) {
        if ($word ne "") {
            push(@list, "INSTR(LOWER($field), " . lc(&::SqlQuote($word)) . ")");
        }
    }

    return \@list;
}

sub getSQL {
    my $self = shift;
    return $self->{'sql'};
}

# Define if the Query Type passed in is a valid query type that we can deal with
sub IsValidQueryType
{
    my ($queryType) = @_;
    if (grep { $_ eq $queryType } qw(specific advanced)) {
        return 1;
    }
    return 0;
}

1;
