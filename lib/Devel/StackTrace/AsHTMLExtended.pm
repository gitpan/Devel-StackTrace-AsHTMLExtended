package Devel::StackTrace::AsHTMLExtended;

use strict;
use 5.008_001;
our $VERSION = '0.15';

use Data::Dumper;
use Devel::StackTrace;
use Scalar::Util;

no warnings 'qw';
my %enc = qw( & &amp; > &gt; < &lt; " &quot; ' &#39; );

# NOTE: because we don't know which encoding $str is in, or even if
# $str is a wide character (decoded strings), we just leave the low
# bits, including latin-1 range and encode everything higher as HTML
# entities. I know this is NOT always correct, but should mostly work
# in case $str is encoded in utf-8 bytes or wide chars. This is a
# necessary workaround since we're rendering someone else's code which
# we can't enforce string encodings.

sub encode_html {
    my $str = shift;
    $str =~ s/([^\x00-\x21\x23-\x25\x28-\x3b\x3d\x3f-\xff])/$enc{$1} || '&#' . ord($1) . ';' /ge;
    utf8::downgrade($str);
    $str;
}

sub Devel::StackTrace::as_html_extended {
    __PACKAGE__->render(@_);
}

sub render {
    my $class = shift;
    my $trace = shift;
    my %opt   = @_;

    my $msg = $opt{msg} // encode_html($trace->frame(0)->as_string(1));

    my $out;

    if (!$opt{inline}) {
        $out = qq{<!doctype html>
<html><head><title>Error: ${msg}</title>};
        $out .= '
<!--[if lt IE 9]>
<script src="https://oss.maxcdn.com/html5shiv/3.7.2/html5shiv.min.js"></script>
<script src="https://oss.maxcdn.com/respond/1.4.2/respond.min.js"></script>
<![endif]-->
<script src="https://ajax.googleapis.com/ajax/libs/jquery/1.11.1/jquery.min.js"></script>
<link href="https://maxcdn.bootstrapcdn.com/bootstrap/3.2.0/css/bootstrap.min.css" rel="stylesheet">
<link href="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/8.3/styles/default.min.css" rel="stylesheet">
<script src="https://maxcdn.bootstrapcdn.com/bootstrap/3.2.0/js/bootstrap.min.js"></script>
<script src="https://cdnjs.cloudflare.com/ajax/libs/highlight.js/8.3/highlight.min.js"></script>';
    }

    if (ref $opt{style}) {
        $out .= qq(<style type="text/css">${$opt{style}}</style>);
    } else {
        $out .= qq(<link rel="stylesheet" type="text/css" href=") . encode_html($opt{style}) . q(" />);
    }

    if (!$opt{inline}) {
        $out .= qq(</head><body style="padding:1em; border-top: 0px;"><h1>Error trace</h1><pre class="message">$msg</pre>);
    }

    my $i = 0;
    while (my $frame = $trace->next_frame) {
        $i++;
        my $next_frame = $trace->frame($i); # peek next

        my $file_link;
        if ($frame->filename) {

            if ($opt{source_link}) {
                my $link_url = $opt{source_link}->($frame->filename, $frame->line);
                $file_link = q(<a href=") . encode_html($link_url) . q(">) . encode_html($frame->filename) . q(</a>);
            } else {
                $file_link = encode_html($frame->filename);
            }
        }
        
        $out .= '<div>';
        if ($next_frame && $next_frame->subroutine) {
            $out .= "<h3><tt>" . encode_html($next_frame->subroutine) . "</tt></h3>";
            $out .= '<h5> at ';
            $out .= $frame->filename ? $file_link  : '';
            $out .= ' line ';
            $out .= $frame->line;
            $out .= '</h5>';
        } else {
            $out .= '<h3>';
            $out .= $frame->filename ? $file_link  : '';
            $out .= ' line ';
            $out .= $frame->line;
            $out .= '</h3>';
        }
        $out .= '</div>';

        $out .= '<div style="margin-left:2em">';
        $out .= '<pre><code class="perl">';
        $out .= _build_context($frame);
        $out .= '</code></pre>';

        if (!$opt{inline}) {
            $out .= qq{<div class="panel-group" id="accordion-$i">};
            $out .= _build_arguments($i, $next_frame);
            if ($frame->can('lexicals')) {
                $out .= _build_lexicals($i, $frame->lexicals)
            }
            $out .= qq{</div>};
        }

        $out .= '</div>';
    }

    if (!$opt{inline}) {
        $out .= '<script>hljs.initHighlightingOnLoad();
$(".collapse").collapse("hide");
$(".collapse_toggle").click(
function () {
var c = $(this).html();
if (c.indexOf("View") != -1) {
c = c.replace("View", "Hide");
$(this).html(c);
} else if(c.indexOf("Hide") != -1) {
c = c.replace("Hide", "View");
$(this).html(c);
}
})
</script>';

        $out .= "<footer>Generated by Devel::StackTrace::AsHTMLExtended $VERSION</footer>";
        $out .= '</body></html>';
    }

    $out;
}

my $dumper = sub {
    my $value = shift;
    $value = $$value if ref $value eq 'SCALAR' or ref $value eq 'REF';
    my $d = Data::Dumper->new([ $value ]);
    $d->Indent(1)->Terse(1)->Deparse(1);
    chomp(my $dump = $d->Dump);
    $dump;
};

sub _build_accordian_panel {
    my ($id, $sub_id, $title, $contents) = @_;
    my $ref = "p-$id-$sub_id";

    my $html = '<div class="panel panel-default"><div class="panel-heading"><h5 class="panel-title">';
    $html .= qq{<a data-toggle="collapse" data-parent="#accordion-$id" href="#$ref" class="collapse_toggle">};
    $html .= $title;
    $html .= '</a></h5></div>';
    $html .= qq{<div id="$ref" class="panel-collapse collapse in"><div class="panel-body">$contents</div></div>};
    $html .= '</div>';
    return $html;
}

sub _build_arguments {
    my($id, $frame) = @_;
    my $ref = "arg-$id";

    return '' unless $frame && $frame->args;

    my @args = $frame->args;

    my $html = qq(<table class="table table-hover table-condensed table-bordered"><tr><th>Argument</th><th>Value</th></tr>);
    
    # Don't use while each since Dumper confuses that
    for my $idx (0 .. @args - 1) {
        my $value = $args[$idx];
        my $dump = $dumper->($value);
        $html .= qq{<tr>};
        $html .= qq{<td class="variable"><tt>\$_[$idx]</tt></td>};
        $html .= qq{<td class="value"><pre class="pre-scrollable"><code>} . encode_html($dump) . qq{</code></pre></td>};
        $html .= qq{</tr>};
    }
    $html .= qq(</table>);

    return _build_accordian_panel($id, "args", "View Arguments", $html);
}

sub _build_lexicals {
    my($id, $lexicals) = @_;

    return '' unless keys %$lexicals;

    my $html = qq(<table class="table table-hover table-condensed table-bordered"><tr><th>Variable</th><th>Value</th></tr>);
    # Don't use while each since Dumper confuses that
    for my $var (sort keys %$lexicals) {
        my $value = $lexicals->{$var};
        my $dump = $dumper->($value);
        $dump =~ s/^\{(.*)\}$/($1)/s if $var =~ /^\%/;
        $dump =~ s/^\[(.*)\]$/($1)/s if $var =~ /^\@/;
        $html .= q{<tr>};
        $html .= q{<td class="variable"><tt>} . encode_html($var) . q{</tt></td>};
        $html .= q{<td class="value"><pre class="pre-scrollable"><code>} . encode_html($dump) . q{</code></pre></td>};
        $html .= q{</tr>};
    }
    $html .= qq(</table>);

    return _build_accordian_panel($id, "lex", "View Lexicals", $html);
}

sub _build_context {
    my $frame = shift;
    my $file    = $frame->filename;
    my $linenum = $frame->line;
    my $code;
    if (-f $file) {
        my $start = $linenum - 3;
        my $end   = $linenum + 3;
        $start = $start < 1 ? 1 : $start;
        open my $fh, '<', $file
            or die "cannot open $file:$!";
        my $cur_line = 0;
        while (my $line = <$fh>) {
            ++$cur_line;
            last if $cur_line > $end;
            next if $cur_line < $start;
            $line =~ s|\t|        |g;
            my @tag = $cur_line == $linenum
                ? (q{<strong style="background: #faa">}, '</strong>')
                    : ('', '');
            $code .= sprintf(
                '%s%5d: %s%s', $tag[0], $cur_line, encode_html($line),
                $tag[1],
            );
        }
        close $file;
    }
    return $code;
}

1;
__END__

=encoding utf-8

=for stopwords

=head1 NAME

Devel::StackTrace::AsHTMLExtended - Displays stack trace in HTML

=head1 SYNOPSIS

  use Devel::StackTrace::AsHTMLExtended;

  my $trace = Devel::StackTrace->new;
  my $html  = $trace->as_html_extended;

=head1 DESCRIPTION

Devel::StackTrace::AsHTMLExtended adds C<as_html_extended> method to
L<Devel::StackTrace> which displays the stack trace in Bootstrap and
Highlight.js enabled HTML, with code snippet context and function
parameters. If you call it on an instance of
L<Devel::StackTrace::WithLexicals>, you even get to see the lexical
variables of each stack frame.

=head1 AUTHOR

Rusty Conover E<lt>rusty@luckydinosaur.comE<gt>

Based off of L<Devel::StackTrace::AsHTML> by:

Tatsuhiko Miyagawa E<lt>miyagawa@bulknews.netE<gt>

Shawn M Moore

HTML generation code is ripped off from L<CGI::ExceptionManager> written by Tokuhiro Matsuno and Kazuho Oku.

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Devel::StackTrace::AsHTML>
L<Devel::StackTrace> L<Devel::StackTrace::WithLexicals> L<CGI::ExceptionManager>

=cut