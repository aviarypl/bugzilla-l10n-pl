#!/usr/bin/perl -wT
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
# Contributor(s): Terry Weissman <terry@mozilla.org>
#                 Dan Mosedale <dmose@mozilla.org>
#                 Dave Miller <justdave@syndicomm.com>
#                 Christopher Aillon <christopher@aillon.com>
#                 Myk Melez <myk@mozilla.org>
#                 Jeff Hedlund <jeff.hedlund@matrixsi.com>
#                 Frédéric Buclin <LpSolit@gmail.com>
#                 Lance Larsh <lance.larsh@oracle.com>

# Implementation notes for this file:
#
# 1) the 'id' form parameter is validated early on, and if it is not a valid
# bugid an error will be reported, so it is OK for later code to simply check
# for a defined form 'id' value, and it can assume a valid bugid.
#
# 2) If the 'id' form parameter is not defined (after the initial validation),
# then we are processing multiple bugs, and @idlist will contain the ids.
#
# 3) If we are processing just the one id, then it is stored in @idlist for
# later processing.

use strict;

my $UserInEditGroupSet = -1;
my $UserInCanConfirmGroupSet = -1;
my $PrivilegesRequired = 0;
my $lastbugid = 0;

use lib qw(.);

require "globals.pl";
use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Bug;
use Bugzilla::BugMail;
use Bugzilla::User;
use Bugzilla::Util;
use Bugzilla::Field;

# Use the Flag module to modify flag data if the user set flags.
use Bugzilla::Flag;
use Bugzilla::FlagType;

# Shut up misguided -w warnings about "used only once":

use vars qw(@legal_product
          %versions
          %components
          %legal_opsys
          %legal_platform
          %legal_priority
          %settable_resolution
          %target_milestone
          %legal_severity
           );

my $user = Bugzilla->login(LOGIN_REQUIRED);
my $whoid = $user->id;
my $grouplist = $user->groups_as_string;

my $cgi = Bugzilla->cgi;
my $dbh = Bugzilla->dbh;
my $template = Bugzilla->template;
my $vars = {};

my $requiremilestone = 0;

######################################################################
# Begin Data/Security Validation
######################################################################

# Create a list of IDs of all bugs being modified in this request.
# This list will either consist of a single bug number from the "id"
# form/URL field or a series of numbers from multiple form/URL fields
# named "id_x" where "x" is the bug number.
# For each bug being modified, make sure its ID is a valid bug number 
# representing an existing bug that the user is authorized to access.
my @idlist;
if (defined $cgi->param('id')) {
  my $id = $cgi->param('id');
  ValidateBugID($id);

  # Store the validated, and detainted id back in the cgi data, as
  # lots of later code will need it, and will obtain it from there
  $cgi->param('id', $id);
  push @idlist, $id;
} else {
    foreach my $i ($cgi->param()) {
        if ($i =~ /^id_([1-9][0-9]*)/) {
            my $id = $1;
            ValidateBugID($id);
            push @idlist, $id;
        }
    }
}

# Make sure there are bugs to process.
scalar(@idlist) || ThrowUserError("no_bugs_chosen");

# Make sure form param 'dontchange' is defined so it can be compared to easily.
$cgi->param('dontchange','') unless defined $cgi->param('dontchange');

# Make sure the 'knob' param is defined; else set it to 'none'.
$cgi->param('knob', 'none') unless defined $cgi->param('knob');

# Validate all timetracking fields
foreach my $field ("estimated_time", "work_time", "remaining_time") {
    if (defined $cgi->param($field)) {
        my $er_time = trim($cgi->param($field));
        if ($er_time ne $cgi->param('dontchange')) {
            Bugzilla::Bug::ValidateTime($er_time, $field);
        }
    }
}

if (UserInGroup(Param('timetrackinggroup'))) {
    my $wk_time = $cgi->param('work_time');
    if ($cgi->param('comment') =~ /^\s*$/ && $wk_time && $wk_time != 0) {
        ThrowUserError('comment_required');
    }
}

ValidateComment(scalar $cgi->param('comment'));

# If the bug(s) being modified have dependencies, validate them
# and rebuild the list with the validated values.  This is important
# because there are situations where validation changes the value
# instead of throwing an error, f.e. when one or more of the values
# is a bug alias that gets converted to its corresponding bug ID
# during validation.
foreach my $field ("dependson", "blocked") {
    if ($cgi->param('id')) {
        my $bug = new Bugzilla::Bug($cgi->param('id'), $user->id);
        my @old = @{$bug->$field};
        my @new;
        foreach my $id (split(/[\s,]+/, $cgi->param($field))) {
            next unless $id;
            ValidateBugID($id, $field);
            push @new, $id;
        }
        $cgi->param($field, join(",", @new));
        my ($added, $removed) = Bugzilla::Util::diff_arrays(\@old, \@new);
        foreach my $id (@$added , @$removed) {
            # ValidateBugID is called without $field here so that it will
            # throw an error if any of the changed bugs are not visible.
            ValidateBugID($id);
            if (Param("strict_isolation")) {
                my $deltabug = new Bugzilla::Bug($id, $user->id);
                if (!$user->can_edit_product($deltabug->{'product_id'})) {
                    $vars->{'field'} = $field;
                    ThrowUserError("illegal_change_deps", $vars);
                }
            }
        }
        if ((@$added  || @$removed)
            && (!CheckCanChangeField($field, $bug->bug_id, 0, 1))) {
            $vars->{'privs'} = $PrivilegesRequired;
            $vars->{'field'} = $field;
            ThrowUserError("illegal_change", $vars);
        }
    } else {
        # Bugzilla does not support mass-change of dependencies so they
        # are not validated.  To prevent a URL-hacking risk, the dependencies
        # are deleted for mass-changes.
        $cgi->delete($field);
    }
}

# do a match on the fields if applicable

# The order of these function calls is important, as both Flag::validate
# and FlagType::validate assume User::match_field has ensured that the values
# in the requestee fields are legitimate user email addresses.
&Bugzilla::User::match_field($cgi, {
    'qa_contact'                => { 'type' => 'single' },
    'newcc'                     => { 'type' => 'multi'  },
    'masscc'                    => { 'type' => 'multi'  },
    'assigned_to'               => { 'type' => 'single' },
    '^requestee(_type)?-(\d+)$' => { 'type' => 'multi'  },
});

# Validate flags in all cases. validate() should not detect any
# reference to flags if $cgi->param('id') is undefined.
Bugzilla::Flag::validate($cgi, $cgi->param('id'));
Bugzilla::FlagType::validate($cgi, $cgi->param('id'));

######################################################################
# End Data/Security Validation
######################################################################

print $cgi->header();
$vars->{'title_tag'} = "bug_processed";

# Set the title if we can see a mid-air coming. This test may have false
# negatives, but never false positives, and should catch the majority of cases.
# It only works at all in the single bug case.
if (defined $cgi->param('id')) {
    SendSQL("SELECT delta_ts FROM bugs WHERE bug_id = " .
            $cgi->param('id'));
    my $delta_ts = FetchOneColumn();
    
    if (defined $cgi->param('delta_ts') && $cgi->param('delta_ts') ne $delta_ts)
    {
        $vars->{'title_tag'} = "mid_air";
    }
}

# Set up the vars for nagiavtional <link> elements
my @bug_list;
if ($cgi->cookie("BUGLIST") && defined $cgi->param('id')) {
    @bug_list = split(/:/, $cgi->cookie("BUGLIST"));
    $vars->{'bug_list'} = \@bug_list;
}

GetVersionTable();

check_form_field_defined($cgi, 'product');
check_form_field_defined($cgi, 'version');
check_form_field_defined($cgi, 'component');


# This function checks if there is a comment required for a specific
# function and tests, if the comment was given.
# If comments are required for functions is defined by params.
#
sub CheckonComment {
    my ($function) = (@_);
    
    # Param is 1 if comment should be added !
    my $ret = Param( "commenton" . $function );

    # Allow without comment in case of undefined Params.
    $ret = 0 unless ( defined( $ret ));

    if( $ret ) {
        if (!defined $cgi->param('comment')
            || $cgi->param('comment') =~ /^\s*$/) {
            # No comment - sorry, action not allowed !
            ThrowUserError("comment_required");
        } else {
            $ret = 0;
        }
    }
    return( ! $ret ); # Return val has to be inverted
}

# Figure out whether or not the user is trying to change the product
# (either the "product" variable is not set to "don't change" or the
# user is changing a single bug and has changed the bug's product),
# and make the user verify the version, component, target milestone,
# and bug groups if so.
my $oldproduct = '';
if (defined $cgi->param('id')) {
    SendSQL("SELECT name FROM products INNER JOIN bugs " .
            "ON products.id = bugs.product_id WHERE bug_id = " .
            $cgi->param('id'));
    $oldproduct = FetchSQLData();
}

