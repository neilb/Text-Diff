package Text::Diff;

use 5.006;
use strict;
use warnings;
use Carp            qw/ croak confess /;
use Exporter        ();
use Algorithm::Diff ();
use Term::ANSIColor 2.02 qw/ :constants color colorvalid /;

our $VERSION = '1.46';
our @ISA     = qw/ Exporter /;
our @EXPORT  = qw/ diff /;

## Hunks are made of ops.  An op is the starting index for each
## sequence and the opcode:
use constant A       => 0;   # Array index before match/discard
use constant B       => 1;
use constant OPCODE  => 2;   # "-", " ", "+"
use constant FLAG    => 3;   # What to display if not OPCODE "!"

my %internal_styles = (
    Unified  => undef,
    Context  => undef,
    OldStyle => undef,
    Table    => undef,   ## "internal", but in another module
);

my %hunks = (
    header       => undef,
    line_number  => undef,
    delete_line  => undef,
    add_line     => undef,
    same_line    => undef,
    context_sep  => undef,
    oldstyle_sep => undef,
    table_frame  => undef,
);

my %default_colors = (
    header      => BOLD,
    line_number => CYAN,
    delete_line => RED,
    add_line    => GREEN,
    reset       => RESET,
);

sub diff {
    my @seqs    = ( shift, shift );
    my $options = shift || {};

    for my $i ( 0 .. 1 ) {
        my $seq = $seqs[$i];
        my $type = ref $seq;

        while ( $type eq "CODE" ) {
            $seqs[$i] = $seq = $seq->( $options );
            $type = ref $seq;
        }

        my $AorB = !$i ? "A" : "B";

        if ( $type eq "ARRAY" ) {
            ## This is most efficient :)
            $options->{"OFFSET_$AorB"} = 0
                unless defined $options->{"OFFSET_$AorB"};
        }
        elsif ( $type eq "SCALAR" ) {
            $seqs[$i] = [split( /^/m, $$seq )];
            $options->{"OFFSET_$AorB"} = 1
                unless defined $options->{"OFFSET_$AorB"};
        }
        elsif ( ! $type ) {
            $options->{"OFFSET_$AorB"} = 1
                unless defined $options->{"OFFSET_$AorB"};
            $options->{"FILENAME_$AorB"} = $seq
                unless defined $options->{"FILENAME_$AorB"};
            $options->{"MTIME_$AorB"} = (stat($seq))[9]
                unless defined $options->{"MTIME_$AorB"};

            local $/ = "\n";
            open my $fh, "<", $seq or croak "Failed to open $seq: $!";
            $seqs[$i] = [<$fh>];
            close $fh;
        }
        elsif ( $type eq "GLOB" || UNIVERSAL::isa( $seq, "IO::Handle" ) ) {
            $options->{"OFFSET_$AorB"} = 1
                unless defined $options->{"OFFSET_$AorB"};
            local $/ = "\n";
            $seqs[$i] = [<$seq>];
        }
        else {
            confess "Can't handle input of type ", ref;
        }
    }

    ## Config vars
    my $output;
    my $output_handler = $options->{OUTPUT};
    my $type = ref $output_handler;
    my $is_tty;
    if ( ! defined $output_handler ) {
        $output = "";
        $output_handler = sub { $output .= shift };
    }
    elsif ( $type eq "CODE" ) {
        ## No problems, mate.
    }
    elsif ( $type eq "SCALAR" ) {
        my $out_ref = $output_handler;
        $output_handler = sub { $$out_ref .= shift };
    }
    elsif ( $type eq "ARRAY" ) {
        my $out_ref = $output_handler;
        $output_handler = sub { push @$out_ref, shift };
    }
    elsif ( $type eq "GLOB" || UNIVERSAL::isa $output_handler, "IO::Handle" ) {
        $is_tty = -t $output_handler ? 1 : 0;

        my $output_handle = $output_handler;
        $output_handler = sub { print $output_handle shift };
    }
    else {
        croak "Unrecognized output type: $type";
    }

    my $style  = $options->{STYLE};
    $style = "Unified" unless defined $options->{STYLE};
    $style = "Text::Diff::$style" if exists $internal_styles{$style};

    if ( ! $style->can( "hunk" ) ) {
        eval "require $style; 1" or die $@;
    }

    $style = $style->new if ! ref $style && $style->can( "new" );

    my $ctx_lines = $options->{CONTEXT};
    $ctx_lines = 3 unless defined $ctx_lines;
    $ctx_lines = 0 if $style->isa( "Text::Diff::OldStyle" );

    my @keygen_args = $options->{KEYGEN_ARGS}
        ? @{$options->{KEYGEN_ARGS}}
        : ();

    $options->{COLOR} = 0 unless defined $options->{COLOR};

    if ( $options->{COLOR} ne "always" ) {
        $options->{COLOR} = 0 if defined $is_tty && ! $is_tty || ! -t STDOUT;
    }

    $options->{PALETTE} = $options->{COLOR} ? _get_colors($options->{PALETTE})
                                            : undef;

    ## State vars
    my $diffs = 0; ## Number of discards this hunk
    my $ctx   = 0; ## Number of " " (ctx_lines) ops pushed after last diff.
    my @ops;       ## ops (" ", +, -) in this hunk
    my $hunks = 0; ## Number of hunks

    my $emit_ops = sub {
        $output_handler->( $style->file_header( @seqs,     $options ) )
            unless $hunks++;
        $output_handler->( $style->hunk_header( @seqs, @_, $options ) );
        $output_handler->( $style->hunk       ( @seqs, @_, $options ) );
        $output_handler->( $style->hunk_footer( @seqs, @_, $options ) );
    };

    ## We keep 2*ctx_lines so that if a diff occurs
    ## at 2*ctx_lines we continue to grow the hunk instead
    ## of emitting diffs and context as we go. We
    ## need to know the total length of both of the two
    ## subsequences so the line count can be printed in the
    ## header.
    my $dis_a = sub { push @ops, [@_[0,1],"-"]; ++$diffs; $ctx = 0 };
    my $dis_b = sub { push @ops, [@_[0,1],"+"]; ++$diffs; $ctx = 0 };

    Algorithm::Diff::traverse_sequences(
        @seqs,
        {
            MATCH => sub {
                push @ops, [@_[0,1]," "];

                if ( $diffs && ++$ctx > $ctx_lines * 2 ) {
                    $emit_ops->( [ splice @ops, 0, $#ops - $ctx_lines ] );
                    $ctx = $diffs = 0;
                }

                ## throw away context lines that aren't needed any more
                shift @ops if ! $diffs && @ops > $ctx_lines;
            },
            DISCARD_A => $dis_a,
            DISCARD_B => $dis_b,
        },
        $options->{KEYGEN},  # pass in user arguments for key gen function
        @keygen_args,
    );

    if ( $diffs ) {
        $#ops -= $ctx - $ctx_lines if $ctx > $ctx_lines;
        $emit_ops->( \@ops );
    }

    $output_handler->( $style->file_footer( @seqs, $options ) ) if $hunks;

    return defined $output ? $output : $hunks;
}

sub _header {
    my ( $h ) = @_;
    my ( $p1, $fn1, $t1, $p2, $fn2, $t2 ) = @{$h}{
        "FILENAME_PREFIX_A",
        "FILENAME_A",
        "MTIME_A",
        "FILENAME_PREFIX_B",
        "FILENAME_B",
        "MTIME_B"
    };

    ## remember to change Text::Diff::Table if this logic is tweaked.
    return "" unless defined $fn1 && defined $fn2;

    $t1 = defined $t1 ? "\t" . localtime $t1 : ();
    $t2 = defined $t2 ? "\t" . localtime $t2 : ();

    my $header = _is_color( $h->{PALETTE}{header} );
    my $reset  = _is_color( $h->{PALETTE}{reset} );

    return join( "",
        $header, $p1, " ", $fn1, $t1, $reset, "\n",
        $header, $p2, " ", $fn2, $t2, $reset, "\n",
    );
}

## _range encapsulates the building of, well, ranges.  Turns out there are
## a few nuances.
sub _range {
    my ( $ops, $a_or_b, $format ) = @_;

    my $start = $ops->[ 0]->[$a_or_b];
    my $after = $ops->[-1]->[$a_or_b];

    ## The sequence indexes in the lines are from *before* the OPCODE is
    ## executed, so we bump the last index up unless the OP indicates
    ## it didn't change.
    ++$after
        unless $ops->[-1]->[OPCODE] eq ( $a_or_b == A ? "+" : "-" );

    ## convert from 0..n index to 1..(n+1) line number.  The unless modifier
    ## handles diffs with no context, where only one file is affected.  In this
    ## case $start == $after indicates an empty range, and the $start must
    ## not be incremented.
    my $empty_range = $start == $after;
    ++$start unless $empty_range;

    return
        $start == $after
            ? $format eq "unified" && $empty_range
                ? "$start,0"
                : $start
            : $format eq "unified"
                ? "$start,".($after-$start+1)
                : "$start,$after";
}

sub _op_to_line {
    my ( $seqs, $op, $a_or_b, $op_prefixes, $options ) = @_;

    my $opcode = $op->[OPCODE];
    return () unless defined $op_prefixes->{$opcode};

    my $op_sym = defined $op->[FLAG] ? $op->[FLAG] : $opcode;
    $op_sym = $op_prefixes->{$op_sym};
    return () unless defined $op_sym;

    $a_or_b = $op->[OPCODE] ne "+" ? 0 : 1 unless defined $a_or_b;

    my $seq_line = $seqs->[$a_or_b][$op->[$a_or_b]];

    my $colors = $options->{PALETTE};
    my $color  = "";

    if ( defined $colors && keys %{$colors} ) {
        ## Do not colorize Unified " " OPCODE lines, unless its color option is
        ## defined.
        if ( $op_sym ne " " ) {
            $color = $a_or_b eq A ? $colors->{delete_line}
                                  : $colors->{add_line};
        }
        elsif ( $op_sym eq " " && defined $colors->{same_line} ) {
            $color = $colors->{same_line};
        }
    }

    # Append a reset color before a line break or end of string.
    $seq_line =~ s/(\r?\n$|\z)/$colors->{reset}$1/ if $color ne "";

    my @line = ( $color . $op_sym, $seq_line );

    unless ( $line[1] =~ /\r?\n$/ ) {
        $line[1] .= "\n\\ No newline at end of file\n";
    }

    return @line;
}

sub _get_colors
{
    my ( $palette ) = @_;

    my %colors = %default_colors;

    if ( defined $palette && ref $palette eq "HASH" && keys %{$palette} ) {
        for my $section ( keys %{$palette} ) {
            next unless exists $hunks{$section};

            my $ansi = $palette->{$section};

            # Silently ignore invalid Term::ANSIColor colors.
            $colors{$section} = color( $ansi ) if colorvalid( $ansi );
        }
    }

    return \%colors;
}

sub _is_color {
    my ( $ansi, $reset ) = @_;

    return $reset if defined $ansi && defined $reset;
    return defined $ansi ? $ansi : "";
}

SCOPE: {
    package Text::Diff::Base;

    sub new         {
        my $proto = shift;
        return bless { @_ }, ref $proto || $proto;
    }

    sub file_header { return "" }

    sub hunk_header { return "" }

    sub hunk        { return "" }

    sub hunk_footer { return "" }

    sub file_footer { return "" }
}

@Text::Diff::Unified::ISA = qw( Text::Diff::Base );

sub Text::Diff::Unified::file_header {
    shift; ## No instance data
    my $options = pop;

    _header(
        { FILENAME_PREFIX_A => "---", FILENAME_PREFIX_B => "+++", %$options }
    );
}

sub Text::Diff::Unified::hunk_header {
    shift; ## No instance data
    my $options = pop;
    my $ops     = pop;

    return join( "",
        _is_color( $options->{PALETTE}{line_number} ),
        "@@ -",
        _range( $ops, A, "unified" ),
        " +",
        _range( $ops, B, "unified" ),
        " @@",
        _is_color( $options->{PALETTE}{reset} ),
        "\n",
    );
}

sub Text::Diff::Unified::hunk {
    shift; ## No instance data
    my $options = pop;
    my $ops     = pop;

    my $prefixes = { "+" => "+", " " => " ", "-" => "-" };

    return join( "",
        map _op_to_line( \@_, $_, undef, $prefixes, $options ),
        @$ops,
    );
}

@Text::Diff::Context::ISA = qw( Text::Diff::Base );

sub Text::Diff::Context::file_header {
    _header(
        { FILENAME_PREFIX_A => "***", FILENAME_PREFIX_B => "---", %{$_[-1]} }
    );
}

sub Text::Diff::Context::hunk_header {
    shift; ## No instance data
    my $options = pop;

    my $colors = $options->{PALETTE};

    return join( "",
        _is_color( $colors->{context_sep} ),
        "***************",
        _is_color( $colors->{context_sep}, $colors->{reset} ),
        "\n",
    );
}

sub Text::Diff::Context::hunk {
    shift; ## No instance data
    my $options = pop;
    my $ops     = pop;
    ## Leave the sequences in @_[0,1]

    my $a_range = _range( $ops, A, "" );
    my $b_range = _range( $ops, B, "" );

    ## Sigh.  Gotta make sure that differences that aren't adds/deletions
    ## get prefixed with "!", and that the old opcodes are removed.
    my $after;
    for ( my $start = 0; $start <= $#$ops; $start = $after ) {
        ## Scan until next difference
        $after = $start + 1;
        my $opcode = $ops->[$start]->[OPCODE];
        next if $opcode eq " ";

        my $bang_it;
        while ( $after <= $#$ops && $ops->[$after]->[OPCODE] ne " " ) {
            $bang_it ||= $ops->[$after]->[OPCODE] ne $opcode;
            ++$after;
        }

        if ( $bang_it ) {
            for my $i ( $start..($after-1) ) {
                $ops->[$i]->[FLAG] = "!";
            }
        }
    }

    my $line_num = _is_color( $options->{PALETTE}{line_number} );
    my $reset    = _is_color( $options->{PALETTE}{reset} );

    my $b_prefixes = { "+" => "+ ",  " " => "  ", "-" => undef, "!" => "! " };
    my $a_prefixes = { "+" => undef, " " => "  ", "-" => "- ",  "!" => "! " };

    return join( "",
        $line_num . "*** ", $a_range, " ****" . $reset . "\n",
        map( _op_to_line( \@_, $_, A, $a_prefixes, $options ), @$ops ),
        $line_num . "--- ", $b_range, " ----" . $reset . "\n",
        map( _op_to_line( \@_, $_, B, $b_prefixes, $options ), @$ops ),
    );
}

@Text::Diff::OldStyle::ISA = qw( Text::Diff::Base );

sub _op {
    my $ops = shift;
    my $op = $ops->[0]->[OPCODE];
    $op = "c" if grep $_->[OPCODE] ne $op, @$ops;
    $op = "a" if $op eq "+";
    $op = "d" if $op eq "-";
    return $op;
}

sub Text::Diff::OldStyle::hunk_header {
    shift; ## No instance data
    my $options = pop;
    my $ops     = pop;

    my $op = _op $ops;

    return join( "",
        _is_color( $options->{PALETTE}{line_number} ),
        _range( $ops, A, "" ),
        $op,
        _range( $ops, B, "" ),
        _is_color( $options->{PALETTE}{reset} ),
        "\n",
    );
}

sub Text::Diff::OldStyle::hunk {
    shift; ## No instance data
    my $options = pop;
    my $ops     = pop;
    ## Leave the sequences in @_[0,1]

    my $a_prefixes = { "+" => undef,  " " => undef, "-" => "< "  };
    my $b_prefixes = { "+" => "> ",   " " => undef, "-" => undef };

    my $op = _op $ops;

    my $colors = $options->{PALETTE};
    my $sep    = _is_color( $colors->{oldstyle_sep} );
    my $reset  = _is_color( $colors->{oldstyle_sep}, $colors->{reset} );

    return join( "",
        map( _op_to_line( \@_, $_, A, $a_prefixes, $options ), @$ops ),
        $op eq "c" ? $sep . "---" . $reset . "\n" : (),
        map( _op_to_line( \@_, $_, B, $b_prefixes, $options ), @$ops ),
    );
}

1;

__END__

=head1 NAME

Text::Diff - Perform diffs on files and record sets

=head1 SYNOPSIS

    use Text::Diff;

    ## Mix and match filenames, strings, file handles, producer subs,
    ## or arrays of records; returns diff in a string.
    ## WARNING: can return B<large> diffs for large files.
    my $diff = diff "file1.txt", "file2.txt", { STYLE => "Context" };
    my $diff = diff \$string1,   \$string2,   \%options;
    my $diff = diff \*FH1,       \*FH2;
    my $diff = diff \&reader1,   \&reader2;
    my $diff = diff \@records1,  \@records2;

    ## May also mix input types:
    my $diff = diff \@records1,  "file_B.txt";

=head1 DESCRIPTION

C<diff()> provides a basic set of services akin to the GNU C<diff> utility.  It
is not anywhere near as feature complete as GNU C<diff>, but it is better
integrated with Perl and available on all platforms.  It is often faster than
shelling out to a system's C<diff> executable for small files, and generally
slower on larger files.

Relies on L<Algorithm::Diff> for, well, the algorithm.  This may not produce
the same exact diff as a system's local C<diff> executable, but it will be a
valid diff and comprehensible by C<patch>.  We haven't seen any differences
between L<Algorithm::Diff>'s logic and GNU C<diff>'s, but we have not examined
them to make sure they are indeed identical.

B<Note>: If you don't want to import the C<diff> function, do one of the
following:

   use Text::Diff ();

   require Text::Diff;

That's a pretty rare occurrence,
so C<diff()> is exported by default.

If you pass a filename, but the file can't be read,
then C<diff()> will C<croak>.

=head1 OPTIONS

C<diff()> takes two parameters from which to draw input and a set of
options to control its output.  The options are:

=over

=item FILENAME_A, MTIME_A, FILENAME_B, MTIME_B

The name of the file and the modification time "files".

These are filled in automatically for each file when C<diff()> is passed a
filename, unless a defined value is passed in.

If a filename is not passed in and FILENAME_A and FILENAME_B are not provided
or are C<undef>, the header will not be printed.

Unused on C<OldStyle> diffs.

=item OFFSET_A, OFFSET_B

The index of the first line / element.  These default to 1 for all
parameter types except ARRAY references, for which the default is 0.  This
is because ARRAY references are presumed to be data structures, while the
others are line-oriented text.

=item STYLE

"Unified", "Context", "OldStyle", or an object or class reference for a class
providing C<file_header()>, C<hunk_header()>, C<hunk()>, C<hunk_footer()> and
C<file_footer()> methods.  The two footer() methods are provided for
overloading only; none of the formats provide them.

Defaults to "Unified" (unlike standard C<diff>, but Unified is what's most
often used in submitting patches and is the most human readable of the three.

If the package indicated by the STYLE has no C<hunk()> method, C<diff()> will
load it automatically (lazy loading).  Since all such packages should inherit
from C<Text::Diff::Base>, this should be marvy.

Styles may be specified as class names (C<STYLE =E<gt> 'Foo'>),
in which case they will be C<new()>ed with no parameters,
or as objects (C<STYLE =E<gt> Foo-E<gt>new>).

=item CONTEXT

How many lines before and after each diff to display.  Ignored on old-style
diffs.  Defaults to 3.

=item OUTPUT

Examples and their equivalent subroutines:

    OUTPUT   => \*FOOHANDLE,   # like: sub { print FOOHANDLE shift() }
    OUTPUT   => \$output,      # like: sub { $output .= shift }
    OUTPUT   => \@output,      # like: sub { push @output, shift }
    OUTPUT   => sub { $output .= shift },

If no C<OUTPUT> is supplied, returns the diffs in a string.  If
C<OUTPUT> is a C<CODE> ref, it will be called once with the (optional)
file header, and once for each hunk body with the text to emit.  If
C<OUTPUT> is an L<IO::Handle>, output will be emitted to that handle.

=item FILENAME_PREFIX_A, FILENAME_PREFIX_B

The string to print before the filename in the header. Unused on C<OldStyle>
diffs.  Defaults are C<"---">, C<"+++"> for Unified and C<"***">, C<"+++"> for
Context.

=item KEYGEN, KEYGEN_ARGS

These are passed to L<Algorithm::Diff/traverse_sequences>.

=item COLOR, PALETTE

C<diff()> output will be colorized based on GNU C<diff> colors depending on
the values passed.  A true value colorizes only if C<STDOUT> or C<OUTPUT>
handle is an interactive TTY, unless "always" is passed; if false is given,
never colorizes.  Defaults to 0.

    COLOR => 1,          # like: GNU diff "auto"
    COLOR => "always",

With PALETTE, C<diff()> colors can be customized according to the
L<Term::ANSIColor> spec by passing a hash with the following:

    ## Hunk sections and its default colors.
    ## NOTE: invalid colors are ignored.
    header       => BOLD,    # like: --- A   Mon Nov 12 23:49:30 2001
    line_number  => CYAN,    # like: @@ -2,13 +2,13 @@
    delete_line  => RED,     # like: -5d
    add_line     => GREEN,   # like: +5a
    same_line    => undef,   # "Unified" unchanged lines
    context_sep  => undef,   # "Context" separator: "***************"
    oldstyle_sep => undef,   # "OldStyle" separator: "---"
    table_frame  => undef,   # "Table" frames: "+--+----+--+----+", "|", "*"

=back

B<Note>: if neither C<FILENAME_> option is defined, the header will not be
printed.  If at least one is present, the other and both C<MTIME_> options must
be present or "Use of undefined variable" warnings will be generated (except
on C<OldStyle> diffs, which ignores these options).

=head1 Formatting Classes

These functions implement the output formats.  They are grouped in to classes
so C<diff()> can use class names to call the correct set of output routines and
so that you may inherit from them easily.  There are no constructors or
instance methods for these classes, though subclasses may provide them if need
be.

Each class has C<file_header()>, C<hunk_header()>, C<hunk()>, and C<footer()>
methods identical to those documented in the C<Text::Diff::Unified> section.
C<header()> is called before the C<hunk()> is first called, C<footer()>
afterwards.  The default footer function is an empty method provided for
overloading:

    sub footer { return "End of patch\n" }

Some output formats are provided by external modules (which are loaded
automatically), such as L<Text::Diff::Table>.  These are
documented here to keep the documentation simple.

=head2 Text::Diff::Base

Returns "" for all methods (other than C<new()>).

=head2 Text::Diff::Unified

  --- A   Mon Nov 12 23:49:30 2001
  +++ B   Mon Nov 12 23:49:30 2001
  @@ -2,13 +2,13 @@
   2
   3
   4
  -5d
  +5a
   6
   7
   8
   9
  +9a
   10
   11
  -11d
   12
   13

=over

=item Text::Diff::Unified::file_header

  $s = Text::Diff::Unified->file_header( $options );

Returns a string containing a unified header.  The sole parameter is the
C<options> hash passed in to C<diff()>, containing at least:

  FILENAME_A  => $fn1,
  MTIME_A     => $mtime1,
  FILENAME_B  => $fn2,
  MTIME_B     => $mtime2

May also contain

  FILENAME_PREFIX_A    => "---",
  FILENAME_PREFIX_B    => "+++",

to override the default prefixes (default values shown).

=item Text::Diff::Unified::hunk_header

  Text::Diff::Unified->hunk_header( \@ops, $options );

Returns a string containing the heading of one hunk of unified diff.

=item Text::Diff::Unified::hunk

  Text::Diff::Unified->hunk( \@seq_a, \@seq_b, \@ops, $options );

Returns a string containing the output of one hunk of unified diff.

=back

=head2 Text::Diff::Table

  +--+----------------------------------+--+------------------------------+
  |  |../Test-Differences-0.2/MANIFEST  |  |../Test-Differences/MANIFEST  |
  |  |Thu Dec 13 15:38:49 2001          |  |Sat Dec 15 02:09:44 2001      |
  +--+----------------------------------+--+------------------------------+
  |  |                                  * 1|Changes                       *
  | 1|Differences.pm                    | 2|Differences.pm                |
  | 2|MANIFEST                          | 3|MANIFEST                      |
  |  |                                  * 4|MANIFEST.SKIP                 *
  | 3|Makefile.PL                       | 5|Makefile.PL                   |
  |  |                                  * 6|t/00escape.t                  *
  | 4|t/00flatten.t                     | 7|t/00flatten.t                 |
  | 5|t/01text_vs_data.t                | 8|t/01text_vs_data.t            |
  | 6|t/10test.t                        | 9|t/10test.t                    |
  +--+----------------------------------+--+------------------------------+

This format also goes to some pains to highlight "invisible" characters on
differing elements by selectively escaping whitespace:

  +--+--------------------------+--------------------------+
  |  |demo_ws_A.txt             |demo_ws_B.txt             |
  |  |Fri Dec 21 08:36:32 2001  |Fri Dec 21 08:36:50 2001  |
  +--+--------------------------+--------------------------+
  | 1|identical                 |identical                 |
  * 2|        spaced in         |        also spaced in    *
  * 3|embedded space            |embedded        tab       *
  | 4|identical                 |identical                 |
  * 5|        spaced in         |\ttabbed in               *
  * 6|trailing spaces\s\s\n     |trailing tabs\t\t\n       *
  | 7|identical                 |identical                 |
  * 8|lf line\n                 |crlf line\r\n             *
  * 9|embedded ws               |embedded\tws              *
  +--+--------------------------+--------------------------+

See L<Text::Diff::Table> for more details, including how the whitespace
escaping works.

=head2 Text::Diff::Context

    *** A   Mon Nov 12 23:49:30 2001
    --- B   Mon Nov 12 23:49:30 2001
    ***************
    *** 2,14 ****
      2
      3
      4
    ! 5d
      6
      7
      8
      9
      10
      11
    - 11d
      12
      13
    --- 2,14 ----
      2
      3
      4
    ! 5a
      6
      7
      8
      9
    + 9a
      10
      11
      12
      13

Note: C<hunk_header()> returns only "***************\n".

=head2 Text::Diff::OldStyle

    5c5
    < 5d
    ---
    > 5a
    9a10
    > 9a
    12d12
    < 11d

Note: no C<file_header()>.

=head1 LIMITATIONS

Must suck both input files entirely in to memory and store them with a normal
amount of Perlish overhead (one array location) per record.  This is implied by
the implementation of L<Algorithm::Diff>, which takes two arrays.  If
L<Algorithm::Diff> ever offers an incremental mode, this can be changed
(contact the maintainers of L<Algorithm::Diff> and C<Text::Diff> if you need
this; it shouldn't be too terribly hard to tie arrays in this fashion).

Does not provide most of the more refined GNU C<diff> options: recursive
directory tree scanning, ignoring blank lines / whitespace, etc., etc.  These
can all be added as time permits and need arises, many are rather easy; patches
quite welcome.

Uses closures internally, this may lead to leaks on Perl versions 5.6.1 and
prior if used many times over a process' life time.

=head1 SEE ALSO

L<Algorithm::Diff> - the underlying implementation of the diff algorithm
used by C<Text::Diff>.

L<YAML::Diff> - find difference between two YAML documents.

L<HTML::Differences> - find difference between two HTML documents.
This uses a more sane approach than L<HTML::Diff>.

L<XML::Diff> - find difference between two XML documents.

L<Array::Diff> - find the differences between two Perl arrays.

L<Hash::Diff> - find the differences between two Perl hashes.

L<Data::Diff> - find difference between two arbitrary data structures.

=head1 REPOSITORY

L<https://github.com/neilbowers/Text-Diff>

=head1 AUTHOR

Adam Kennedy E<lt>adamk@cpan.orgE<gt>

Barrie Slaymaker E<lt>barries@slaysys.comE<gt>

=head1 COPYRIGHT

Some parts copyright 2009 Adam Kennedy.

Copyright 2001 Barrie Slaymaker.  All Rights Reserved.

You may use this under the terms of either the Artistic License or GNU Public
License v 2.0 or greater.

=cut

1;
