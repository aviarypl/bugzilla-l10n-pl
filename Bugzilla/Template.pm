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
#                 Jacob Steenhagen <jake@bugzilla.org>
#                 Bradley Baetz <bbaetz@student.usyd.edu.au>
#                 Christopher Aillon <christopher@aillon.com>
#                 Tobias Burnus <burnus@net-b.de>
#                 Myk Melez <myk@mozilla.org>
#                 Max Kanat-Alexander <mkanat@bugzilla.org>
#                 Frédéric Buclin <LpSolit@gmail.com>
#                 Greg Hendricks <ghendricks@novell.com>


package Bugzilla::Template;

use strict;

use Bugzilla::Constants;
use Bugzilla::Config qw(:DEFAULT $templatedir $datadir $project);
use Bugzilla::Util;
use Bugzilla::User;
use Bugzilla::Error;
use MIME::Base64;

# for time2str - replace by TT Date plugin??
use Date::Format ();

use base qw(Template);

# Convert the constants in the Bugzilla::Constants module into a hash we can
# pass to the template object for reflection into its "constants" namespace
# (which is like its "variables" namespace, but for constants).  To do so, we
# traverse the arrays of exported and exportable symbols, pulling out functions
# (which is how Perl implements constants) and ignoring the rest (which, if
# Constants.pm exports only constants, as it should, will be nothing else).
use Bugzilla::Constants ();
my %constants;
foreach my $constant (@Bugzilla::Constants::EXPORT,
                      @Bugzilla::Constants::EXPORT_OK)
{
    if (defined &{$Bugzilla::Constants::{$constant}}) {
        # Constants can be lists, and we can't know whether we're getting
        # a scalar or a list in advance, since they come to us as the return
        # value of a function call, so we have to retrieve them all in list
        # context into anonymous arrays, then extract the scalar ones (i.e.
        # the ones whose arrays contain a single element) from their arrays.
        $constants{$constant} = [&{$Bugzilla::Constants::{$constant}}];
        if (scalar(@{$constants{$constant}}) == 1) {
            $constants{$constant} = @{$constants{$constant}}[0];
        }
    }
}

# XXX - mod_perl
my $template_include_path;

# Make an ordered list out of a HTTP Accept-Language header see RFC 2616, 14.4
# We ignore '*' and <language-range>;q=0
# For languages with the same priority q the order remains unchanged.
sub sortAcceptLanguage {
    sub sortQvalue { $b->{'qvalue'} <=> $a->{'qvalue'} }
    my $accept_language = $_[0];

    # clean up string.
    $accept_language =~ s/[^A-Za-z;q=0-9\.\-,]//g;
    my @qlanguages;
    my @languages;
    foreach(split /,/, $accept_language) {
        if (m/([A-Za-z\-]+)(?:;q=(\d(?:\.\d+)))?/) {
            my $lang   = $1;
            my $qvalue = $2;
            $qvalue = 1 if not defined $qvalue;
            next if $qvalue == 0;
            $qvalue = 1 if $qvalue > 1;
            push(@qlanguages, {'qvalue' => $qvalue, 'language' => $lang});
        }
    }

    return map($_->{'language'}, (sort sortQvalue @qlanguages));
}