if (((defined $cgi->param('id') && $cgi->param('product') ne $oldproduct) 
     || (!$cgi->param('id')
         && $cgi->param('product') ne $cgi->param('dontchange')))
    && CheckonComment( "reassignbycomponent" ))
{
    # Check to make sure they actually have the right to change the product
    if (!CheckCanChangeField('product', scalar $cgi->param('id'), $oldproduct,
                              $cgi->param('product'))) {
        $vars->{'oldvalue'} = $oldproduct;
        $vars->{'newvalue'} = $cgi->param('product');
        $vars->{'field'} = 'product';
        $vars->{'privs'} = $PrivilegesRequired;
        ThrowUserError("illegal_change", $vars);
    }

    my $prod = $cgi->param('product');
    trick_taint($prod);

    # If at least one bug does not belong to the product we are
    # moving to, we have to check whether or not the user is
    # allowed to enter bugs into that product.
    # Note that this check must be done early to avoid the leakage
    # of component, version and target milestone names.
    my $check_can_enter =
        $dbh->selectrow_array("SELECT 1 FROM bugs
                               INNER JOIN products
                               ON bugs.product_id = products.id
                               WHERE products.name != ?
                               AND bugs.bug_id IN
                               (" . join(',', @idlist) . ") " .
                               $dbh->sql_limit(1),
                               undef, $prod);

    if ($check_can_enter) { $user->can_enter_product($prod, 1) }

    # note that when this script is called from buglist.cgi (rather
    # than show_bug.cgi), it's possible that the product will be changed
    # but that the version and/or component will be set to 
    # "--dont_change--" but still happen to be correct.  in this case,
    # the if statement will incorrectly trigger anyway.  this is a 
    # pretty weird case, and not terribly unreasonable behavior, but 
    # worthy of a comment, perhaps.
    #
    my $vok = lsearch($::versions{$prod}, $cgi->param('version')) >= 0;
    my $cok = lsearch($::components{$prod}, $cgi->param('component')) >= 0;

    my $mok = 1;   # so it won't affect the 'if' statement if milestones aren't used
    if ( Param("usetargetmilestone") ) {
       check_form_field_defined($cgi, 'target_milestone');
       $mok = lsearch($::target_milestone{$prod},
                      $cgi->param('target_milestone')) >= 0;
    }

    # If the product-specific fields need to be verified, or we need to verify
    # whether or not to add the bugs to their new product's group, display
    # a verification form.
    if (!$vok || !$cok || !$mok || (AnyDefaultGroups()
        && !defined $cgi->param('addtonewgroup'))) {
        
        if (!$vok || !$cok || !$mok) {
            $vars->{'verify_fields'} = 1;
            my %defaults;
            # We set the defaults to these fields to the old value,
            # if its a valid option, otherwise we use the default where
            # that's appropriate
            $vars->{'versions'} = $::versions{$prod};
            if ($vok) {
                $defaults{'version'} = $cgi->param('version');
            }
            $vars->{'components'} = $::components{$prod};
            if ($cok) {
                $defaults{'component'} = $cgi->param('component');
            }
            if (Param("usetargetmilestone")) {
                $vars->{'use_target_milestone'} = 1;
                $vars->{'milestones'} = $::target_milestone{$prod};
                if ($mok) {
                    $defaults{'target_milestone'} = $cgi->param('target_milestone');
                } else {
                    SendSQL("SELECT defaultmilestone FROM products " .
                            "WHERE name = " . SqlQuote($prod));
                    $defaults{'target_milestone'} = FetchOneColumn();
                }
            }
            else {
                $vars->{'use_target_milestone'} = 0;
            }
            $vars->{'defaults'} = \%defaults;
        }
        else {
            $vars->{'verify_fields'} = 0;
        }
        
        $vars->{'verify_bug_group'} = (AnyDefaultGroups() 
                                       && !defined $cgi->param('addtonewgroup'));
        
        $template->process("bug/process/verify-new-product.html.tmpl", $vars)
          || ThrowTemplateError($template->error());
        exit;
    }
}


# Checks that the user is allowed to change the given field.  Actually, right
# now, the rules are pretty simple, and don't look at the field itself very
# much, but that could be enhanced.

my $ownerid;
my $reporterid;
my $qacontactid;

