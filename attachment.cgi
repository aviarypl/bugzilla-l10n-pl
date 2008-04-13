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
#                 Myk Melez <myk@mozilla.org>
#                 Daniel Raichle <draichle@gmx.net>
#                 Dave Miller <justdave@syndicomm.com>
#                 Alexander J. Vincent <ajvincent@juno.com>
#                 Max Kanat-Alexander <mkanat@bugzilla.org>
#                 Greg Hendricks <ghendricks@novell.com>
#                 Frédéric Buclin <LpSolit@gmail.com>
#                 Marc Schumann <wurblzap@gmail.com>

################################################################################
# Script Initialization
################################################################################

# Make it harder for us to do dangerous things in Perl.
use strict;

use lib qw(. lib);

use Bugzilla;
use Bugzilla::Constants;
use Bugzilla::Error;
use Bugzilla::Flag; 
use Bugzilla::FlagType; 
use Bugzilla::User;
use Bugzilla::Util;
use Bugzilla::Bug;
use Bugzilla::Field;
use Bugzilla::Attachment;
use Bugzilla::Attachment::PatchReader;
use Bugzilla::Token;
use Bugzilla::Keyword;

Bugzilla->login();

# For most scripts we don't make $cgi and $template global variables. But
# when preparing Bugzilla for mod_perl, this script used these
# variables in so many subroutines that it was easier to just
# make them globals.
local our $cgi = Bugzilla->cgi;
local our $template = Bugzilla->template;
local our $vars = {};

################################################################################
# Main Body Execution
################################################################################

# All calls to this script should contain an "action" variable whose
# value determines what the user wants to do.  The code below checks
# the value of that variable and runs the appropriate code. If none is
# supplied, we default to 'view'.

# Determine whether to use the action specified by the user or the default.
my $action = $cgi->param('action') || 'view';

# Determine if PatchReader is installed
eval {
    require PatchReader;
    $vars->{'patchviewerinstalled'} = 1;
};

if ($action eq "view")  
{
    view();
}
elsif ($action eq "interdiff")
{
    interdiff();
}
elsif ($action eq "diff")
{
    diff();
}
elsif ($action eq "viewall") 
{ 
    viewall(); 
}
elsif ($action eq "enter") 
{ 
    Bugzilla->login(LOGIN_REQUIRED);
    enter(); 
}
elsif ($action eq "insert")
{
    Bugzilla->login(LOGIN_REQUIRED);
    insert();
}
elsif ($action eq "edit") 
{ 
    edit(); 
}
elsif ($action eq "update") 
{ 
    Bugzilla->login(LOGIN_REQUIRED);
    update();
}
elsif ($action eq "delete") {
    delete_attachment();
}
else 
{ 
  ThrowCodeError("unknown_action", { action => $action });
}

exit;

################################################################################
# Data Validation / Security Authorization
################################################################################

# Validates an attachment ID. Optionally takes a parameter of a form
# variable name that contains the ID to be validated. If not specified,
# uses 'id'.
# 
# Will throw an error if 1) attachment ID is not a valid number,
# 2) attachment does not exist, or 3) user isn't allowed to access the
# attachment.
#
# Returns an attachment object.

sub validateID {
    my $param = @_ ? $_[0] : 'id';
    my $user = Bugzilla->user;

    # If we're not doing interdiffs, check if id wasn't specified and
    # prompt them with a page that allows them to choose an attachment.
    # Happens when calling plain attachment.cgi from the urlbar directly
    if ($param eq 'id' && !$cgi->param('id')) {
        print $cgi->header();
        $template->process("attachment/choose.html.tmpl", $vars) ||
            ThrowTemplateError($template->error());
        exit;
    }
    
    my $attach_id = $cgi->param($param);

    # Validate the specified attachment id. detaint kills $attach_id if
    # non-natural, so use the original value from $cgi in our exception
    # message here.
    detaint_natural($attach_id)
     || ThrowUserError("invalid_attach_id", { attach_id => $cgi->param($param) });
  
    # Make sure the attachment exists in the database.
    my $attachment = Bugzilla::Attachment->get($attach_id)
      || ThrowUserError("invalid_attach_id", { attach_id => $attach_id });

    # Make sure the user is authorized to access this attachment's bug.
    ValidateBugID($attachment->bug_id);
    if ($attachment->isprivate && $user->id != $attachment->attacher->id && !$user->is_insider) {
        ThrowUserError('auth_failure', {action => 'access',
                                        object => 'attachment'});
    }
    return $attachment;
}