# Returns the path to the templates based on the Accept-Language
# settings of the user and of the available languages
# If no Accept-Language is present it uses the defined default
sub getTemplateIncludePath {
    # Return cached value if available

    # XXXX - mod_perl!
    if ($template_include_path) {
        return $template_include_path;
    }
    my $languages = trim(Param('languages'));
    if (not ($languages =~ /,/)) {
       if ($project) {
           $template_include_path = [
               "$templatedir/$languages/$project",
               "$templatedir/$languages/custom",
               "$templatedir/$languages/extension",
               "$templatedir/$languages/default"
           ];
       } else {
           $template_include_path = [
               "$templatedir/$languages/custom",
               "$templatedir/$languages/extension",
               "$templatedir/$languages/default"
           ];
       }
        return $template_include_path;
    }
    my @languages       = sortAcceptLanguage($languages);
    my @accept_language = sortAcceptLanguage($ENV{'HTTP_ACCEPT_LANGUAGE'} || "" );
    my @usedlanguages;
    foreach my $lang (@accept_language) {
        # Per RFC 1766 and RFC 2616 any language tag matches also its 
        # primary tag. That is 'en' (accept lanuage)  matches 'en-us',
        # 'en-uk' etc. but not the otherway round. (This is unfortunally
        # not very clearly stated in those RFC; see comment just over 14.5
        # in http://www.w3.org/Protocols/rfc2616/rfc2616-sec14.html#sec14.4)
        if(my @found = grep /^\Q$lang\E(-.+)?$/i, @languages) {
            push (@usedlanguages, @found);
        }
    }
    push(@usedlanguages, Param('defaultlanguage'));
    if ($project) {
        $template_include_path = [
           map((
               "$templatedir/$_/$project",
               "$templatedir/$_/custom",
               "$templatedir/$_/extension",
               "$templatedir/$_/default"
               ), @usedlanguages
            )
        ];
    } else {
        $template_include_path = [
           map((
               "$templatedir/$_/custom",
               "$templatedir/$_/extension",
               "$templatedir/$_/default"
               ), @usedlanguages
            )
        ];
    }
    return $template_include_path;
}

sub put_header {
    my $self = shift;
    my $vars = {};
    ($vars->{'title'}, $vars->{'h1'}, $vars->{'h2'}) = (@_);
     
    $self->process("global/header.html.tmpl", $vars)
      || ThrowTemplateError($self->error());
    $vars->{'header_done'} = 1;
}

sub put_footer {
    my $self = shift;
    $self->process("global/footer.html.tmpl")
      || ThrowTemplateError($self->error());
}

sub get_format {
    my $self = shift;
    my ($template, $format, $ctype) = @_;

    $ctype ||= 'html';
    $format ||= '';

    # Security - allow letters and a hyphen only
    $ctype =~ s/[^a-zA-Z\-]//g;
    $format =~ s/[^a-zA-Z\-]//g;
    trick_taint($ctype);
    trick_taint($format);

    $template .= ($format ? "-$format" : "");
    $template .= ".$ctype.tmpl";

    # Now check that the template actually exists. We only want to check
    # if the template exists; any other errors (eg parse errors) will
    # end up being detected later.
    eval {
        $self->context->template($template);
    };
    # This parsing may seem fragile, but its OK:
    # http://lists.template-toolkit.org/pipermail/templates/2003-March/004370.html
    # Even if it is wrong, any sort of error is going to cause a failure
    # eventually, so the only issue would be an incorrect error message
    if ($@ && $@->info =~ /: not found$/) {
        ThrowUserError('format_not_found', {'format' => $format,
                                            'ctype'  => $ctype});
    }

    # Else, just return the info
    return
    {
        'template'    => $template,
        'extension'   => $ctype,
        'ctype'       => Bugzilla::Constants::contenttypes->{$ctype}
    };
}

###############################################################################
# Templatization Code

# The Template Toolkit throws an error if a loop iterates >1000 times.
# We want to raise that limit.
# NOTE: If you change this number, you MUST RE-RUN checksetup.pl!!!
# If you do not re-run checksetup.pl, the change you make will not apply
$Template::Directive::WHILE_MAX = 1000000;

# Use the Toolkit Template's Stash module to add utility pseudo-methods
# to template variables.
use Template::Stash;

# Add "contains***" methods to list variables that search for one or more 
# items in a list and return boolean values representing whether or not 
# one/all/any item(s) were found.
$Template::Stash::LIST_OPS->{ contains } =
  sub {
      my ($list, $item) = @_;
      return grep($_ eq $item, @$list);
  };

$Template::Stash::LIST_OPS->{ containsany } =
  sub {
      my ($list, $items) = @_;
      foreach my $item (@$items) { 
          return 1 if grep($_ eq $item, @$list);
      }
      return 0;
  };