################################################################################
# CheckCanChangeField() defines what users are allowed to change what bugs. You
# can add code here for site-specific policy changes, according to the 
# instructions given in the Bugzilla Guide and below. Note that you may also
# have to update the Bugzilla::Bug::user() function to give people access to the
# options that they are permitted to change.
#
# CheckCanChangeField() should return true if the user is allowed to change this
# field, and false if they are not.
#
# The parameters to this function are as follows:
# $field    - name of the field in the bugs table the user is trying to change
# $bugid    - the ID of the bug they are changing
# $oldvalue - what they are changing it from
# $newvalue - what they are changing it to
#
# Note that this function is currently not called for dependency changes 
# (bug 141593) or CC changes, which means anyone can change those fields.
#
# Do not change the sections between START DO_NOT_CHANGE and END DO_NOT_CHANGE.
################################################################################
sub CheckCanChangeField {
    # START DO_NOT_CHANGE
    my ($field, $bugid, $oldvalue, $newvalue) = (@_);

    $oldvalue = defined($oldvalue) ? $oldvalue : '';
    $newvalue = defined($newvalue) ? $newvalue : '';

    # Return true if they haven't changed this field at all.
    if ($oldvalue eq $newvalue) {
        return 1;
    } elsif (trim($oldvalue) eq trim($newvalue)) {
        return 1;
    # numeric fields need to be compared using == 
    } elsif (($field eq "estimated_time" || $field eq "remaining_time")
             && $newvalue ne $cgi->param('dontchange')
             && $oldvalue == $newvalue)
    {
        return 1;
    }

    # A resolution change is always accompanied by a status change. So, we 
    # always OK resolution changes; if they really can't do this, we will 
    # notice it when status is checked. 
    if ($field eq "resolution") { 
        return 1;             
    }
    # END DO_NOT_CHANGE

    # Allow anyone to change comments.
    if ($field =~ /^longdesc/) {
        return 1;
    }

    # Ignore the assigned_to field if the bug is not being reassigned
    if ($field eq "assigned_to"
        && $cgi->param('knob') ne "reassignbycomponent"
        && $cgi->param('knob') ne "reassign")
    {
        return 1;
    }

    # START DO_NOT_CHANGE
    # Find out whether the user is a member of the "editbugs" and/or
    # "canconfirm" groups. $UserIn*GroupSet are caches of the return value of 
    # the UserInGroup calls.
    if ($UserInEditGroupSet < 0) {
        $UserInEditGroupSet = UserInGroup("editbugs");
    }
    
    if ($UserInCanConfirmGroupSet < 0) {
        $UserInCanConfirmGroupSet = UserInGroup("canconfirm");
    }
    # END DO_NOT_CHANGE

    # If the user isn't allowed to change a field, we must tell him who can.
    # We store the required permission set into the $PrivilegesRequired
    # variable which gets passed to the error template.
    #
    # $PrivilegesRequired = 0 : no privileges required;
    # $PrivilegesRequired = 1 : the reporter, assignee or an empowered user;
    # $PrivilegesRequired = 2 : the assignee or an empowered user;
    # $PrivilegesRequired = 3 : an empowered user.

    # Allow anyone with "editbugs" privs to change anything.
    if ($UserInEditGroupSet) {
        return 1;
    }

    # *Only* users with "canconfirm" privs can confirm bugs.
    if ($field eq "canconfirm"
        || ($field eq "bug_status"
            && $oldvalue eq 'UNCONFIRMED'
            && IsOpenedState($newvalue)))
    {
        $PrivilegesRequired = 3;
        return $UserInCanConfirmGroupSet;
    }

    # START DO_NOT_CHANGE
    # $reporterid, $ownerid and $qacontactid are caches of the results of
    # the call to find out the assignee, reporter and qacontact of the current bug.
    if ($lastbugid != $bugid) {
        SendSQL("SELECT reporter, assigned_to, qa_contact FROM bugs
                 WHERE bug_id = $bugid");
        ($reporterid, $ownerid, $qacontactid) = (FetchSQLData());
        $lastbugid = $bugid;
    }    
    # END DO_NOT_CHANGE

    # Allow the assignee to change anything else.
    if ($ownerid == $whoid) {
        return 1;
    }
    
    # Allow the QA contact to change anything else.
    if (Param('useqacontact') && $qacontactid && ($qacontactid == $whoid)) {
        return 1;
    }
    
    # At this point, the user is either the reporter or an
    # unprivileged user. We first check for fields the reporter
    # is not allowed to change.

    # The reporter may not:
    # - reassign bugs, unless the bugs are assigned to him;
    #   in that case we will have already returned 1 above
    #   when checking for the assignee of the bug.
    if ($field eq "assigned_to") {
        $PrivilegesRequired = 2;
        return 0;
    }
    # - change the QA contact
    if ($field eq "qa_contact") {
        $PrivilegesRequired = 2;
        return 0;
    }
    # - change the target milestone
    if ($field eq "target_milestone") {
        $PrivilegesRequired = 2;
        return 0;
    }
    # - change the priority (unless he could have set it originally)
    if ($field eq "priority"
        && !Param('letsubmitterchoosepriority'))
    {
        $PrivilegesRequired = 2;
        return 0;
    }

    # The reporter is allowed to change anything else.
    if ($reporterid == $whoid) {
        return 1;
    }

    # If we haven't returned by this point, then the user doesn't
    # have the necessary permissions to change this field.
    $PrivilegesRequired = 1;
    return 0;
}

# Confirm that the reporter of the current bug can access the bug we are duping to.
sub DuplicateUserConfirm {
    # if we've already been through here, then exit
    if (defined $cgi->param('confirm_add_duplicate')) {
        return;
    }

    # Remember that we validated both these ids earlier, so we know
    # they are both valid bug ids
    my $dupe = $cgi->param('id');
    my $original = $cgi->param('dup_id');
    
    SendSQL("SELECT reporter FROM bugs WHERE bug_id = $dupe");
    my $reporter = FetchOneColumn();
    my $rep_user = Bugzilla::User->new($reporter);

    if ($rep_user->can_see_bug($original)) {
        $cgi->param('confirm_add_duplicate', '1');
        return;
    }

    SendSQL("SELECT cclist_accessible FROM bugs WHERE bug_id = $original");
    $vars->{'cclist_accessible'} = FetchOneColumn();
    
    # Once in this part of the subroutine, the user has not been auto-validated
    # and the duper has not chosen whether or not to add to CC list, so let's
    # ask the duper what he/she wants to do.
    
    $vars->{'original_bug_id'} = $original;
    $vars->{'duplicate_bug_id'} = $dupe;
    
    # Confirm whether or not to add the reporter to the cc: list
    # of the original bug (the one this bug is being duped against).
    print Bugzilla->cgi->header();
    $template->process("bug/process/confirm-duplicate.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    exit;
}

if (defined $cgi->param('id')) {
    # since this means that we were called from show_bug.cgi, now is a good
    # time to do a whole bunch of error checking that can't easily happen when
    # we've been called from buglist.cgi, because buglist.cgi only tweaks
    # values that have been changed instead of submitting all the new values.
    # (XXX those error checks need to happen too, but implementing them 
    # is more work in the current architecture of this script...)
    #
    check_form_field($cgi, 'product', \@::legal_product);
    check_form_field($cgi, 'component', 
                   \@{$::components{$cgi->param('product')}});
    check_form_field($cgi, 'version', \@{$::versions{$cgi->param('product')}});
    if ( Param("usetargetmilestone") ) {
        check_form_field($cgi, 'target_milestone', 
                       \@{$::target_milestone{$cgi->param('product')}});
    }
    check_form_field($cgi, 'rep_platform', \@::legal_platform);
    check_form_field($cgi, 'op_sys', \@::legal_opsys);
    check_form_field($cgi, 'priority', \@::legal_priority);
    check_form_field($cgi, 'bug_severity', \@::legal_severity);
    check_form_field_defined($cgi, 'bug_file_loc');
    check_form_field_defined($cgi, 'short_desc');
    check_form_field_defined($cgi, 'longdesclength');
    $cgi->param('short_desc', clean_text($cgi->param('short_desc')));

    if (trim($cgi->param('short_desc')) eq "") {
        ThrowUserError("require_summary");
    }
}

my $action = trim($cgi->param('action') || '');

if ($action eq Param('move-button-text')) {
    Param('move-enabled') || ThrowUserError("move_bugs_disabled");

    $user->is_mover || ThrowUserError("auth_failure", {action => 'move',
                                                       object => 'bugs'});

    # Moved bugs are marked as RESOLVED MOVED.
    my $sth = $dbh->prepare("UPDATE bugs
                                SET bug_status = 'RESOLVED',
                                    resolution = 'MOVED',
                                    delta_ts = ?
                              WHERE bug_id = ?");
    # Bugs cannot be a dupe and moved at the same time.
    my $sth2 = $dbh->prepare("DELETE FROM duplicates WHERE dupe = ?");

    my $comment = "";
    if (defined $cgi->param('comment') && $cgi->param('comment') !~ /^\s*$/) {
        $comment = $cgi->param('comment') . "\n\n";
    }
    $comment .= "Bug moved to " . Param('move-to-url') . ".\n\n";
    $comment .= "If the move succeeded, " . $user->login . " will receive a mail\n";
    $comment .= "containing the number of the new bug in the other database.\n";
    $comment .= "If all went well,  please mark this bug verified, and paste\n";
    $comment .= "in a link to the new bug. Otherwise, reopen this bug.\n";

    $dbh->bz_lock_tables('bugs WRITE', 'bugs_activity WRITE', 'duplicates WRITE',
                         'longdescs WRITE', 'profiles READ', 'groups READ',
                         'bug_group_map READ', 'group_group_map READ',
                         'user_group_map READ', 'classifications READ',
                         'products READ', 'components READ', 'votes READ',
                         'cc READ', 'fielddefs READ');

    my $timestamp = $dbh->selectrow_array("SELECT NOW()");
    my @bugs;
    # First update all moved bugs.
    foreach my $id (@idlist) {
        my $bug = new Bugzilla::Bug($id, $whoid);
        push(@bugs, $bug);

        $sth->execute($timestamp, $id);
        $sth2->execute($id);

        AppendComment($id, $whoid, $comment, 0, $timestamp);

        if ($bug->bug_status ne 'RESOLVED') {
            LogActivityEntry($id, 'bug_status', $bug->bug_status,
                             'RESOLVED', $whoid, $timestamp);
        }
        if ($bug->resolution ne 'MOVED') {
            LogActivityEntry($id, 'resolution', $bug->resolution,
                             'MOVED', $whoid, $timestamp);
        }
    }
    $dbh->bz_unlock_tables();

    # Now send emails.
    foreach my $id (@idlist) {
        $vars->{'mailrecipients'} = { 'changer' => $user->login };
        $vars->{'id'} = $id;
        $vars->{'type'} = "move";

        $template->process("bug/process/results.html.tmpl", $vars)
          || ThrowTemplateError($template->error());
        $vars->{'header_done'} = 1;
    }
    # Prepare and send all data about these bugs to the new database
    my $to = Param('move-to-address');
    $to =~ s/@/\@/;
    my $from = Param('moved-from-address');
    $from =~ s/@/\@/;
    my $msg = "To: $to\n";
    $msg .= "From: Bugzilla <" . $from . ">\n";
    $msg .= "Subject: Moving bug(s) " . join(', ', @idlist) . "\n\n";

    my @fieldlist = (Bugzilla::Bug::fields(), 'group', 'long_desc',
                     'attachment', 'attachmentdata');
    my %displayfields;
    foreach (@fieldlist) {
        $displayfields{$_} = 1;
    }

    $template->process("bug/show.xml.tmpl", { bugs => \@bugs,
                                              displayfields => \%displayfields,
                                            }, \$msg)
      || ThrowTemplateError($template->error());

    $msg .= "\n";
    Bugzilla::BugMail::MessageToMTA($msg);

    # End the response page.
    $template->process("bug/navigate.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    $template->process("global/footer.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    exit;
}


$::query = "update bugs\nset";
$::comma = "";
umask(0);

sub _remove_remaining_time {
    if (UserInGroup(Param('timetrackinggroup'))) {
        if ( defined $cgi->param('remaining_time') 
             && $cgi->param('remaining_time') > 0 )
        {
            $cgi->param('remaining_time', 0);
            $vars->{'message'} = "remaining_time_zeroed";
        }
    }
    else {
        DoComma();
        $::query .= "remaining_time = 0";
    }
}

sub DoComma {
    $::query .= "$::comma\n    ";
    $::comma = ",";
}

# $everconfirmed is used by ChangeStatus() to determine whether we are
# confirming the bug or not.
my $everconfirmed;
sub DoConfirm {
    if (CheckCanChangeField("canconfirm", scalar $cgi->param('id'), 0, 1)) {
        DoComma();
        $::query .= "everconfirmed = 1";
        $everconfirmed = 1;
    }
}

sub ChangeStatus {
    my ($str) = (@_);
    if (!$cgi->param('dontchange')
        || $str ne $cgi->param('dontchange')) {
        DoComma();
        if ($cgi->param('knob') eq 'reopen') {
            # When reopening, we need to check whether the bug was ever
            # confirmed or not
            $::query .= "bug_status = CASE WHEN everconfirmed = 1 THEN " .
                         SqlQuote($str) . " ELSE 'UNCONFIRMED' END";
        } elsif (IsOpenedState($str)) {
            # Note that we cannot combine this with the above branch - here we
            # need to check if bugs.bug_status is open, (since we don't want to
            # reopen closed bugs when reassigning), while above the whole point
            # is to reopen a closed bug.
            # Currently, the UI doesn't permit a user to reassign a closed bug
            # from the single bug page (only during a mass change), but they
            # could still hack the submit, so don't restrict this extended
            # check to the mass change page for safety/sanity/consistency
            # purposes.

            # The logic for this block is:
            # If the new state is open:
            #   If the old state was open
            #     If the bug was confirmed
            #       - move it to the new state
            #     Else
            #       - Set the state to unconfirmed
            #   Else
            #     - leave it as it was

            # This is valid only because 'reopen' is the only thing which moves
            # from closed to open, and its handled above
            # This also relies on the fact that confirming and accepting have
            # already called DoConfirm before this is called

            my @open_state = map(SqlQuote($_), OpenStates());
            my $open_state = join(", ", @open_state);

            # If we are changing everconfirmed to 1, we have to take this change
            # into account and the new bug status is given by $str.
            my $cond = SqlQuote($str);
            # If we are not setting everconfirmed, the new bug status depends on
            # the actual value of everconfirmed, which is bug-specific.
            unless ($everconfirmed) {
                $cond = "(CASE WHEN everconfirmed = 1 THEN " . $cond .
                        " ELSE 'UNCONFIRMED' END)";
            }
            $::query .= "bug_status = CASE WHEN bug_status IN($open_state) THEN " .
                                      $cond . " ELSE bug_status END";
        } else {
            $::query .= "bug_status = " . SqlQuote($str);
        }
        # If bugs are reassigned and their status is "UNCONFIRMED", they
        # should keep this status instead of "NEW" as suggested here.
        # This point is checked for each bug later in the code.
        $cgi->param('bug_status', $str);
    }
}

sub ChangeResolution {
    my ($str) = (@_);
    if (!$cgi->param('dontchange')
        || $str ne $cgi->param('dontchange'))
    {
        DoComma();
        $::query .= "resolution = " . SqlQuote($str);
        # We define this variable here so that customized installations
        # may set rules based on the resolution in CheckCanChangeField.
        $cgi->param('resolution', $str);
    }
}

# Changing this so that it will process groups from checkboxes instead of
# select lists.  This means that instead of looking for the bit-X values in
# the form, we need to loop through all the bug groups this user has access
# to, and for each one, see if it's selected.
# If the form element isn't present, or the user isn't in the group, leave
# it as-is

my @groupAdd = ();
my @groupDel = ();

SendSQL("SELECT groups.id, isactive FROM groups " .
        "WHERE id IN($grouplist) " .
        "AND isbuggroup = 1");
while (my ($b, $isactive) = FetchSQLData()) {
    # The multiple change page may not show all groups a bug is in
    # (eg product groups when listing more than one product)
    # Only consider groups which were present on the form. We can't do this
    # for single bug changes because non-checked checkboxes aren't present.
    # All the checkboxes should be shown in that case, though, so its not
    # an issue there
    if (defined $cgi->param('id') || defined $cgi->param("bit-$b")) {
        if (!$cgi->param("bit-$b")) {
            push(@groupDel, $b);
        } elsif ($cgi->param("bit-$b") == 1 && $isactive) {
            push(@groupAdd, $b);
        }
    }
}

foreach my $field ("rep_platform", "priority", "bug_severity",
                   "bug_file_loc", "short_desc", "version", "op_sys",
                   "target_milestone", "status_whiteboard") {
    if (defined $cgi->param($field)) {
        if (!$cgi->param('dontchange')
            || $cgi->param($field) ne $cgi->param('dontchange')) {
            DoComma();
            $::query .= "$field = " . SqlQuote(trim($cgi->param($field)));
        }
    }
}

my $prod_id;
my $prod_changed;
my @newprod_ids;
if ($cgi->param('product') ne $cgi->param('dontchange')) {
    $prod_id = get_product_id($cgi->param('product'));
    $prod_id ||
      ThrowUserError("invalid_product_name", 
                     {product => $cgi->param('product')});
      
    DoComma();
    @newprod_ids = ($prod_id);
    $prod_changed = 1;
    $::query .= "product_id = $prod_id";
} else {
    @newprod_ids = @{$dbh->selectcol_arrayref("SELECT DISTINCT product_id
                                               FROM bugs 
                                               WHERE bug_id IN (" .
                                                   join(',', @idlist) . 
                                               ")")};
    if (scalar(@newprod_ids) == 1) {
        ($prod_id) = @newprod_ids;
    }
}

my $comp_id;
if ($cgi->param('component') ne $cgi->param('dontchange')) {
    if (scalar(@newprod_ids) > 1) {
        ThrowUserError("no_component_change_for_multiple_products");
    }
    $comp_id = get_component_id($prod_id,
                                $cgi->param('component'));
    $comp_id || ThrowCodeError("invalid_component", 
                               {name => $cgi->param('component'),
                                product => $cgi->param('product')});
    
    $cgi->param('component_id', $comp_id);
    DoComma();
    $::query .= "component_id = $comp_id";
}

# If this installation uses bug aliases, and the user is changing the alias,
# add this change to the query.
if (Param("usebugaliases") && defined $cgi->param('alias')) {
    my $alias = trim($cgi->param('alias'));
    
    # Since aliases are unique (like bug numbers), they can only be changed
    # for one bug at a time, so ignore the alias change unless only a single
    # bug is being changed.
    if (scalar(@idlist) == 1) {
        # Add the alias change to the query.  If the field contains the blank 
        # value, make the field be NULL to indicate that the bug has no alias.
        # Otherwise, if the field contains a value, update the record 
        # with that value.
        DoComma();
        $::query .= "alias = ";
        if ($alias ne "") {
            ValidateBugAlias($alias, $idlist[0]);
            $::query .= $dbh->quote($alias);
        } else {
            $::query .= "NULL";
        }
    }
}

# If the user is submitting changes from show_bug.cgi for a single bug,
# and that bug is restricted to a group, process the checkboxes that
# allowed the user to set whether or not the reporter
# and cc list can see the bug even if they are not members of all groups 
# to which the bug is restricted.
if (defined $cgi->param('id')) {
    SendSQL("SELECT group_id FROM bug_group_map WHERE bug_id = " .
            $cgi->param('id'));
    my ($havegroup) = FetchSQLData();
    if ( $havegroup ) {
        DoComma();
        $cgi->param('reporter_accessible',
                    $cgi->param('reporter_accessible') ? '1' : '0');
        $::query .= 'reporter_accessible = ' .
                    $cgi->param('reporter_accessible');

        DoComma();
        $cgi->param('cclist_accessible',
                    $cgi->param('cclist_accessible') ? '1' : '0');
        $::query .= 'cclist_accessible = ' . $cgi->param('cclist_accessible');
    }
}

if (defined $cgi->param('id') &&
    (Param("insidergroup") && UserInGroup(Param("insidergroup")))) {

    my $sth = $dbh->prepare('UPDATE longdescs SET isprivate = ?
                             WHERE bug_id = ? AND bug_when = ?');

    foreach my $field ($cgi->param()) {
        if ($field =~ /when-([0-9]+)/) {
            my $sequence = $1;
            my $private = $cgi->param("isprivate-$sequence") ? 1 : 0 ;
            if ($private != $cgi->param("oisprivate-$sequence")) {
                my $field_data = $cgi->param("$field");
                # Make sure a valid date is given.
                $field_data = format_time($field_data, '%Y-%m-%d %T');
                $sth->execute($private, $cgi->param('id'), $field_data);
            }
        }

    }
}

my $duplicate = 0;

# We need to check the addresses involved in a CC change before we touch any bugs.
# What we'll do here is formulate the CC data into two hashes of ID's involved
# in this CC change.  Then those hashes can be used later on for the actual change.
my (%cc_add, %cc_remove);
if (defined $cgi->param('newcc')
    || defined $cgi->param('addselfcc')
    || defined $cgi->param('removecc')
    || defined $cgi->param('masscc')) {
    # If masscc is defined, then we came from buglist and need to either add or
    # remove cc's... otherwise, we came from bugform and may need to do both.
    my ($cc_add, $cc_remove) = "";
    if (defined $cgi->param('masscc')) {
        if ($cgi->param('ccaction') eq 'add') {
            $cc_add = join(' ',$cgi->param('masscc'));
        } elsif ($cgi->param('ccaction') eq 'remove') {
            $cc_remove = join(' ',$cgi->param('masscc'));
        }
    } else {
        $cc_add = join(' ',$cgi->param('newcc'));
        # We came from bug_form which uses a select box to determine what cc's
        # need to be removed...
        if (defined $cgi->param('removecc') && $cgi->param('cc')) {
            $cc_remove = join (",", $cgi->param('cc'));
        }
    }

    if ($cc_add) {
        $cc_add =~ s/[\s,]+/ /g; # Change all delimiters to a single space
        foreach my $person ( split(" ", $cc_add) ) {
            my $pid = DBNameToIdAndCheck($person);
            $cc_add{$pid} = $person;
        }
    }
    if ($cgi->param('addselfcc')) {
        $cc_add{$whoid} = $user->login;
    }
    if ($cc_remove) {
        $cc_remove =~ s/[\s,]+/ /g; # Change all delimiters to a single space
        foreach my $person ( split(" ", $cc_remove) ) {
            my $pid = DBNameToIdAndCheck($person);
            $cc_remove{$pid} = $person;
        }
    }
}

# Store the new assignee and QA contact IDs (if any). This is the
# only way to keep these informations when bugs are reassigned by
# component as $cgi->param('assigned_to') and $cgi->param('qa_contact')
# are not the right fields to look at.
# If the assignee or qacontact is changed, the new one is checked when
# changed information is validated.  If not, then the unchanged assignee
# or qacontact may have to be validated later.

my $assignee;
my $qacontact;
my $qacontact_checked = 0;
my $assignee_checked = 0;

my %usercache = ();

if (defined $cgi->param('qa_contact')
    && $cgi->param('knob') ne "reassignbycomponent")
{
    my $name = trim($cgi->param('qa_contact'));
    # The QA contact cannot be deleted from show_bug.cgi for a single bug!
    if ($name ne $cgi->param('dontchange')) {
        $qacontact = DBNameToIdAndCheck($name) if ($name ne "");
        if ($qacontact && Param("strict_isolation")) {
                $usercache{$qacontact} ||= Bugzilla::User->new($qacontact);
                my $qa_user = $usercache{$qacontact};
                foreach my $product_id (@newprod_ids) {
                    if (!$qa_user->can_edit_product($product_id)) {
                        my $product_name = get_product_name($product_id);
                        ThrowUserError('invalid_user_group',
                                          {'users'   => $qa_user->login,
                                           'product' => $product_name,
                                           'bug_id' => (scalar(@idlist) > 1)
                                                         ? undef : $idlist[0]
                                          });
                    }
                }
        }
        $qacontact_checked = 1;
        DoComma();
        if($qacontact) {
            $::query .= "qa_contact = $qacontact";
        }
        else {
            $::query .= "qa_contact = NULL";
        }
    }
}

SWITCH: for ($cgi->param('knob')) {
    /^none$/ && do {
        last SWITCH;
    };
    /^confirm$/ && CheckonComment( "confirm" ) && do {
        DoConfirm();
        ChangeStatus('NEW');
        last SWITCH;
    };
    /^accept$/ && CheckonComment( "accept" ) && do {
        DoConfirm();
        ChangeStatus('ASSIGNED');
        if (Param("usetargetmilestone") && Param("musthavemilestoneonaccept")) {
            $requiremilestone = 1;
        }
        last SWITCH;
    };
    /^clearresolution$/ && CheckonComment( "clearresolution" ) && do {
        ChangeResolution('');
        last SWITCH;
    };
    /^resolve$/ && CheckonComment( "resolve" ) && do {
        # Check here, because its the only place we require the resolution
        check_form_field($cgi, 'resolution', \@::settable_resolution);

        # don't resolve as fixed while still unresolved blocking bugs
        if (Param("noresolveonopenblockers")
            && $cgi->param('resolution') eq 'FIXED')
        {
            my @dependencies = Bugzilla::Bug::CountOpenDependencies(@idlist);
            if (scalar @dependencies > 0) {
                ThrowUserError("still_unresolved_bugs",
                               { dependencies     => \@dependencies,
                                 dependency_count => scalar @dependencies });
            }
        }

        # RESOLVED bugs should have no time remaining;
        # more time can be added for the VERIFY step, if needed.
        _remove_remaining_time();

        ChangeStatus('RESOLVED');
        ChangeResolution($cgi->param('resolution'));
        last SWITCH;
    };
    /^reassign$/ && CheckonComment( "reassign" ) && do {
        if ($cgi->param('andconfirm')) {
            DoConfirm();
        }
        ChangeStatus('NEW');
        DoComma();
        if (defined $cgi->param('assigned_to')
            && trim($cgi->param('assigned_to')) ne "") { 
            $assignee = DBNameToIdAndCheck(trim($cgi->param('assigned_to')));
            if (Param("strict_isolation")) {
                $usercache{$assignee} ||= Bugzilla::User->new($assignee);
                my $assign_user = $usercache{$assignee};
                foreach my $product_id (@newprod_ids) {
                    if (!$assign_user->can_edit_product($product_id)) {
                        my $product_name = get_product_name($product_id);
                        ThrowUserError('invalid_user_group',
                                          {'users'   => $assign_user->login,
                                           'product' => $product_name,
                                           'bug_id' => (scalar(@idlist) > 1)
                                                         ? undef : $idlist[0]
                                          });
                    }
                }
            }
        } else {
            ThrowUserError("reassign_to_empty");
        }
        $assignee_checked = 1;
        $::query .= "assigned_to = $assignee";
        last SWITCH;
    };
    /^reassignbycomponent$/  && CheckonComment( "reassignbycomponent" ) && do {
        if ($cgi->param('compconfirm')) {
            DoConfirm();
        }
        ChangeStatus('NEW');
        last SWITCH;
    };
    /^reopen$/  && CheckonComment( "reopen" ) && do {
        ChangeStatus('REOPENED');
        ChangeResolution('');
        last SWITCH;
    };
    /^verify$/ && CheckonComment( "verify" ) && do {
        ChangeStatus('VERIFIED');
        last SWITCH;
    };
    /^close$/ && CheckonComment( "close" ) && do {
        # CLOSED bugs should have no time remaining.
        _remove_remaining_time();

        ChangeStatus('CLOSED');
        last SWITCH;
    };
    /^duplicate$/ && CheckonComment( "duplicate" ) && do {
        # You cannot mark bugs as duplicates when changing
        # several bugs at once.
        unless (defined $cgi->param('id')) {
            ThrowUserError('dupe_not_allowed');
        }

        # Make sure we can change the original bug (issue A on bug 96085)
        check_form_field_defined($cgi, 'dup_id');
        $duplicate = $cgi->param('dup_id');
        ValidateBugID($duplicate, 'dup_id');
        $cgi->param('dup_id', $duplicate);

        # Make sure the bug is not already marked as a dupe
        # (may appear in race condition)
        my $dupe_of =
            $dbh->selectrow_array("SELECT dupe_of FROM duplicates
                                   WHERE dupe = ?",
                                   undef, $cgi->param('id'));
        if ($dupe_of) {
            ThrowUserError("dupe_entry_found", { dupe_of => $dupe_of });
        }

        # Make sure a loop isn't created when marking this bug
        # as duplicate.
        my %dupes;
        $dupe_of = $duplicate;
        my $sth = $dbh->prepare('SELECT dupe_of FROM duplicates
                                 WHERE dupe = ?');

        while ($dupe_of) {
            if ($dupe_of == $cgi->param('id')) {
                ThrowUserError('dupe_loop_detected', { bug_id  => $cgi->param('id'),
                                                       dupe_of => $duplicate });
            }
            # If $dupes{$dupe_of} is already set to 1, then a loop
            # already exists which does not involve this bug.
            # As the user is not responsible for this loop, do not
            # prevent him from marking this bug as a duplicate.
            last if exists $dupes{"$dupe_of"};
            $dupes{"$dupe_of"} = 1;
            $sth->execute($dupe_of);
            $dupe_of = $sth->fetchrow_array;
        }

        # Also, let's see if the reporter has authorization to see
        # the bug to which we are duping. If not we need to prompt.
        DuplicateUserConfirm();

        # DUPLICATE bugs should have no time remaining.
        _remove_remaining_time();

        ChangeStatus('RESOLVED');
        ChangeResolution('DUPLICATE');
        my $comment = $cgi->param('comment');
        $comment .= "\n\n*** This bug has been marked " .
                    "as a duplicate of bug $duplicate ***";
        $cgi->param('comment', $comment);
        last SWITCH;
    };

    ThrowCodeError("unknown_action", { action => $cgi->param('knob') });
}

my @keywordlist;
my %keywordseen;

if (defined $cgi->param('keywords')) {
    foreach my $keyword (split(/[\s,]+/, $cgi->param('keywords'))) {
        if ($keyword eq '') {
            next;
        }
        my $i = GetKeywordIdFromName($keyword);
        if (!$i) {
            ThrowUserError("unknown_keyword",
                           { keyword => $keyword });
        }
        if (!$keywordseen{$i}) {
            push(@keywordlist, $i);
            $keywordseen{$i} = 1;
        }
    }
}

my $keywordaction = $cgi->param('keywordaction') || "makeexact";
if (!grep($keywordaction eq $_, qw(add delete makeexact))) {
    $keywordaction = "makeexact";
}

if ($::comma eq ""
    && (! @groupAdd) && (! @groupDel)
    && (! @::legal_keywords || (0 == @keywordlist && $keywordaction ne "makeexact"))
    && defined $cgi->param('masscc') && ! $cgi->param('masscc')
    ) {
    if (!defined $cgi->param('comment') || $cgi->param('comment') =~ /^\s*$/) {
        ThrowUserError("bugs_not_changed");
    }
}

# Process data for Time Tracking fields
if (UserInGroup(Param('timetrackinggroup'))) {
    foreach my $field ("estimated_time", "remaining_time") {
        if (defined $cgi->param($field)) {
            my $er_time = trim($cgi->param($field));
            if ($er_time ne $cgi->param('dontchange')) {
                DoComma();
                $::query .= "$field = " . SqlQuote($er_time);
            }
        }
    }

    if (defined $cgi->param('deadline')) {
        DoComma();
        $::query .= "deadline = ";
        if ($cgi->param('deadline')) {
            validate_date($cgi->param('deadline'))
              || ThrowUserError('illegal_date', {date => $cgi->param('deadline'),
                                                 format => 'YYYY-MM-DD'});
            $::query .= SqlQuote($cgi->param('deadline'));
        } else {
            $::query .= "NULL" ;
        }
    }
}

my $basequery = $::query;
my $delta_ts;


sub SnapShotBug {
    my ($id) = (@_);
    SendSQL("SELECT delta_ts, " . join(',', @::log_columns) .
            " FROM bugs WHERE bug_id = $id");
    my @row = FetchSQLData();
    $delta_ts = shift @row;

    return @row;
}


sub SnapShotDeps {
    my ($i, $target, $me) = (@_);
    SendSQL("SELECT $target FROM dependencies WHERE $me = $i ORDER BY $target");
    my @list;
    while (MoreSQLData()) {
        push(@list, FetchOneColumn());
    }
    return join(',', @list);
}


my $timestamp;
my $bug_changed;

sub LogDependencyActivity {
    my ($i, $oldstr, $target, $me, $timestamp) = (@_);
    my $sql_timestamp = SqlQuote($timestamp);
    my $newstr = SnapShotDeps($i, $target, $me);
    if ($oldstr ne $newstr) {
        # Figure out what's really different...
        my ($removed, $added) = diff_strings($oldstr, $newstr);
        LogActivityEntry($i,$target,$removed,$added,$whoid,$timestamp);
        # update timestamp on target bug so midairs will be triggered
        SendSQL("UPDATE bugs SET delta_ts = $sql_timestamp WHERE bug_id = $i");
        $bug_changed = 1;
        return 1;
    }
    return 0;
}

if (Param("strict_isolation")) {
    my @blocked_cc = ();
    foreach my $pid (keys %cc_add) {
        $usercache{$pid} ||= Bugzilla::User->new($pid);
        my $cc_user = $usercache{$pid};
        foreach my $product_id (@newprod_ids) {
            if (!$cc_user->can_edit_product($product_id)) {
                push (@blocked_cc, $cc_user->login);
                last;
            }
        }
    }
    if (scalar(@blocked_cc)) {
        ThrowUserError("invalid_user_group", 
            {'users' => \@blocked_cc,
             'bug_id' => (scalar(@idlist) > 1) ? undef : $idlist[0]});
    }
}

if ($prod_changed && Param("strict_isolation")) {
    my $sth_cc = $dbh->prepare("SELECT who
                                FROM cc
                                WHERE bug_id = ?");
    my $sth_bug = $dbh->prepare("SELECT assigned_to, qa_contact
                                 FROM bugs
                                 WHERE bug_id = ?");
    my $prod_name = get_product_name($prod_id);
    foreach my $id (@idlist) {
        $sth_cc->execute($id);
        my @blocked_cc = ();
        while (my ($pid) = $sth_cc->fetchrow_array) {
            $usercache{$pid} ||= Bugzilla::User->new($pid);
            my $cc_user = $usercache{$pid};
            if (!$cc_user->can_edit_product($prod_id)) {
                push (@blocked_cc, $cc_user->login);
            }
        }
        if (scalar(@blocked_cc)) {
            ThrowUserError('invalid_user_group',
                              {'users'   => \@blocked_cc,
                               'bug_id' => $id,
                               'product' => $prod_name});
        }
        $sth_bug->execute($id);
        my ($assignee, $qacontact) = $sth_bug->fetchrow_array;
        if (!$assignee_checked) {
            $usercache{$assignee} ||= Bugzilla::User->new($assignee);
            my $assign_user = $usercache{$assignee};
            if (!$assign_user->can_edit_product($prod_id)) {
                    ThrowUserError('invalid_user_group',
                                      {'users'   => $assign_user->login,
                                       'bug_id' => $id,
                                       'product' => $prod_name});
            }
        }
        if (!$qacontact_checked && $qacontact) {
            $usercache{$qacontact} ||= Bugzilla::User->new($qacontact);
            my $qa_user = $usercache{$qacontact};
            if (!$qa_user->can_edit_product($prod_id)) {
                    ThrowUserError('invalid_user_group',
                                      {'users'   => $qa_user->login,
                                       'bug_id' => $id,
                                       'product' => $prod_name});
            }
        }
    }
}


# This loop iterates once for each bug to be processed (i.e. all the
# bugs selected when this script is called with multiple bugs selected
# from buglist.cgi, or just the one bug when called from
# show_bug.cgi).
#
foreach my $id (@idlist) {
    my $query = $basequery;
    my $bug_obj = new Bugzilla::Bug($id, $whoid);

    if ($cgi->param('knob') eq 'reassignbycomponent') {
        # We have to check whether the bug is moved to another product
        # and/or component before reassigning. If $comp_id is defined,
        # use it; else use the product/component the bug is already in.
        my $new_comp_id = $comp_id || $bug_obj->{'component_id'};
        $assignee = $dbh->selectrow_array('SELECT initialowner
                                           FROM components
                                           WHERE components.id = ?',
                                           undef, $new_comp_id);
        $query .= ", assigned_to = $assignee";
        if (Param("useqacontact")) {
            $qacontact = $dbh->selectrow_array('SELECT initialqacontact
                                                FROM components
                                                WHERE components.id = ?',
                                                undef, $new_comp_id);
            if ($qacontact) {
                $query .= ", qa_contact = $qacontact";
            }
            else {
                $query .= ", qa_contact = NULL";
            }
        }
    }

    my %dependencychanged;
    $bug_changed = 0;
    my $write = "WRITE";        # Might want to make a param to control
                                # whether we do LOW_PRIORITY ...
    $dbh->bz_lock_tables("bugs $write", "bugs_activity $write",
            "cc $write", "cc AS selectVisible_cc $write",
            "profiles READ", "dependencies $write", "votes $write",
            "products READ", "components READ",
            "keywords $write", "longdescs $write", "fielddefs $write",
            "bug_group_map $write", "flags $write", "duplicates $write",
            "user_group_map READ", "group_group_map READ", "flagtypes READ",
            "flaginclusions AS i READ", "flagexclusions AS e READ",
            "keyworddefs READ", "groups READ", "attachments READ",
            "group_control_map AS oldcontrolmap READ",
            "group_control_map AS newcontrolmap READ",
            "group_control_map READ", "email_setting READ");

    # It may sound crazy to set %formhash for each bug as $cgi->param()
    # will not change, but %formhash is modified below and we prefer
    # to set it again.
    my $i = 0;
    my @oldvalues = SnapShotBug($id);
    my %oldhash;
    my %formhash;
    foreach my $col (@::log_columns) {
        # Consider NULL db entries to be equivalent to the empty string
        $oldvalues[$i] = defined($oldvalues[$i]) ? $oldvalues[$i] : '';
        # Convert the deadline taken from the DB into the YYYY-MM-DD format
        # for consistency with the deadline provided by the user, if any.
        # Else CheckCanChangeField() would see them as different in all cases.
        if ($col eq 'deadline') {
            $oldvalues[$i] = format_time($oldvalues[$i], "%Y-%m-%d");
        }
        $oldhash{$col} = $oldvalues[$i];
        $formhash{$col} = $cgi->param($col) if defined $cgi->param($col);
        $i++;
    }
    # If the user is reassigning bugs, we need to:
    # - convert $newhash{'assigned_to'} and $newhash{'qa_contact'}
    #   email addresses into their corresponding IDs;
    # - update $newhash{'bug_status'} to its real state if the bug
    #   is in the unconfirmed state.
    $formhash{'qa_contact'} = $qacontact if Param('useqacontact');
    if ($cgi->param('knob') eq 'reassignbycomponent'
        || $cgi->param('knob') eq 'reassign') {
        $formhash{'assigned_to'} = $assignee;
        if ($oldhash{'bug_status'} eq 'UNCONFIRMED') {
            $formhash{'bug_status'} = $oldhash{'bug_status'};
        }
    }
    foreach my $col (@::log_columns) {
        if (exists $formhash{$col}
            && !CheckCanChangeField($col, $id, $oldhash{$col}, $formhash{$col}))
        {
            my $vars;
            if ($col eq 'component_id') {
                # Display the component name
                $vars->{'oldvalue'} = get_component_name($oldhash{$col});
                $vars->{'newvalue'} = $cgi->param('component');
                $vars->{'field'} = 'component';
            } elsif ($col eq 'assigned_to' || $col eq 'qa_contact') {
                # Display the assignee or QA contact email address
                $vars->{'oldvalue'} = DBID_to_name($oldhash{$col});
                $vars->{'newvalue'} = DBID_to_name($formhash{$col});
                $vars->{'field'} = $col;
            } else {
                $vars->{'oldvalue'} = $oldhash{$col};
                $vars->{'newvalue'} = $formhash{$col};
                $vars->{'field'} = $col;
            }
            $vars->{'privs'} = $PrivilegesRequired;
            ThrowUserError("illegal_change", $vars);
        }
    }
    
    # When editing multiple bugs, users can specify a list of keywords to delete
    # from bugs.  If the list matches the current set of keywords on those bugs,
    # CheckCanChangeField above will fail to check permissions because it thinks
    # the list hasn't changed.  To fix that, we have to call CheckCanChangeField
    # again with old!=new if the keyword action is "delete" and old=new.
    if ($keywordaction eq "delete"
        && defined $cgi->param('keywords')
        && length(@keywordlist) > 0
        && $cgi->param('keywords') eq $oldhash{keywords}
        && !CheckCanChangeField("keywords", $id, "old is not", "equal to new"))
    {
        $vars->{'oldvalue'} = $oldhash{keywords};
        $vars->{'newvalue'} = "no keywords";
        $vars->{'field'} = "keywords";
        $vars->{'privs'} = $PrivilegesRequired;
        ThrowUserError("illegal_change", $vars);
    }

    $oldhash{'product'} = get_product_name($oldhash{'product_id'});
    if (!Bugzilla->user->can_edit_product($oldhash{'product_id'})) {
        ThrowUserError("product_edit_denied",
                      { product => $oldhash{'product'} });
    }

    if ($requiremilestone) {
        # musthavemilestoneonaccept applies only if at least two
        # target milestones are defined for the current product.
        my $nb_milestones = scalar(@{$::target_milestone{$oldhash{'product'}}});
        if ($nb_milestones > 1) {
            my $value = $cgi->param('target_milestone');
            if (!defined $value || $value eq $cgi->param('dontchange')) {
                $value = $oldhash{'target_milestone'};
            }
            my $defaultmilestone =
                $dbh->selectrow_array("SELECT defaultmilestone
                                       FROM products WHERE id = ?",
                                       undef, $oldhash{'product_id'});
            # if musthavemilestoneonaccept == 1, then the target
            # milestone must be different from the default one.
            if ($value eq $defaultmilestone) {
                ThrowUserError("milestone_required", { bug_id => $id });
            }
        }
    }   
    if (defined $cgi->param('delta_ts') && $cgi->param('delta_ts') ne $delta_ts)
    {
        ($vars->{'operations'}) =
            Bugzilla::Bug::GetBugActivity($id, $cgi->param('delta_ts'));

        $vars->{'start_at'} = $cgi->param('longdesclength');

        # Always sort midair collision comments oldest to newest,
        # regardless of the user's personal preference.
        $vars->{'comments'} = Bugzilla::Bug::GetComments($id, "oldest_to_newest");

        $cgi->param('delta_ts', $delta_ts);
        
        $vars->{'bug_id'} = $id;
        
        $dbh->bz_unlock_tables(UNLOCK_ABORT);
        
        # Warn the user about the mid-air collision and ask them what to do.
        $template->process("bug/process/midair.html.tmpl", $vars)
          || ThrowTemplateError($template->error());
        exit;
    }

    # Gather the dependency list, and make sure there are no circular refs
    my %deps = Bugzilla::Bug::ValidateDependencies(scalar($cgi->param('dependson')),
                                                   scalar($cgi->param('blocked')),
                                                   $id);

    #
    # Start updating the relevant database entries
    #

    SendSQL("select now()");
    $timestamp = FetchOneColumn();
    my $sql_timestamp = SqlQuote($timestamp);

    my $work_time;
    if (UserInGroup(Param('timetrackinggroup'))) {
        $work_time = $cgi->param('work_time');
        if ($work_time) {
            # AppendComment (called below) can in theory raise an error,
            # but because we've already validated work_time here it's
            # safe to log the entry before adding the comment.
            LogActivityEntry($id, "work_time", "", $work_time,
                             $whoid, $timestamp);
        }
    }

    if ($cgi->param('comment') || $work_time) {
        AppendComment($id, $whoid, scalar($cgi->param('comment')),
                      scalar($cgi->param('commentprivacy')), $timestamp, $work_time);
        $bug_changed = 1;
    }

    if (@::legal_keywords && defined $cgi->param('keywords')) {
        # There are three kinds of "keywordsaction": makeexact, add, delete.
        # For makeexact, we delete everything, and then add our things.
        # For add, we delete things we're adding (to make sure we don't
        # end up having them twice), and then we add them.
        # For delete, we just delete things on the list.
        my $changed = 0;
        if ($keywordaction eq "makeexact") {
            SendSQL("DELETE FROM keywords WHERE bug_id = $id");
            $changed = 1;
        }
        foreach my $keyword (@keywordlist) {
            if ($keywordaction ne "makeexact") {
                SendSQL("DELETE FROM keywords
                         WHERE bug_id = $id AND keywordid = $keyword");
                $changed = 1;
            }
            if ($keywordaction ne "delete") {
                SendSQL("INSERT INTO keywords 
                         (bug_id, keywordid) VALUES ($id, $keyword)");
                $changed = 1;
            }
        }
        if ($changed) {
            SendSQL("SELECT keyworddefs.name 
                     FROM keyworddefs INNER JOIN keywords
                       ON keyworddefs.id = keywords.keywordid
                     WHERE keywords.bug_id = $id
                     ORDER BY keyworddefs.name");
            my @list;
            while (MoreSQLData()) {
                push(@list, FetchOneColumn());
            }
            $dbh->do("UPDATE bugs SET keywords = ? WHERE bug_id = ?",
                     undef, join(', ', @list), $id);
        }
    }
    $query .= " where bug_id = $id";

    if ($::comma ne "") {
        SendSQL($query);
    }

    # Check for duplicates if the bug is [re]open
    SendSQL("SELECT resolution FROM bugs WHERE bug_id = $id");
    my $resolution = FetchOneColumn();
    if ($resolution eq '') {
        SendSQL("DELETE FROM duplicates WHERE dupe = $id");
    }
    
    my $newproduct_id = $oldhash{'product_id'};
    if ($cgi->param('product') ne $cgi->param('dontchange')) {
        my $newproduct_id = get_product_id($cgi->param('product'));
    }

    my %groupsrequired = ();
    my %groupsforbidden = ();
    SendSQL("SELECT id, membercontrol 
             FROM groups LEFT JOIN group_control_map
             ON id = group_id
             AND product_id = $newproduct_id WHERE isactive != 0");
    while (MoreSQLData()) {
        my ($group, $control) = FetchSQLData();
        $control ||= 0;
        unless ($control > &::CONTROLMAPNA)  {
            $groupsforbidden{$group} = 1;
        }
        if ($control == &::CONTROLMAPMANDATORY) {
            $groupsrequired{$group} = 1;
        }
    }

    my @groupAddNames = ();
    my @groupAddNamesAll = ();
    foreach my $grouptoadd (@groupAdd, keys %groupsrequired) {
        next if $groupsforbidden{$grouptoadd};
        push(@groupAddNamesAll, GroupIdToName($grouptoadd));
        if (!BugInGroupId($id, $grouptoadd)) {
            push(@groupAddNames, GroupIdToName($grouptoadd));
            SendSQL("INSERT INTO bug_group_map (bug_id, group_id) 
                     VALUES ($id, $grouptoadd)");
        }
    }
    my @groupDelNames = ();
    my @groupDelNamesAll = ();
    foreach my $grouptodel (@groupDel, keys %groupsforbidden) {
        push(@groupDelNamesAll, GroupIdToName($grouptodel));
        next if $groupsrequired{$grouptodel};
        if (BugInGroupId($id, $grouptodel)) {
            push(@groupDelNames, GroupIdToName($grouptodel));
        }
        SendSQL("DELETE FROM bug_group_map 
                 WHERE bug_id = $id AND group_id = $grouptodel");
    }

    my $groupDelNames = join(',', @groupDelNames);
    my $groupAddNames = join(',', @groupAddNames);

    if ($groupDelNames ne $groupAddNames) {
        LogActivityEntry($id, "bug_group", $groupDelNames, $groupAddNames,
                         $whoid, $timestamp); 
        $bug_changed = 1;
    }

    my @ccRemoved = (); 
    if (defined $cgi->param('newcc')
        || defined $cgi->param('addselfcc')
        || defined $cgi->param('removecc')
        || defined $cgi->param('masscc')) {
        # Get the current CC list for this bug
        my %oncc;
        SendSQL("SELECT who FROM cc WHERE bug_id = $id");
        while (MoreSQLData()) {
            $oncc{FetchOneColumn()} = 1;
        }

        my (@added, @removed) = ();
 
        foreach my $pid (keys %cc_add) {
            # If this person isn't already on the cc list, add them
            if (! $oncc{$pid}) {
                SendSQL("INSERT INTO cc (bug_id, who) VALUES ($id, $pid)");
                push (@added, $cc_add{$pid});
                $oncc{$pid} = 1;
            }
        }
        foreach my $pid (keys %cc_remove) {
            # If the person is on the cc list, remove them
            if ($oncc{$pid}) {
                SendSQL("DELETE FROM cc WHERE bug_id = $id AND who = $pid");
                push (@removed, $cc_remove{$pid});
                $oncc{$pid} = 0;
            }
        }

        # If any changes were found, record it in the activity log
        if (scalar(@removed) || scalar(@added)) {
            my $removed = join(", ", @removed);
            my $added = join(", ", @added);
            LogActivityEntry($id,"cc",$removed,$added,$whoid,$timestamp);
            $bug_changed = 1;
        }
        @ccRemoved = @removed;
    }

    # We need to send mail for dependson/blocked bugs if the dependencies
    # change or the status or resolution change. This var keeps track of that.
    my $check_dep_bugs = 0;

    foreach my $pair ("blocked/dependson", "dependson/blocked") {
        my ($me, $target) = split("/", $pair);

        my @oldlist = @{$dbh->selectcol_arrayref("SELECT $target FROM dependencies
                                                  WHERE $me = ? ORDER BY $target",
                                                  undef, $id)};
        @dependencychanged{@oldlist} = 1;

        if (defined $cgi->param($target)) {
            my %snapshot;
            my @newlist = sort {$a <=> $b} @{$deps{$target}};
            @dependencychanged{@newlist} = 1;

            while (0 < @oldlist || 0 < @newlist) {
                if (@oldlist == 0 || (@newlist > 0 &&
                                      $oldlist[0] > $newlist[0])) {
                    $snapshot{$newlist[0]} = SnapShotDeps($newlist[0], $me,
                                                          $target);
                    shift @newlist;
                } elsif (@newlist == 0 || (@oldlist > 0 &&
                                           $newlist[0] > $oldlist[0])) {
                    $snapshot{$oldlist[0]} = SnapShotDeps($oldlist[0], $me,
                                                          $target);
                    shift @oldlist;
                } else {
                    if ($oldlist[0] != $newlist[0]) {
                        $dbh->bz_unlock_tables(UNLOCK_ABORT);
                        die "Error in list comparing code";
                    }
                    shift @oldlist;
                    shift @newlist;
                }
            }
            my @keys = keys(%snapshot);
            if (@keys) {
                my $oldsnap = SnapShotDeps($id, $target, $me);
                SendSQL("delete from dependencies where $me = $id");
                foreach my $i (@{$deps{$target}}) {
                    SendSQL("insert into dependencies ($me, $target) values ($id, $i)");
                }
                foreach my $k (@keys) {
                    LogDependencyActivity($k, $snapshot{$k}, $me, $target, $timestamp);
                }
                LogDependencyActivity($id, $oldsnap, $target, $me, $timestamp);
                $check_dep_bugs = 1;
            }
        }
    }

    # When a bug changes products and the old or new product is associated
    # with a bug group, it may be necessary to remove the bug from the old
    # group or add it to the new one.  There are a very specific series of
    # conditions under which these activities take place, more information
    # about which can be found in comments within the conditionals below.
    # Check if the user has changed the product to which the bug belongs;
    if ($cgi->param('product') ne $cgi->param('dontchange')
        && $cgi->param('product') ne $oldhash{'product'}
    ) {
        $newproduct_id = get_product_id($cgi->param('product'));
        # Depending on the "addtonewgroup" variable, groups with
        # defaults will change.
        #
        # For each group, determine
        # - The group id and if it is active
        # - The control map value for the old product and this group
        # - The control map value for the new product and this group
        # - Is the user in this group?
        # - Is the bug in this group?
        SendSQL("SELECT DISTINCT groups.id, isactive, " .
                "oldcontrolmap.membercontrol, newcontrolmap.membercontrol, " .
                "CASE WHEN groups.id IN ($grouplist) THEN 1 ELSE 0 END, " .
                "CASE WHEN bug_group_map.group_id IS NOT NULL " .
                "THEN 1 ELSE 0 END " .
                "FROM groups " .
                "LEFT JOIN group_control_map AS oldcontrolmap " .
                "ON oldcontrolmap.group_id = groups.id " .
                "AND oldcontrolmap.product_id = " . $oldhash{'product_id'} .
                " LEFT JOIN group_control_map AS newcontrolmap " .
                "ON newcontrolmap.group_id = groups.id " .
                "AND newcontrolmap.product_id = $newproduct_id " .
                "LEFT JOIN bug_group_map " .
                "ON bug_group_map.group_id = groups.id " .
                "AND bug_group_map.bug_id = $id "
            );
        my @groupstoremove = ();
        my @groupstoadd = ();
        my @defaultstoremove = ();
        my @defaultstoadd = ();
        my @allgroups = ();
        my $buginanydefault = 0;
        my $buginanychangingdefault = 0;
        while (MoreSQLData()) {
            my ($groupid, $isactive, $oldcontrol, $newcontrol, 
            $useringroup, $bugingroup) = FetchSQLData();
            # An undefined newcontrol is none.
            $newcontrol = CONTROLMAPNA unless $newcontrol;
            $oldcontrol = CONTROLMAPNA unless $oldcontrol;
            push(@allgroups, $groupid);
            if (($bugingroup) && ($isactive)
                && ($oldcontrol == CONTROLMAPDEFAULT)) {
                # Bug was in a default group.
                $buginanydefault = 1;
                if (($newcontrol != CONTROLMAPDEFAULT)
                    && ($newcontrol != CONTROLMAPMANDATORY)) {
                    # Bug was in a default group that no longer is.
                    $buginanychangingdefault = 1;
                    push (@defaultstoremove, $groupid);
                }
            }
            if (($isactive) && (!$bugingroup)
                && ($newcontrol == CONTROLMAPDEFAULT)
                && ($useringroup)) {
                push (@defaultstoadd, $groupid);
            }
            if (($bugingroup) && ($isactive) && ($newcontrol == CONTROLMAPNA)) {
                # Group is no longer permitted.
                push(@groupstoremove, $groupid);
            }
            if ((!$bugingroup) && ($isactive) 
                && ($newcontrol == CONTROLMAPMANDATORY)) {
                # Group is now required.
                push(@groupstoadd, $groupid);
            }
        }
        # If addtonewgroups = "yes", old default groups will be removed
        # and new default groups will be added.
        # If addtonewgroups = "yesifinold", old default groups will be removed
        # and new default groups will be added only if the bug was in ANY
        # of the old default groups.
        # If addtonewgroups = "no", old default groups will be removed and not
        # replaced.
        push(@groupstoremove, @defaultstoremove);
        if (AnyDefaultGroups()
            && (($cgi->param('addtonewgroup') eq 'yes')
            || (($cgi->param('addtonewgroup') eq 'yesifinold')
            && ($buginanydefault)))) {
            push(@groupstoadd, @defaultstoadd);
        }

        # Now actually update the bug_group_map.
        my @DefGroupsAdded = ();
        my @DefGroupsRemoved = ();
        foreach my $groupid (@allgroups) {
            my $thisadd = grep( ($_ == $groupid), @groupstoadd);
            my $thisdel = grep( ($_ == $groupid), @groupstoremove);
            if ($thisadd) {
                push(@DefGroupsAdded, GroupIdToName($groupid));
                SendSQL("INSERT INTO bug_group_map (bug_id, group_id) VALUES " .
                        "($id, $groupid)");
            } elsif ($thisdel) {
                push(@DefGroupsRemoved, GroupIdToName($groupid));
                SendSQL("DELETE FROM bug_group_map WHERE bug_id = $id " .
                        "AND group_id = $groupid");
            }
        }
        if ((@DefGroupsAdded) || (@DefGroupsRemoved)) {
            LogActivityEntry($id, "bug_group",
                join(', ', @DefGroupsRemoved),
                join(', ', @DefGroupsAdded),
                     $whoid, $timestamp); 
        }
    }
  
    # get a snapshot of the newly set values out of the database, 
    # and then generate any necessary bug activity entries by seeing 
    # what has changed since before we wrote out the new values.
    #
    my @newvalues = SnapShotBug($id);
    my %newhash;
    $i = 0;
    foreach my $col (@::log_columns) {
        # Consider NULL db entries to be equivalent to the empty string
        $newvalues[$i] = defined($newvalues[$i]) ? $newvalues[$i] : '';
        # Convert the deadline to the YYYY-MM-DD format.
        if ($col eq 'deadline') {
            $newvalues[$i] = format_time($newvalues[$i], "%Y-%m-%d");
        }
        $newhash{$col} = $newvalues[$i];
        $i++;
    }
    # for passing to Bugzilla::BugMail to ensure that when someone is removed
    # from one of these fields, they get notified of that fact (if desired)
    #
    my $origOwner = "";
    my $origQaContact = "";
    
    foreach my $c (@::log_columns) {
        my $col = $c;           # We modify it, don't want to modify array
                                # values in place.
        my $old = shift @oldvalues;
        my $new = shift @newvalues;
        if ($old ne $new) {

            # Products and components are now stored in the DB using ID's
            # We need to translate this to English before logging it
            if ($col eq 'product_id') {
                $old = get_product_name($old);
                $new = get_product_name($new);
                $col = 'product';
            }
            if ($col eq 'component_id') {
                $old = get_component_name($old);
                $new = get_component_name($new);
                $col = 'component';
            }

            # save off the old value for passing to Bugzilla::BugMail so
            # the old assignee can be notified
            #
            if ($col eq 'assigned_to') {
                $old = ($old) ? DBID_to_name($old) : "";
                $new = ($new) ? DBID_to_name($new) : "";
                $origOwner = $old;
            }

            # ditto for the old qa contact
            #
            if ($col eq 'qa_contact') {
                $old = ($old) ? DBID_to_name($old) : "";
                $new = ($new) ? DBID_to_name($new) : "";
                $origQaContact = $old;
            }

            # If this is the keyword field, only record the changes, not everything.
            if ($col eq 'keywords') {
                ($old, $new) = diff_strings($old, $new);
            }

            if ($col eq 'product') {
                RemoveVotes($id, 0,
                            "This bug has been moved to a different product");
            }
            
            if ($col eq 'bug_status' 
                && IsOpenedState($old) ne IsOpenedState($new))
            {
                $check_dep_bugs = 1;
            }

            LogActivityEntry($id,$col,$old,$new,$whoid,$timestamp);
            $bug_changed = 1;
        }
    }
    # Set and update flags.
    Bugzilla::Flag::process($id, undef, $timestamp, $cgi);

    if ($bug_changed) {
        SendSQL("UPDATE bugs SET delta_ts = $sql_timestamp WHERE bug_id = $id");
    }
    $dbh->bz_unlock_tables();

    if ($duplicate) {
        # Check to see if Reporter of this bug is reporter of Dupe 
        SendSQL("SELECT reporter FROM bugs WHERE bug_id = " .
                $cgi->param('id'));
        my $reporter = FetchOneColumn();
        SendSQL("SELECT reporter FROM bugs WHERE bug_id = " .
                "$duplicate and reporter = $reporter");
        my $isreporter = FetchOneColumn();
        SendSQL("SELECT who FROM cc WHERE bug_id = " .
                " $duplicate and who = $reporter");
        my $isoncc = FetchOneColumn();
        unless ($isreporter || $isoncc
                || !$cgi->param('confirm_add_duplicate')) {
            # The reporter is oblivious to the existence of the new bug and is permitted access
            # ... add 'em to the cc (and record activity)
            LogActivityEntry($duplicate,"cc","",DBID_to_name($reporter),
                             $whoid,$timestamp);
            SendSQL("INSERT INTO cc (who, bug_id) " .
                    "VALUES ($reporter, $duplicate)");
        }
        # Bug 171639 - Duplicate notifications do not need to be private. 
        AppendComment($duplicate, $whoid,
                      "*** Bug " . $cgi->param('id') .
                      " has been marked as a duplicate of this bug. ***",
                      0, $timestamp);

        check_form_field_defined($cgi,'comment');
        SendSQL("INSERT INTO duplicates VALUES ($duplicate, " .
                $cgi->param('id') . ")");
    }

    # Now all changes to the DB have been made. It's time to email
    # all concerned users, including the bug itself, but also the
    # duplicated bug and dependent bugs, if any.

    $vars->{'mailrecipients'} = { 'cc' => \@ccRemoved,
                                  'owner' => $origOwner,
                                  'qacontact' => $origQaContact,
                                  'changer' => Bugzilla->user->login };

    $vars->{'id'} = $id;
    $vars->{'type'} = "bug";
    
    # Let the user know the bug was changed and who did and didn't
    # receive email about the change.
    $template->process("bug/process/results.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
    $vars->{'header_done'} = 1;
    
    if ($duplicate) {
        $vars->{'mailrecipients'} = { 'changer' => Bugzilla->user->login }; 

        $vars->{'id'} = $duplicate;
        $vars->{'type'} = "dupe";
        
        # Let the user know a duplication notation was added to the original bug.
        $template->process("bug/process/results.html.tmpl", $vars)
          || ThrowTemplateError($template->error());
        $vars->{'header_done'} = 1;
    }

    if ($check_dep_bugs) {
        foreach my $k (keys(%dependencychanged)) {
            $vars->{'mailrecipients'} = { 'changer' => Bugzilla->user->login }; 
            $vars->{'id'} = $k;
            $vars->{'type'} = "dep";

            # Let the user (if he is able to see the bug) know we checked to see 
            # if we should email notice of this change to users with a relationship
            # to the dependent bug and who did and didn't receive email about it.
            $template->process("bug/process/results.html.tmpl", $vars)
              || ThrowTemplateError($template->error());
            $vars->{'header_done'} = 1;
        }
    }
}

# Determine if Patch Viewer is installed, for Diff link
# (NB: Duplicate code with show_bug.cgi.)
eval {
    require PatchReader;
    $vars->{'patchviewerinstalled'} = 1;
};

if (defined $cgi->param('id')) {
    $action = Bugzilla->user->settings->{'post_bug_submit_action'}->{'value'};
} else {
    # param('id') is not defined when changing multiple bugs
    $action = 'nothing';
}

if ($action eq 'next_bug') {
    my $next_bug;
    my $cur = lsearch(\@bug_list, $cgi->param("id"));
    if ($cur >= 0 && $cur < $#bug_list) {
        $next_bug = $bug_list[$cur + 1];
    }
    if ($next_bug) {
        if (detaint_natural($next_bug) && Bugzilla->user->can_see_bug($next_bug)) {
            my $bug = new Bugzilla::Bug($next_bug, $whoid);
            ThrowCodeError("bug_error", { bug => $bug }) if $bug->error;

            $vars->{'bugs'} = [$bug];
            $vars->{'nextbug'} = $bug->bug_id;

            $template->process("bug/show.html.tmpl", $vars)
              || ThrowTemplateError($template->error());

            exit;
        }
    }
} elsif ($action eq 'same_bug') {
    if (Bugzilla->user->can_see_bug($cgi->param('id'))) {
        my $bug = new Bugzilla::Bug($cgi->param('id'), $whoid);
        ThrowCodeError("bug_error", { bug => $bug }) if $bug->error;

        $vars->{'bugs'} = [$bug];

        $template->process("bug/show.html.tmpl", $vars)
          || ThrowTemplateError($template->error());

        exit;
    }
} elsif ($action ne 'nothing') {
    ThrowCodeError("invalid_post_bug_submit_action");
}

# End the response page.
$template->process("bug/navigate.html.tmpl", $vars)
  || ThrowTemplateError($template->error());
$template->process("global/footer.html.tmpl", $vars)
  || ThrowTemplateError($template->error());
