#!/usr/bin/perl

## Test COLOR and PALLETE options correctness; they must behave like described
## in POD.
## All styles (Unified, Context, OldStyle, and Table) outputs must match their
## respective expected colorized outputs.

use strict;
use warnings;

use Test::More 0.96;

use File::Spec::Functions qw( catfile );
use File::Temp            qw( tempdir tempfile );
use Text::Diff;
use Text::Diff::Table;
use IO::Handle;

## Texts based on https://en.wikipedia.org/wiki/Diff#Default_output_format.

my $TEXT_ORIG = <<'END';
This part of the
document has stayed the
same.

This paragraph contains
text that is outdated.

It is important to spell
check this dokument.
Things can be added
after it.
END

my $TEXT_NEW = <<'END';
This is an important
notice!

This part of the
document has stayed the
same.

It is important to spell
check this document.
Things can be added
after it.

This paragraph contains
important new additions
to this document.
END

## Tests based on https://github.com/neilb/Text-Diff/blob/master/t/newlines.t.

my %EXPECTED_OUTPUTS = (
    "Unified" => {
        "default" => <<"END",
\x{1b}[36m\@\@ -1,11 +1,15 \@\@\x{1b}[0m
\x{1b}[32m+This is an important\x{1b}[0m
\x{1b}[32m+notice!\x{1b}[0m
\x{1b}[32m+\x{1b}[0m
 This part of the
 document has stayed the
 same.
 
\x{1b}[31m-This paragraph contains\x{1b}[0m
\x{1b}[31m-text that is outdated.\x{1b}[0m
\x{1b}[31m-\x{1b}[0m
 It is important to spell
\x{1b}[31m-check this dokument.\x{1b}[0m
\x{1b}[32m+check this document.\x{1b}[0m
 Things can be added
 after it.
\x{1b}[32m+\x{1b}[0m
\x{1b}[32m+This paragraph contains\x{1b}[0m
\x{1b}[32m+important new additions\x{1b}[0m
\x{1b}[32m+to this document.\x{1b}[0m
END
        "custom_palette" => <<"END",
\x{1b}[30;46m\@\@ -1,11 +1,15 \@\@\x{1b}[0m
\x{1b}[30;42m+This is an important\x{1b}[0m
\x{1b}[30;42m+notice!\x{1b}[0m
\x{1b}[30;42m+\x{1b}[0m
\x{1b}[30;47m This part of the\x{1b}[0m
\x{1b}[30;47m document has stayed the\x{1b}[0m
\x{1b}[30;47m same.\x{1b}[0m
\x{1b}[30;47m \x{1b}[0m
\x{1b}[30;41m-This paragraph contains\x{1b}[0m
\x{1b}[30;41m-text that is outdated.\x{1b}[0m
\x{1b}[30;41m-\x{1b}[0m
\x{1b}[30;47m It is important to spell\x{1b}[0m
\x{1b}[30;41m-check this dokument.\x{1b}[0m
\x{1b}[30;42m+check this document.\x{1b}[0m
\x{1b}[30;47m Things can be added\x{1b}[0m
\x{1b}[30;47m after it.\x{1b}[0m
\x{1b}[30;42m+\x{1b}[0m
\x{1b}[30;42m+This paragraph contains\x{1b}[0m
\x{1b}[30;42m+important new additions\x{1b}[0m
\x{1b}[30;42m+to this document.\x{1b}[0m
END
    },
    "Context" => {
        "default" => <<"END",
***************
\x{1b}[36m*** 1,11 ****\x{1b}[0m
\x{1b}[31m  This part of the\x{1b}[0m
\x{1b}[31m  document has stayed the\x{1b}[0m
\x{1b}[31m  same.\x{1b}[0m
\x{1b}[31m  \x{1b}[0m
\x{1b}[31m- This paragraph contains\x{1b}[0m
\x{1b}[31m- text that is outdated.\x{1b}[0m
\x{1b}[31m- \x{1b}[0m
\x{1b}[31m  It is important to spell\x{1b}[0m
\x{1b}[31m! check this dokument.\x{1b}[0m
\x{1b}[31m  Things can be added\x{1b}[0m
\x{1b}[31m  after it.\x{1b}[0m
\x{1b}[36m--- 1,15 ----\x{1b}[0m
\x{1b}[32m+ This is an important\x{1b}[0m
\x{1b}[32m+ notice!\x{1b}[0m
\x{1b}[32m+ \x{1b}[0m
\x{1b}[32m  This part of the\x{1b}[0m
\x{1b}[32m  document has stayed the\x{1b}[0m
\x{1b}[32m  same.\x{1b}[0m
\x{1b}[32m  \x{1b}[0m
\x{1b}[32m  It is important to spell\x{1b}[0m
\x{1b}[32m! check this document.\x{1b}[0m
\x{1b}[32m  Things can be added\x{1b}[0m
\x{1b}[32m  after it.\x{1b}[0m
\x{1b}[32m+ \x{1b}[0m
\x{1b}[32m+ This paragraph contains\x{1b}[0m
\x{1b}[32m+ important new additions\x{1b}[0m
\x{1b}[32m+ to this document.\x{1b}[0m
END
        "custom_palette" => <<"END",
\x{1b}[1;30;44m***************\x{1b}[0m
\x{1b}[30;46m*** 1,11 ****\x{1b}[0m
\x{1b}[30;41m  This part of the\x{1b}[0m
\x{1b}[30;41m  document has stayed the\x{1b}[0m
\x{1b}[30;41m  same.\x{1b}[0m
\x{1b}[30;41m  \x{1b}[0m
\x{1b}[30;41m- This paragraph contains\x{1b}[0m
\x{1b}[30;41m- text that is outdated.\x{1b}[0m
\x{1b}[30;41m- \x{1b}[0m
\x{1b}[30;41m  It is important to spell\x{1b}[0m
\x{1b}[30;41m! check this dokument.\x{1b}[0m
\x{1b}[30;41m  Things can be added\x{1b}[0m
\x{1b}[30;41m  after it.\x{1b}[0m
\x{1b}[30;46m--- 1,15 ----\x{1b}[0m
\x{1b}[30;42m+ This is an important\x{1b}[0m
\x{1b}[30;42m+ notice!\x{1b}[0m
\x{1b}[30;42m+ \x{1b}[0m
\x{1b}[30;42m  This part of the\x{1b}[0m
\x{1b}[30;42m  document has stayed the\x{1b}[0m
\x{1b}[30;42m  same.\x{1b}[0m
\x{1b}[30;42m  \x{1b}[0m
\x{1b}[30;42m  It is important to spell\x{1b}[0m
\x{1b}[30;42m! check this document.\x{1b}[0m
\x{1b}[30;42m  Things can be added\x{1b}[0m
\x{1b}[30;42m  after it.\x{1b}[0m
\x{1b}[30;42m+ \x{1b}[0m
\x{1b}[30;42m+ This paragraph contains\x{1b}[0m
\x{1b}[30;42m+ important new additions\x{1b}[0m
\x{1b}[30;42m+ to this document.\x{1b}[0m
END
    },
    "OldStyle" => {
        "default" => <<"END",
\x{1b}[36m0a1,3\x{1b}[0m
\x{1b}[32m> This is an important\x{1b}[0m
\x{1b}[32m> notice!\x{1b}[0m
\x{1b}[32m> \x{1b}[0m
\x{1b}[36m5,7d7\x{1b}[0m
\x{1b}[31m< This paragraph contains\x{1b}[0m
\x{1b}[31m< text that is outdated.\x{1b}[0m
\x{1b}[31m< \x{1b}[0m
\x{1b}[36m9c9\x{1b}[0m
\x{1b}[31m< check this dokument.\x{1b}[0m
---
\x{1b}[32m> check this document.\x{1b}[0m
\x{1b}[36m11a12,15\x{1b}[0m
\x{1b}[32m> \x{1b}[0m
\x{1b}[32m> This paragraph contains\x{1b}[0m
\x{1b}[32m> important new additions\x{1b}[0m
\x{1b}[32m> to this document.\x{1b}[0m
END
        "custom_palette" => <<"END",
\x{1b}[30;46m0a1,3\x{1b}[0m
\x{1b}[30;42m> This is an important\x{1b}[0m
\x{1b}[30;42m> notice!\x{1b}[0m
\x{1b}[30;42m> \x{1b}[0m
\x{1b}[30;46m5,7d7\x{1b}[0m
\x{1b}[30;41m< This paragraph contains\x{1b}[0m
\x{1b}[30;41m< text that is outdated.\x{1b}[0m
\x{1b}[30;41m< \x{1b}[0m
\x{1b}[30;46m9c9\x{1b}[0m
\x{1b}[30;41m< check this dokument.\x{1b}[0m
\x{1b}[1;30;44m---\x{1b}[0m
\x{1b}[30;42m> check this document.\x{1b}[0m
\x{1b}[30;46m11a12,15\x{1b}[0m
\x{1b}[30;42m> \x{1b}[0m
\x{1b}[30;42m> This paragraph contains\x{1b}[0m
\x{1b}[30;42m> important new additions\x{1b}[0m
\x{1b}[30;42m> to this document.\x{1b}[0m
END
    },
    "Table" => {
        "default" => <<"END",
+---+--------------------------+---+--------------------------+\x{1b}[0m
|   |                          *\x{1b}[0m \x{1b}[36m 1\x{1b}[0m|\x{1b}[0m\x{1b}[32mThis is an important    \x{1b}[0m  *\x{1b}[0m
|   |                          *\x{1b}[0m \x{1b}[36m 2\x{1b}[0m|\x{1b}[0m\x{1b}[32mnotice!                 \x{1b}[0m  *\x{1b}[0m
|   |                          *\x{1b}[0m \x{1b}[36m 3\x{1b}[0m|\x{1b}[0m\x{1b}[32m\\n                      \x{1b}[0m  *\x{1b}[0m
|\x{1b}[0m \x{1b}[36m 1\x{1b}[0m|\x{1b}[0mThis part of the        \x{1b}[0m  |\x{1b}[0m \x{1b}[36m 4\x{1b}[0m|\x{1b}[0mThis part of the        \x{1b}[0m  |\x{1b}[0m
|\x{1b}[0m \x{1b}[36m 2\x{1b}[0m|\x{1b}[0mdocument has stayed the \x{1b}[0m  |\x{1b}[0m \x{1b}[36m 5\x{1b}[0m|\x{1b}[0mdocument has stayed the \x{1b}[0m  |\x{1b}[0m
|\x{1b}[0m \x{1b}[36m 3\x{1b}[0m|\x{1b}[0msame.                   \x{1b}[0m  |\x{1b}[0m \x{1b}[36m 6\x{1b}[0m|\x{1b}[0msame.                   \x{1b}[0m  |\x{1b}[0m
|\x{1b}[0m \x{1b}[36m 4\x{1b}[0m|\x{1b}[0m                        \x{1b}[0m  |\x{1b}[0m \x{1b}[36m 7\x{1b}[0m|\x{1b}[0m                        \x{1b}[0m  |\x{1b}[0m
*\x{1b}[0m \x{1b}[36m 5\x{1b}[0m|\x{1b}[0m\x{1b}[31mThis paragraph contains \x{1b}[0m  *   |                          |\x{1b}[0m
*\x{1b}[0m \x{1b}[36m 6\x{1b}[0m|\x{1b}[0m\x{1b}[31mtext that is outdated.  \x{1b}[0m  *   |                          |\x{1b}[0m
*\x{1b}[0m \x{1b}[36m 7\x{1b}[0m|\x{1b}[0m\x{1b}[31m\\n                      \x{1b}[0m  *   |                          |\x{1b}[0m
|\x{1b}[0m \x{1b}[36m 8\x{1b}[0m|\x{1b}[0mIt is important to spell\x{1b}[0m  |\x{1b}[0m \x{1b}[36m 8\x{1b}[0m|\x{1b}[0mIt is important to spell\x{1b}[0m  |\x{1b}[0m
*\x{1b}[0m \x{1b}[36m 9\x{1b}[0m|\x{1b}[0m\x{1b}[31mcheck this dokument.    \x{1b}[0m  *\x{1b}[0m \x{1b}[36m 9\x{1b}[0m|\x{1b}[0m\x{1b}[32mcheck this document.    \x{1b}[0m  *\x{1b}[0m
|\x{1b}[0m \x{1b}[36m10\x{1b}[0m|\x{1b}[0mThings can be added     \x{1b}[0m  |\x{1b}[0m \x{1b}[36m10\x{1b}[0m|\x{1b}[0mThings can be added     \x{1b}[0m  |\x{1b}[0m
|\x{1b}[0m \x{1b}[36m11\x{1b}[0m|\x{1b}[0mafter it.               \x{1b}[0m  |\x{1b}[0m \x{1b}[36m11\x{1b}[0m|\x{1b}[0mafter it.               \x{1b}[0m  |\x{1b}[0m
|   |                          *\x{1b}[0m \x{1b}[36m12\x{1b}[0m|\x{1b}[0m\x{1b}[32m\\n                      \x{1b}[0m  *\x{1b}[0m
|   |                          *\x{1b}[0m \x{1b}[36m13\x{1b}[0m|\x{1b}[0m\x{1b}[32mThis paragraph contains \x{1b}[0m  *\x{1b}[0m
|   |                          *\x{1b}[0m \x{1b}[36m14\x{1b}[0m|\x{1b}[0m\x{1b}[32mimportant new additions \x{1b}[0m  *\x{1b}[0m
|   |                          *\x{1b}[0m \x{1b}[36m15\x{1b}[0m|\x{1b}[0m\x{1b}[32mto this document.       \x{1b}[0m  *\x{1b}[0m
+---+--------------------------+---+--------------------------+\x{1b}[0m
END
        "custom_palette" => <<"END",
\x{1b}[93m+---+--------------------------+---+--------------------------+\x{1b}[0m
\x{1b}[93m|   |                          *\x{1b}[0m \x{1b}[30;46m 1\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;42mThis is an important    \x{1b}[0m  \x{1b}[93m*\x{1b}[0m
\x{1b}[93m|   |                          *\x{1b}[0m \x{1b}[30;46m 2\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;42mnotice!                 \x{1b}[0m  \x{1b}[93m*\x{1b}[0m
\x{1b}[93m|   |                          *\x{1b}[0m \x{1b}[30;46m 3\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;42m\\n                      \x{1b}[0m  \x{1b}[93m*\x{1b}[0m
\x{1b}[93m|\x{1b}[0m \x{1b}[30;46m 1\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;47mThis part of the        \x{1b}[0m  \x{1b}[93m|\x{1b}[0m \x{1b}[30;46m 4\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;47mThis part of the        \x{1b}[0m  \x{1b}[93m|\x{1b}[0m
\x{1b}[93m|\x{1b}[0m \x{1b}[30;46m 2\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;47mdocument has stayed the \x{1b}[0m  \x{1b}[93m|\x{1b}[0m \x{1b}[30;46m 5\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;47mdocument has stayed the \x{1b}[0m  \x{1b}[93m|\x{1b}[0m
\x{1b}[93m|\x{1b}[0m \x{1b}[30;46m 3\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;47msame.                   \x{1b}[0m  \x{1b}[93m|\x{1b}[0m \x{1b}[30;46m 6\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;47msame.                   \x{1b}[0m  \x{1b}[93m|\x{1b}[0m
\x{1b}[93m|\x{1b}[0m \x{1b}[30;46m 4\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;47m                        \x{1b}[0m  \x{1b}[93m|\x{1b}[0m \x{1b}[30;46m 7\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;47m                        \x{1b}[0m  \x{1b}[93m|\x{1b}[0m
\x{1b}[93m*\x{1b}[0m \x{1b}[30;46m 5\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;41mThis paragraph contains \x{1b}[0m  \x{1b}[93m*   |                          |\x{1b}[0m
\x{1b}[93m*\x{1b}[0m \x{1b}[30;46m 6\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;41mtext that is outdated.  \x{1b}[0m  \x{1b}[93m*   |                          |\x{1b}[0m
\x{1b}[93m*\x{1b}[0m \x{1b}[30;46m 7\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;41m\\n                      \x{1b}[0m  \x{1b}[93m*   |                          |\x{1b}[0m
\x{1b}[93m|\x{1b}[0m \x{1b}[30;46m 8\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;47mIt is important to spell\x{1b}[0m  \x{1b}[93m|\x{1b}[0m \x{1b}[30;46m 8\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;47mIt is important to spell\x{1b}[0m  \x{1b}[93m|\x{1b}[0m
\x{1b}[93m*\x{1b}[0m \x{1b}[30;46m 9\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;41mcheck this dokument.    \x{1b}[0m  \x{1b}[93m*\x{1b}[0m \x{1b}[30;46m 9\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;42mcheck this document.    \x{1b}[0m  \x{1b}[93m*\x{1b}[0m
\x{1b}[93m|\x{1b}[0m \x{1b}[30;46m10\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;47mThings can be added     \x{1b}[0m  \x{1b}[93m|\x{1b}[0m \x{1b}[30;46m10\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;47mThings can be added     \x{1b}[0m  \x{1b}[93m|\x{1b}[0m
\x{1b}[93m|\x{1b}[0m \x{1b}[30;46m11\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;47mafter it.               \x{1b}[0m  \x{1b}[93m|\x{1b}[0m \x{1b}[30;46m11\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;47mafter it.               \x{1b}[0m  \x{1b}[93m|\x{1b}[0m
\x{1b}[93m|   |                          *\x{1b}[0m \x{1b}[30;46m12\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;42m\\n                      \x{1b}[0m  \x{1b}[93m*\x{1b}[0m
\x{1b}[93m|   |                          *\x{1b}[0m \x{1b}[30;46m13\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;42mThis paragraph contains \x{1b}[0m  \x{1b}[93m*\x{1b}[0m
\x{1b}[93m|   |                          *\x{1b}[0m \x{1b}[30;46m14\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;42mimportant new additions \x{1b}[0m  \x{1b}[93m*\x{1b}[0m
\x{1b}[93m|   |                          *\x{1b}[0m \x{1b}[30;46m15\x{1b}[0m\x{1b}[93m|\x{1b}[0m\x{1b}[30;42mto this document.       \x{1b}[0m  \x{1b}[93m*\x{1b}[0m
\x{1b}[93m+---+--------------------------+---+--------------------------+\x{1b}[0m
END
    },
);

my $NAMES = {
    never           => "file diff 'never'",
    auto            => "file diff 'auto'",
    always          => "file diff 'always'",
    invalid_hunks   => "file diff 'always' (invalid hunks)",
    invalid_palette => "file diff 'always' (invalid palette)",
};

my $PALETTE = {
    valid => {
        header       => "bold blue",
        line_number  => "black on_cyan",
        delete_line  => "black on_red",
        add_line     => "black on_green",
        same_line    => "black on_white",
        context_sep  => "bold black on_blue",
        oldstyle_sep => "bold black on_blue",
        table_frame  => "bright_yellow",
    },
    invalid => {
        header       => "bogus bold blue",
        line_number  => "bogus black on_cyan",
        delete_line  => "bogus black on_red",
        add_line     => "bogus black on_green",
        same_line    => "bogus black on_white",
        context_sep  => "bogus bold black on_blue",
        oldstyle_sep => "bogus bold black on_blue",
        table_frame  => "bogus bright_yellow",
    },
};

my $HUNKS = {
    invalid => {
        bogus_header       => "bold blue",
        bogus_line_number  => "black on_cyan",
        bogus_delete_line  => "black on_red",
        bogus_add_line     => "black on_green",
        bogus_same_line    => "black on_white",
        bogus_context_sep  => "bold black on_blue",
        bogus_oldstyle_sep => "bold black on_blue",
        bogus_table_frame  => "bright_yellow",
    },
};

sub _verbose_output {
    note "Original text";
    note explain _indent( $TEXT_ORIG );
    note "\n";
    note "New text";
    note explain _indent( $TEXT_NEW );
    note "\n";

    for my $style ( qw/ Unified Context OldStyle Table / ) {
        note $style;
        note "(expected default)";
        note explain _indent( $EXPECTED_OUTPUTS{$style}{default} );
        note "\n";
        note "(expected custom_palette)";
        note explain _indent( $EXPECTED_OUTPUTS{$style}{custom_palette} );
        note "\n";
    }
}

sub _indent {
    my $text = shift;

    return $text =~ s/^/  /mgr if defined $text;
}

sub _spew {
    my ( $content, $file ) = @_;

    open my $fh, ">", $file or die $!;
    print $fh $content or die $!;
    close $fh or die $!;
}

## Generate diff() file header.
sub _file_header {
    my ( $options ) = @_;

    my ( $file_a, $file_b, $style, $colors ) = @{$options}{
        "file_a",
        "file_b",
        "style",
        "colors",
    };

    my $file_stats = {
        FILENAME_A => $file_a,
        MTIME_A    => (stat( $file_a ))[9],
        FILENAME_B => $file_b,
        MTIME_B    => (stat( $file_b ))[9],
        PALETTE    => $colors,
    };

    if ( $style eq "Table" ) {
        my @heading_lines = Text::Diff::Table::_header( $file_stats );

        my $fmt_opts = {
            width       => [2, 24, 2, 24],
            column_mode => 1,
            palette     => $colors,
        };

        my %heading_fmts = Text::Diff::Table::_header_fmt( $fmt_opts );
        my %fmts         = Text::Diff::Table::_table_fmt( $fmt_opts );

        my $bar = Text::Diff::Table::_bar_fmt(
            {
                bar         => $fmts{"="},
                column_mode => 1,
                palette     => $colors,
            }
        );

        my $heading = Text::Diff::Table::_heading(
            {
                bar   => $bar,
                fmts  => \%heading_fmts,
                lines => \@heading_lines,
            }
        );

        return $heading;
    }
    else {
        my $header_sub = ( "Text::Diff::" . $style )->can( "file_header" );

        return $header_sub->(
            undef,
            $file_stats,
        );
    }
}

_verbose_output();

## Initialize temporary directory and files.

my $temp_dir = tempdir( CLEANUP => 1 );
my $file_a   = catfile( $temp_dir, "a.txt" );
my $file_b   = catfile( $temp_dir, "b.txt" );

_spew( $TEXT_ORIG, $file_a );
_spew( $TEXT_NEW,  $file_b );

## Tests

## NOTE:
## A true value (auto) cannot be tested reliably, since TAP::Harness/prove seem
## to modify STDOUT.
for my $style ( qw/ Unified Context OldStyle Table / ) {
    my $test = $EXPECTED_OUTPUTS{$style};

    subtest $style => sub {
        my $palette;
        my $colors;

        for my $expected ( qw/ default custom_palette / ) {
            ## Init test variables/closures.

            if ( $expected eq "default" ) {
                $palette = undef;
                $colors  = Text::Diff::_get_colors();
            }
            elsif ( $expected eq "custom_palette" ) {
                $palette = $PALETTE->{valid};
                $colors  = Text::Diff::_get_colors( $palette );
            }

            my $header_opts = {
                file_a => $file_a,
                file_b => $file_b,
                style  => $style,
                colors => $colors,
            };

            my $get_opts = sub {
                my ( $options ) = @_;

                my $diff_opts = $options->{diff};
                my $is        = $options->{test}{is};
                my $isnt      = $options->{test}{isnt};
                my $expected  = $options->{test}{expected};

                if ( defined $is || defined $isnt ) {
                    if ( defined $expected && $expected ne "invalid_default" ) {
                        $expected = _file_header( $header_opts ) . $test->{$expected};
                    }
                }

                if ( defined $expected && $expected eq "invalid_default" ) {
                    $expected = _file_header(
                        {
                            file_a => $file_a,
                            file_b => $file_b,
                            style  => $style,
                            colors => Text::Diff::_get_colors(),
                        }
                    ) . $test->{default};
                }

                return ( $diff_opts, $is, $isnt, $expected );
            };

            my $test_it = sub {
                my ( $options ) = @_;
                my ( $diff_opts, $is, $isnt, $expected ) = $get_opts->( $options );

                my $diff = sub {
                    diff(
                        $file_a, $file_b,
                        {
                            STYLE => $style,
                            %{$diff_opts},
                        }
                    );
                };

                if ( defined $is ) {
                    is(
                        $diff->(),
                        $expected,
                        $options->{test}{name},
                    );
                }
                elsif ( defined $isnt ) {
                    isnt(
                        $diff->(),
                        $expected,
                        $options->{test}{name},
                    );
                }
            };

            my $isnt_auto = sub {
                {
                    diff => {
                        COLOR   => 1,
                        PALETTE => $palette,
                    },
                    test => {
                        isnt     => 1,
                        expected => $expected,
                        name     => $NAMES->{auto},
                    }
                }
            };

            my $is_always = sub {
                {
                    diff => {
                        COLOR   => "always",
                        PALETTE => $palette,
                    },
                    test => {
                        is       => 1,
                        expected => $expected,
                        name     => $NAMES->{always},
                    },
                }
            };

            my $isnt_hunks_invalid = sub {
                ## Invalid hunks cannot get its expected custom palette colors.
                {
                    diff => {
                        COLOR   => "always",
                        PALETTE => $HUNKS->{invalid},
                    },
                    test => {
                        isnt     => 1,
                        expected => $expected,
                        name     => $NAMES->{invalid_hunks},
                    },
                }
            };

            my $is_palette_valid = sub {
                ## Invalid palettes get its expected default colors.
                {
                    diff => {
                        COLOR   => "always",
                        PALETTE => $PALETTE->{invalid},
                    },
                    test => {
                        is       => 1,
                        expected => "invalid_default",
                        name     => $NAMES->{invalid_palette},
                    },
                }
            };

            ## Begin tests.
            subtest $expected => sub {
                $test_it->(
                    {
                        diff => {
                            COLOR => 0,
                        },
                        test => {
                            isnt     => 1,
                            expected => $expected,
                            name     => $NAMES->{never},
                        },
                    }
                );

                $test_it->( $is_always->() );

                ## Test bogus PALETTE input.
                if ( $expected eq "custom_palette" ) {
                    $test_it->( $isnt_hunks_invalid->() );
                    $test_it->( $is_palette_valid->() );
                }

                ## Non-TTY tests.
                subtest "non-TTY" => sub {
                    subtest "STDOUT" => sub {
                        ## Emulate non-TTY STDOUT.
                        {
                            local *STDOUT;

                            $test_it->( $isnt_auto->() );
                            $test_it->( $is_always->() );

                            if ( $expected eq "custom_palette" ) {
                                $test_it->( $isnt_hunks_invalid->() );
                                $test_it->( $is_palette_valid->() );
                            }
                        }
                    };

                    ## OUTPUT option tests.
                    for my $output ( qw/ GLOB IO::Handle / ) {
                        subtest "OUTPUT ($output)" => sub {
                            my $io = IO::Handle->new if $output eq "IO::Handle";

                            my $output_test_it = sub {
                                my ( $options ) = @_;
                                my ( $diff_opts, $is, $isnt, $expected ) = $get_opts->( $options );

                                my $glob = tempfile( DIR => $temp_dir );

                                if ( $output eq "IO::Handle" ) {
                                    if ( defined $io && $io->fdopen( fileno( $glob ), "r+" ) ) {
                                        $glob = $io;
                                    } else {
                                        die "Failed to fdopen(): $!";
                                    }
                                }

                                ## diff() output is sent to $glob handle.
                                diff(
                                    $file_a, $file_b,
                                    {
                                        STYLE  => $style,
                                        %{$diff_opts},
                                        OUTPUT => $glob,
                                    }
                                );

                                ## Rewind $glob before slurping it, so diff()
                                ## output can be captured.
                                seek $glob, 0, 0 or die $!;
                                my $diff = do { local $/; <$glob> };
                                #print $diff;
                                close $glob or die $!;

                                if ( defined $is ) {
                                    is(
                                        $diff,
                                        $expected,
                                        $options->{test}{name},
                                    );
                                }
                                elsif ( defined $isnt ) {
                                    isnt(
                                        $diff,
                                        $expected,
                                        $options->{test}{name},
                                    );
                                }
                            };

                            $output_test_it->( $isnt_auto->() );
                            $output_test_it->( $is_always->() );

                            if ( $expected eq "custom_palette" ) {
                                $output_test_it->( $isnt_hunks_invalid->() );
                                $output_test_it->( $is_palette_valid->() );
                            }
                        };
                    }
                };
            };
        }
    };
}

done_testing();