# Allow us to still get the scalar if we use the list operation ".0" on it,
# as we often do for defaults in query.cgi and other places.
$Template::Stash::SCALAR_OPS->{ 0 } = 
  sub {
      return $_[0];
  };

# Add a "substr" method to the Template Toolkit's "scalar" object
# that returns a substring of a string.
$Template::Stash::SCALAR_OPS->{ substr } = 
  sub {
      my ($scalar, $offset, $length) = @_;
      return substr($scalar, $offset, $length);
  };

# Add a "truncate" method to the Template Toolkit's "scalar" object
# that truncates a string to a certain length.
$Template::Stash::SCALAR_OPS->{ truncate } = 
  sub {
      my ($string, $length, $ellipsis) = @_;
      $ellipsis ||= "";
      
      return $string if !$length || length($string) <= $length;
      
      my $strlen = $length - length($ellipsis);
      my $newstr = substr($string, 0, $strlen) . $ellipsis;
      return $newstr;
  };

# Create the template object that processes templates and specify
# configuration parameters that apply to all templates.

###############################################################################

# Construct the Template object

# Note that all of the failure cases here can't use templateable errors,
# since we won't have a template to use...

sub create {
    my $class = shift;
    my %opts = @_;

    # checksetup.pl will call us once for any template/lang directory.
    # We need a possibility to reset the cache, so that no files from
    # the previous language pollute the action.
    if ($opts{'clean_cache'}) {
        $template_include_path = undef;
    }

    # IMPORTANT - If you make any configuration changes here, make sure to
    # make them in t/004.template.t and checksetup.pl.

    return $class->new({
        # Colon-separated list of directories containing templates.
        INCLUDE_PATH => [\&getTemplateIncludePath],

        # Remove white-space before template directives (PRE_CHOMP) and at the
        # beginning and end of templates and template blocks (TRIM) for better
        # looking, more compact content.  Use the plus sign at the beginning
        # of directives to maintain white space (i.e. [%+ DIRECTIVE %]).
        PRE_CHOMP => 1,
        TRIM => 1,

        COMPILE_DIR => "$datadir/template",

        # Initialize templates (f.e. by loading plugins like Hook).
        PRE_PROCESS => "global/initialize.none.tmpl",

        # Functions for processing text within templates in various ways.
        # IMPORTANT!  When adding a filter here that does not override a
        # built-in filter, please also add a stub filter to t/004template.t.
        FILTERS => {

            # Render text in required style.

            inactive => [
                sub {
                    my($context, $isinactive) = @_;
                    return sub {
                        return $isinactive ? '<span class="bz_inactive">'.$_[0].'</span>' : $_[0];
                    }
                }, 1
            ],

            closed => [
                sub {
                    my($context, $isclosed) = @_;
                    return sub {
                        return $isclosed ? '<span class="bz_closed">'.$_[0].'</span>' : $_[0];
                    }
                }, 1
            ],

            obsolete => [
                sub {
                    my($context, $isobsolete) = @_;
                    return sub {
                        return $isobsolete ? '<span class="bz_obsolete">'.$_[0].'</span>' : $_[0];
                    }
                }, 1
            ],

            # Returns the text with backslashes, single/double quotes,
            # and newlines/carriage returns escaped for use in JS strings.
            js => sub {
                my ($var) = @_;
                $var =~ s/([\\\'\"\/])/\\$1/g;
                $var =~ s/\n/\\n/g;
                $var =~ s/\r/\\r/g;
                $var =~ s/\@/\\x40/g; # anti-spam for email addresses
                return $var;
            },
            
            # Converts data to base64
            base64 => sub {
                my ($data) = @_;
                return encode_base64($data);
            },
            
            # HTML collapses newlines in element attributes to a single space,
            # so form elements which may have whitespace (ie comments) need
            # to be encoded using &#013;
            # See bugs 4928, 22983 and 32000 for more details
            html_linebreak => sub {
                my ($var) = @_;
                $var =~ s/\r\n/\&#013;/g;
                $var =~ s/\n\r/\&#013;/g;
                $var =~ s/\r/\&#013;/g;
                $var =~ s/\n/\&#013;/g;
                return $var;
            },

            # Prevents line break on hyphens and whitespaces.
            no_break => sub {
                my ($var) = @_;
                $var =~ s/ /\&nbsp;/g;
                $var =~ s/-/\&#8209;/g;
                return $var;
            },

            xml => \&Bugzilla::Util::xml_quote ,

            # This filter escapes characters in a variable or value string for
            # use in a query string.  It escapes all characters NOT in the
            # regex set: [a-zA-Z0-9_\-.].  The 'uri' filter should be used for
            # a full URL that may have characters that need encoding.
            url_quote => \&Bugzilla::Util::url_quote ,

            # This filter is similar to url_quote but used a \ instead of a %
            # as prefix. In addition it replaces a ' ' by a '_'.
            css_class_quote => \&Bugzilla::Util::css_class_quote ,

            quoteUrls => [ sub {
                               my ($context, $bug) = @_;
                               return sub {
                                   my $text = shift;
                                   return &::quoteUrls($text, $bug);
                               };
                           },
                           1
                         ],

            bug_link => [ sub {
                              my ($context, $bug) = @_;
                              return sub {
                                  my $text = shift;
                                  return &::GetBugLink($bug, $text);
                              };
                          },
                          1
                        ],

            # In CSV, quotes are doubled, and any value containing a quote or a
            # comma is enclosed in quotes.
            csv => sub
            {
                my ($var) = @_;
                $var =~ s/\"/\"\"/g;
                if ($var !~ /^-?(\d+\.)?\d*$/) {
                    $var = "\"$var\"";
                }
                return $var;
            } ,

            # Format a filesize in bytes to a human readable value
            unitconvert => sub
            {
                my ($data) = @_;
                my $retval = "";
                my %units = (
                    'KB' => 1024,
                    'MB' => 1024 * 1024,
                    'GB' => 1024 * 1024 * 1024,
                );

                if ($data < 1024) {
                    return "$data bytes";
                } 
                else {
                    my $u;
                    foreach $u ('GB', 'MB', 'KB') {
                        if ($data >= $units{$u}) {
                            return sprintf("%.2f %s", $data/$units{$u}, $u);
                        }
                    }
                }
            },

            # Format a time for display (more info in Bugzilla::Util)
            time => \&Bugzilla::Util::format_time,

            # Bug 120030: Override html filter to obscure the '@' in user
            #             visible strings.
            # Bug 319331: Handle BiDi disruptions.
            html => sub {
                my ($var) = Template::Filters::html_filter(@_);
                # Obscure '@'.
                $var =~ s/\@/\&#64;/g;
                if (Param('utf8')) {
                    # Remove the following characters because they're
                    # influencing BiDi:
                    # --------------------------------------------------------
                    # |Code  |Name                      |UTF-8 representation|
                    # |------|--------------------------|--------------------|
                    # |U+202a|Left-To-Right Embedding   |0xe2 0x80 0xaa      |
                    # |U+202b|Right-To-Left Embedding   |0xe2 0x80 0xab      |
                    # |U+202c|Pop Directional Formatting|0xe2 0x80 0xac      |
                    # |U+202d|Left-To-Right Override    |0xe2 0x80 0xad      |
                    # |U+202e|Right-To-Left Override    |0xe2 0x80 0xae      |
                    # --------------------------------------------------------
                    #
                    # The following are characters influencing BiDi, too, but
                    # they can be spared from filtering because they don't
                    # influence more than one character right or left:
                    # --------------------------------------------------------
                    # |Code  |Name                      |UTF-8 representation|
                    # |------|--------------------------|--------------------|
                    # |U+200e|Left-To-Right Mark        |0xe2 0x80 0x8e      |
                    # |U+200f|Right-To-Left Mark        |0xe2 0x80 0x8f      |
                    # --------------------------------------------------------
                    #
                    # Do the replacing in a loop so that we don't get tricked
                    # by stuff like 0xe2 0xe2 0x80 0xae 0x80 0xae.
                    while ($var =~ s/\xe2\x80(\xaa|\xab|\xac|\xad|\xae)//g) {
                    }
                }
                return $var;
            },
            
            # iCalendar contentline filter
            ics => [ sub {
                         my ($context, @args) = @_;
                         return sub {
                             my ($var) = shift;
                             my ($par) = shift @args;
                             my ($output) = "";

                             $var =~ s/[\r\n]/ /g;
                             $var =~ s/([;\\\"])/\\$1/g;

                             if ($par) {
                                 $output = sprintf("%s:%s", $par, $var);
                             } else {
                                 $output = $var;
                             }
                             
                             $output =~ s/(.{75,75})/$1\n /g;

                             return $output;
                         };
                     },
                     1
                     ],

            # Wrap a displayed comment to the appropriate length
            wrap_comment => \&Bugzilla::Util::wrap_comment,

            # We force filtering of every variable in key security-critical
            # places; we have a none filter for people to use when they 
            # really, really don't want a variable to be changed.
            none => sub { return $_[0]; } ,
        },

        PLUGIN_BASE => 'Bugzilla::Template::Plugin',

        CONSTANTS => \%constants,

        # Default variables for all templates
        VARIABLES => {
            # Function for retrieving global parameters.
            'Param' => \&Bugzilla::Config::Param,

            # Function to create date strings
            'time2str' => \&Date::Format::time2str,

            # Generic linear search function
            'lsearch' => \&Bugzilla::Util::lsearch,

            # Currently logged in user, if any
            # If an sudo session is in progress, this is the user we're faking
            'user' => sub { return Bugzilla->user; },

            # If an sudo session is in progress, this is the user who
            # started the session.
            'sudoer' => sub { return Bugzilla->sudoer; },

            # UserInGroup. Deprecated - use the user.* functions instead
            'UserInGroup' => \&Bugzilla::User::UserInGroup,

            # SendBugMail - sends mail about a bug, using Bugzilla::BugMail.pm
            'SendBugMail' => sub {
                my ($id, $mailrecipients) = (@_);
                require Bugzilla::BugMail;
                Bugzilla::BugMail::Send($id, $mailrecipients);
            },

            # Bugzilla version
            # This could be made a ref, or even a CONSTANT with TT2.08
            'VERSION' => $Bugzilla::Config::VERSION ,
        },

   }) || die("Template creation failed: " . $class->error());
}

1;

__END__

=head1 NAME

Bugzilla::Template - Wrapper around the Template Toolkit C<Template> object

=head1 SYNOPSIS

  my $template = Bugzilla::Template->create;

  $template->put_header($title, $h1, $h2);
  $template->put_footer();

  my $format = $template->get_format("foo/bar",
                                     scalar($cgi->param('format')),
                                     scalar($cgi->param('ctype')));

=head1 DESCRIPTION

This is basically a wrapper so that the correct arguments get passed into
the C<Template> constructor.

It should not be used directly by scripts or modules - instead, use
C<Bugzilla-E<gt>instance-E<gt>template> to get an already created module.

=head1 METHODS

=over

=item C<put_header($title, $h1, $h2)>

 Description: Display the header of the page for non yet templatized .cgi files.

 Params:      $title - Page title.
              $h1    - Main page header.
              $h2    - Page subheader.

 Returns:     nothing

=item C<put_footer()>

 Description: Display the footer of the page for non yet templatized .cgi files.

 Params:      none

 Returns:     nothing

=item C<get_format($file, $format, $ctype)>

 Description: Construct a format object from URL parameters.

 Params:      $file   - Name of the template to display.
              $format - When the template exists under several formats
                        (e.g. table or graph), specify the one to choose.
              $ctype  - Content type, see Bugzilla::Constants::contenttypes.

 Returns:     A format object.

=back

=head1 SEE ALSO

L<Bugzilla>, L<Template>