# Validates format of a diff/interdiff. Takes a list as an parameter, which
# defines the valid format values. Will throw an error if the format is not
# in the list. Returns either the user selected or default format.
sub validateFormat
{
  # receives a list of legal formats; first item is a default
  my $format = $cgi->param('format') || $_[0];
  if ( lsearch(\@_, $format) == -1)
  {
     ThrowUserError("invalid_format", { format  => $format, formats => \@_ });
  }

  return $format;
}

# Validates context of a diff/interdiff. Will throw an error if the context
# is not number, "file" or "patch". Returns the validated, detainted context.
sub validateContext
{
  my $context = $cgi->param('context') || "patch";
  if ($context ne "file" && $context ne "patch") {
    detaint_natural($context)
      || ThrowUserError("invalid_context", { context => $cgi->param('context') });
  }

  return $context;
}

sub validateCanChangeBug
{
    my ($bugid) = @_;
    my $dbh = Bugzilla->dbh;
    my ($productid) = $dbh->selectrow_array(
            "SELECT product_id
             FROM bugs 
             WHERE bug_id = ?", undef, $bugid);

    Bugzilla->user->can_edit_product($productid)
      || ThrowUserError("illegal_attachment_edit_bug",
                        { bug_id => $bugid });
}

################################################################################
# Functions
################################################################################

# Display an attachment.
sub view {
    # Retrieve and validate parameters
    my $attachment = validateID();
    my $contenttype = $attachment->contenttype;
    my $filename = $attachment->filename;

    # Bug 111522: allow overriding content-type manually in the posted form
    # params.
    if (defined $cgi->param('content_type'))
    {
        $cgi->param('contenttypemethod', 'manual');
        $cgi->param('contenttypeentry', $cgi->param('content_type'));
        Bugzilla::Attachment->validate_content_type(THROW_ERROR);
        $contenttype = $cgi->param('content_type');
    }

    # Return the appropriate HTTP response headers.
    $attachment->datasize || ThrowUserError("attachment_removed");

    $filename =~ s/^.*[\/\\]//;
    # escape quotes and backslashes in the filename, per RFCs 2045/822
    $filename =~ s/\\/\\\\/g; # escape backslashes
    $filename =~ s/"/\\"/g; # escape quotes

    print $cgi->header(-type=>"$contenttype; name=\"$filename\"",
                       -content_disposition=> "inline; filename=\"$filename\"",
                       -content_length => $attachment->datasize);
    disable_utf8();
    print $attachment->data;
}

sub interdiff {
    # Retrieve and validate parameters
    my $old_attachment = validateID('oldid');
    my $new_attachment = validateID('newid');
    my $format = validateFormat('html', 'raw');
    my $context = validateContext();

    Bugzilla::Attachment::PatchReader::process_interdiff(
        $old_attachment, $new_attachment, $format, $context);
}

sub diff {
    # Retrieve and validate parameters
    my $attachment = validateID();
    my $format = validateFormat('html', 'raw');
    my $context = validateContext();

    # If it is not a patch, view normally.
    if (!$attachment->ispatch) {
        view();
        return;
    }

    Bugzilla::Attachment::PatchReader::process_diff($attachment, $format, $context);
}

# Display all attachments for a given bug in a series of IFRAMEs within one
# HTML page.
sub viewall {
    # Retrieve and validate parameters
    my $bugid = $cgi->param('bugid');
    ValidateBugID($bugid);
    my $bug = new Bugzilla::Bug($bugid);

    my $attachments = Bugzilla::Attachment->get_attachments_by_bug($bugid);

    # Define the variables and functions that will be passed to the UI template.
    $vars->{'bug'} = $bug;
    $vars->{'attachments'} = $attachments;

    print $cgi->header();

    # Generate and return the UI (HTML page) from the appropriate template.
    $template->process("attachment/show-multiple.html.tmpl", $vars)
      || ThrowTemplateError($template->error());
}

# Display a form for entering a new attachment.
sub enter {
  # Retrieve and validate parameters
  my $bugid = $cgi->param('bugid');
  ValidateBugID($bugid);
  validateCanChangeBug($bugid);
  my $dbh = Bugzilla->dbh;
  my $user = Bugzilla->user;

  my $bug = new Bugzilla::Bug($bugid, $user->id);
  # Retrieve the attachments the user can edit from the database and write
  # them into an array of hashes where each hash represents one attachment.
  my $canEdit = "";
  if (!$user->in_group('editbugs', $bug->product_id)) {
      $canEdit = "AND submitter_id = " . $user->id;
  }
  my $attach_ids = $dbh->selectcol_arrayref("SELECT attach_id FROM attachments
                                             WHERE bug_id = ? AND isobsolete = 0 $canEdit
                                             ORDER BY attach_id", undef, $bugid);

  # Define the variables and functions that will be passed to the UI template.
  $vars->{'bug'} = $bug;
  $vars->{'attachments'} = Bugzilla::Attachment->get_list($attach_ids);

  my $flag_types = Bugzilla::FlagType::match({'target_type'  => 'attachment',
                                              'product_id'   => $bug->product_id,
                                              'component_id' => $bug->component_id});
  $vars->{'flag_types'} = $flag_types;
  $vars->{'any_flags_requesteeble'} = grep($_->is_requesteeble, @$flag_types);

  print $cgi->header();

  # Generate and return the UI (HTML page) from the appropriate template.
  $template->process("attachment/create.html.tmpl", $vars)
    || ThrowTemplateError($template->error());
}

# Insert a new attachment into the database.
sub insert {
    my $dbh = Bugzilla->dbh;
    my $user = Bugzilla->user;

    $dbh->bz_start_transaction;

    # Retrieve and validate parameters
    my $bugid = $cgi->param('bugid');
    ValidateBugID($bugid);
    validateCanChangeBug($bugid);
    my ($timestamp) = Bugzilla->dbh->selectrow_array("SELECT NOW()");

    my $bug = new Bugzilla::Bug($bugid);
    my $attachment =
        Bugzilla::Attachment->insert_attachment_for_bug(THROW_ERROR, $bug, $user,
                                                        $timestamp, $vars);

    # Insert a comment about the new attachment into the database.
    my $comment = "Created an attachment (id=" . $attachment->id . ")\n" .
                  $attachment->description . "\n";
    $comment .= ("\n" . $cgi->param('comment')) if defined $cgi->param('comment');

    $bug->add_comment($comment, { isprivate => $attachment->isprivate });

  # Assign the bug to the user, if they are allowed to take it
  my $owner = "";
  if ($cgi->param('takebug') && $user->in_group('editbugs', $bug->product_id)) {
      # When taking a bug, we have to follow the workflow.
      my $bug_status = $cgi->param('bug_status') || '';
      ($bug_status) = grep {$_->name eq $bug_status} @{$bug->status->can_change_to};

      if ($bug_status && $bug_status->is_open
          && ($bug_status->name ne 'UNCONFIRMED' || $bug->product_obj->votes_to_confirm))
      {
          $bug->set_status($bug_status->name);
          $bug->clear_resolution();
      }
      # Make sure the person we are taking the bug from gets mail.
      $owner = $bug->assigned_to->login;
      $bug->set_assigned_to($user);
  }
  $bug->update($timestamp);

  $dbh->bz_commit_transaction;

  # Define the variables and functions that will be passed to the UI template.
  $vars->{'mailrecipients'} =  { 'changer' => $user->login,
                                 'owner'   => $owner };
  $vars->{'attachment'} = $attachment;
  # We cannot reuse the $bug object as delta_ts has eventually been updated
  # since the object was created.
  $vars->{'bugs'} = [new Bugzilla::Bug($bugid)];
  $vars->{'header_done'} = 1;
  $vars->{'contenttypemethod'} = $cgi->param('contenttypemethod');
  $vars->{'valid_keywords'} = [map($_->name, Bugzilla::Keyword->get_all)];
  $vars->{'use_keywords'} = 1 if Bugzilla::Keyword::keyword_count();

  print $cgi->header();
  # Generate and return the UI (HTML page) from the appropriate template.
  $template->process("attachment/created.html.tmpl", $vars)
    || ThrowTemplateError($template->error());
}

# Displays a form for editing attachment properties.
# Any user is allowed to access this page, unless the attachment
# is private and the user does not belong to the insider group.
# Validations are done later when the user submits changes.
sub edit {
  my $attachment = validateID();
  my $dbh = Bugzilla->dbh;

  # Retrieve a list of attachments for this bug as well as a summary of the bug
  # to use in a navigation bar across the top of the screen.
  my $bugattachments =
      Bugzilla::Attachment->get_attachments_by_bug($attachment->bug_id);
  # We only want attachment IDs.
  @$bugattachments = map { $_->id } @$bugattachments;

  my ($bugsummary, $product_id, $component_id) =
      $dbh->selectrow_array('SELECT short_desc, product_id, component_id
                               FROM bugs
                              WHERE bug_id = ?', undef, $attachment->bug_id);

  # Get a list of flag types that can be set for this attachment.
  my $flag_types = Bugzilla::FlagType::match({ 'target_type'  => 'attachment' ,
                                               'product_id'   => $product_id ,
                                               'component_id' => $component_id });
  foreach my $flag_type (@$flag_types) {
    $flag_type->{'flags'} = Bugzilla::Flag->match({ 'type_id'   => $flag_type->id,
                                                    'attach_id' => $attachment->id });
  }
  $vars->{'flag_types'} = $flag_types;
  $vars->{'any_flags_requesteeble'} = grep($_->is_requesteeble, @$flag_types);
  $vars->{'attachment'} = $attachment;
  $vars->{'bugsummary'} = $bugsummary; 
  $vars->{'attachments'} = $bugattachments;

  print $cgi->header();

  # Generate and return the UI (HTML page) from the appropriate template.
  $template->process("attachment/edit.html.tmpl", $vars)
    || ThrowTemplateError($template->error());
}

# Updates an attachment record. Users with "editbugs" privileges, (or the
# original attachment's submitter) can edit the attachment's description,
# content type, ispatch and isobsolete flags, and statuses, and they can
# also submit a comment that appears in the bug.
# Users cannot edit the content of the attachment itself.
sub update {
    my $user = Bugzilla->user;
    my $dbh = Bugzilla->dbh;

    # Retrieve and validate parameters
    my $attachment = validateID();
    my $bug = new Bugzilla::Bug($attachment->bug_id);
    $attachment->validate_can_edit($bug->product_id);
    validateCanChangeBug($bug->id);
    Bugzilla::Attachment->validate_description(THROW_ERROR);
    Bugzilla::Attachment->validate_is_patch(THROW_ERROR);
    Bugzilla::Attachment->validate_content_type(THROW_ERROR) unless $cgi->param('ispatch');
    $cgi->param('isobsolete', $cgi->param('isobsolete') ? 1 : 0);
    $cgi->param('isprivate', $cgi->param('isprivate') ? 1 : 0);

    # Now make sure the attachment has not been edited since we loaded the page.
    if (defined $cgi->param('delta_ts')
        && $cgi->param('delta_ts') ne $attachment->modification_time)
    {
        ($vars->{'operations'}) =
            Bugzilla::Bug::GetBugActivity($bug->id, $attachment->id, $cgi->param('delta_ts'));

        # If the modification date changed but there is no entry in
        # the activity table, this means someone commented only.
        # In this case, there is no reason to midair.
        if (scalar(@{$vars->{'operations'}})) {
            $cgi->param('delta_ts', $attachment->modification_time);
            $vars->{'attachment'} = $attachment;

            print $cgi->header();
            # Warn the user about the mid-air collision and ask them what to do.
            $template->process("attachment/midair.html.tmpl", $vars)
              || ThrowTemplateError($template->error());
            exit;
        }
    }
    # If the submitter of the attachment is not in the insidergroup,
    # be sure that he cannot overwrite the private bit.
    # This check must be done before calling Bugzilla::Flag*::validate(),
    # because they will look at the private bit when checking permissions.
    # XXX - This is a ugly hack. Ideally, we shouldn't have to look at the
    # old private bit twice (first here, and then below again), but this is
    # the less risky change.
    unless ($user->is_insider) {
        $cgi->param('isprivate', $attachment->isprivate);
    }

    # If the user submitted a comment while editing the attachment,
    # add the comment to the bug. Do this after having validated isprivate!
    if ($cgi->param('comment')) {
        # Prepend a string to the comment to let users know that the comment came
        # from the "edit attachment" screen.
        my $comment = "(From update of attachment " . $attachment->id . ")\n" .
                      $cgi->param('comment');

        $bug->add_comment($comment, { isprivate => $cgi->param('isprivate') });
    }

    # The order of these function calls is important, as Flag::validate
    # assumes User::match_field has ensured that the values in the
    # requestee fields are legitimate user email addresses.
    Bugzilla::User::match_field($cgi, {
        '^requestee(_type)?-(\d+)$' => { 'type' => 'multi' }
    });
    Bugzilla::Flag::validate($bug->id, $attachment->id);

    # Start a transaction in preparation for updating the attachment.
    $dbh->bz_start_transaction();

  # Quote the description and content type for use in the SQL UPDATE statement.
  my $description = $cgi->param('description');
  my $contenttype = $cgi->param('contenttype');
  my $filename = $cgi->param('filename');
  # we can detaint this way thanks to placeholders
  trick_taint($description);
  trick_taint($contenttype);
  trick_taint($filename);

  # Figure out when the changes were made.
  my ($timestamp) = $dbh->selectrow_array("SELECT NOW()");
    
  # Update flags.  We have to do this before committing changes
  # to attachments so that we can delete pending requests if the user
  # is obsoleting this attachment without deleting any requests
  # the user submits at the same time.
  Bugzilla::Flag->process($bug, $attachment, $timestamp, $vars);

  # Update the attachment record in the database.
  $dbh->do("UPDATE  attachments 
            SET     description = ?,
                    mimetype    = ?,
                    filename    = ?,
                    ispatch     = ?,
                    isobsolete  = ?,
                    isprivate   = ?,
                    modification_time = ?
            WHERE   attach_id   = ?",
            undef, ($description, $contenttype, $filename,
            $cgi->param('ispatch'), $cgi->param('isobsolete'), 
            $cgi->param('isprivate'), $timestamp, $attachment->id));

  my $updated_attachment = Bugzilla::Attachment->get($attachment->id);
  # Record changes in the activity table.
  my $sth = $dbh->prepare('INSERT INTO bugs_activity (bug_id, attach_id, who, bug_when,
                                                      fieldid, removed, added)
                           VALUES (?, ?, ?, ?, ?, ?, ?)');

  if ($attachment->description ne $updated_attachment->description) {
    my $fieldid = get_field_id('attachments.description');
    $sth->execute($bug->id, $attachment->id, $user->id, $timestamp, $fieldid,
                  $attachment->description, $updated_attachment->description);
  }
  if ($attachment->contenttype ne $updated_attachment->contenttype) {
    my $fieldid = get_field_id('attachments.mimetype');
    $sth->execute($bug->id, $attachment->id, $user->id, $timestamp, $fieldid,
                  $attachment->contenttype, $updated_attachment->contenttype);
  }
  if ($attachment->filename ne $updated_attachment->filename) {
    my $fieldid = get_field_id('attachments.filename');
    $sth->execute($bug->id, $attachment->id, $user->id, $timestamp, $fieldid,
                  $attachment->filename, $updated_attachment->filename);
  }
  if ($attachment->ispatch != $updated_attachment->ispatch) {
    my $fieldid = get_field_id('attachments.ispatch');
    $sth->execute($bug->id, $attachment->id, $user->id, $timestamp, $fieldid,
                  $attachment->ispatch, $updated_attachment->ispatch);
  }
  if ($attachment->isobsolete != $updated_attachment->isobsolete) {
    my $fieldid = get_field_id('attachments.isobsolete');
    $sth->execute($bug->id, $attachment->id, $user->id, $timestamp, $fieldid,
                  $attachment->isobsolete, $updated_attachment->isobsolete);
  }
  if ($attachment->isprivate != $updated_attachment->isprivate) {
    my $fieldid = get_field_id('attachments.isprivate');
    $sth->execute($bug->id, $attachment->id, $user->id, $timestamp, $fieldid,
                  $attachment->isprivate, $updated_attachment->isprivate);
  }
  
  # Commit the transaction now that we are finished updating the database.
  $dbh->bz_commit_transaction();

  # Commit the comment, if any.
  $bug->update();

  # Define the variables and functions that will be passed to the UI template.
  $vars->{'mailrecipients'} = { 'changer' => Bugzilla->user->login };
  $vars->{'attachment'} = $attachment;
  # We cannot reuse the $bug object as delta_ts has eventually been updated
  # since the object was created.
  $vars->{'bugs'} = [new Bugzilla::Bug($bug->id)];
  $vars->{'header_done'} = 1;
  $vars->{'valid_keywords'} = [map($_->name, Bugzilla::Keyword->get_all)];
  $vars->{'use_keywords'} = 1 if Bugzilla::Keyword::keyword_count();

  print $cgi->header();

  # Generate and return the UI (HTML page) from the appropriate template.
  $template->process("attachment/updated.html.tmpl", $vars)
    || ThrowTemplateError($template->error());
}

# Only administrators can delete attachments.
sub delete_attachment {
    my $user = Bugzilla->login(LOGIN_REQUIRED);
    my $dbh = Bugzilla->dbh;

    print $cgi->header();

    $user->in_group('admin')
      || ThrowUserError('auth_failure', {group  => 'admin',
                                         action => 'delete',
                                         object => 'attachment'});

    Bugzilla->params->{'allow_attachment_deletion'}
      || ThrowUserError('attachment_deletion_disabled');

    # Make sure the administrator is allowed to edit this attachment.
    my $attachment = validateID();
    validateCanChangeBug($attachment->bug_id);

    $attachment->datasize || ThrowUserError('attachment_removed');

    # We don't want to let a malicious URL accidentally delete an attachment.
    my $token = trim($cgi->param('token'));
    if ($token) {
        my ($creator_id, $date, $event) = Bugzilla::Token::GetTokenData($token);
        unless ($creator_id
                  && ($creator_id == $user->id)
                  && ($event eq 'attachment' . $attachment->id))
        {
            # The token is invalid.
            ThrowUserError('token_does_not_exist');
        }

        my $bug = new Bugzilla::Bug($attachment->bug_id);

        # The token is valid. Delete the content of the attachment.
        my $msg;
        $vars->{'attachment'} = $attachment;
        $vars->{'date'} = $date;
        $vars->{'reason'} = clean_text($cgi->param('reason') || '');
        $vars->{'mailrecipients'} = { 'changer' => $user->login };

        $template->process("attachment/delete_reason.txt.tmpl", $vars, \$msg)
          || ThrowTemplateError($template->error());

        # Paste the reason provided by the admin into a comment.
        $bug->add_comment($msg);

        # If the attachment is stored locally, remove it.
        if (-e $attachment->_get_local_filename) {
            unlink $attachment->_get_local_filename;
        }
        $attachment->remove_from_db();

        # Now delete the token.
        delete_token($token);

        # Insert the comment.
        $bug->update();

        # Required to display the bug the deleted attachment belongs to.
        $vars->{'bugs'} = [$bug];
        $vars->{'header_done'} = 1;
        $vars->{'valid_keywords'} = [map($_->name, Bugzilla::Keyword->get_all)];
        $vars->{'use_keywords'} = 1 if Bugzilla::Keyword::keyword_count();

        $template->process("attachment/updated.html.tmpl", $vars)
          || ThrowTemplateError($template->error());
    }
    else {
        # Create a token.
        $token = issue_session_token('attachment' . $attachment->id);

        $vars->{'a'} = $attachment;
        $vars->{'token'} = $token;

        $template->process("attachment/confirm-delete.html.tmpl", $vars)
          || ThrowTemplateError($template->error());
    }
}
