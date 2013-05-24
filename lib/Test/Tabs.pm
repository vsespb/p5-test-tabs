package Test::Tabs;

use 5.008;
use strict;
use warnings;

BEGIN {
	$Test::Tabs::AUTHORITY = 'cpan:TOBYINK';
	$Test::Tabs::VERSION   = '0.002';
}

use Test::Builder;
use File::Spec;
use FindBin qw($Bin);
use File::Find;

use vars qw( $PERL $UNTAINT_PATTERN $PERL_PATTERN );

$PERL             = $^X || 'perl';
$UNTAINT_PATTERN  = qr|^([-+@\w./:\\]+)$|;
$PERL_PATTERN     = qr/^#!.*perl/;

my %file_find_arg = ($] <= 5.006) ? () : (
	untaint         => 1,
	untaint_pattern => $UNTAINT_PATTERN,
	untaint_skip    => 1,
);

my $Test  = Test::Builder->new;
my $updir = File::Spec->updir();

sub import
{
	my $self   = shift;
	my $caller = caller;
	{
		no strict 'refs';
		*{$caller.'::tabs_ok'} = \&tabs_ok;
		*{$caller.'::all_perl_files_ok'} = \&all_perl_files_ok;
	}
	$Test->exported_to($caller);
	$Test->plan(@_);
}

sub _all_perl_files
{
	my @all_files = _all_files(@_);
	return grep { _is_perl_module($_) || _is_perl_script($_) } @all_files;
}

sub _all_files
{
	my @base_dirs = @_ ? @_ : File::Spec->catdir($Bin, $updir);
	my @found;
	my $want_sub = sub
	{
		return if ($File::Find::dir =~ m![\\/]?CVS[\\/]|[\\/]?\.svn[\\/]!); # Filter out cvs or subversion dirs/
		return if ($File::Find::dir =~ m![\\/]?blib[\\/]libdoc$!); # Filter out pod doc in dist
		return if ($File::Find::dir =~ m![\\/]?inc!); # Remove Module::Install
		return if ($File::Find::dir =~ m![\\/]?blib[\\/]man\d$!); # Filter out pod doc in dist
		return if ($File::Find::name =~ m!Build$!i); # Filter out autogenerated Build script
		return unless (-f $File::Find::name && -r _);
		push @found, File::Spec->no_upwards( $File::Find::name );
	};
	my $find_arg = {
		%file_find_arg,
		wanted   => $want_sub,
		no_chdir => 1,
	};
	find( $find_arg, @base_dirs);
	return @found;
}
 
sub tabs_ok
{
	my $file = shift;
	$file = _module_to_path($file);
	open my $fh, $file or do {
		$Test->ok(0, "whitespace for $file");
		$Test->diag("Could not open $file: $!");
		return;
	};
	my $line        = 0;
	my $last_indent = 0;
	my $ignoring    = 0;
	my $ok          = 1;
	while (<$fh>)
	{
		$line++;
		
		my $ignore_line = /##\s*WS/i;
		$ignoring = 1 if /#\s*no\s*Test::Tabs/;
		$ignoring = 0 if /#\s*use\s*Test::Tabs/;
		
		if (/#\s*skip\s*Test::Tabs/)
		{
			$ok
				? $Test->skip($file)
				: $Test->ok($ok, "$file contains skip comment, but problems already encountered");
			return $ok;
		}
		
		next if (/^\s*#/);
		next if (/^\s*=.+/ .. (/^\s*=(cut|back|end)/ || eof($fh)));
		last if (/^\s*(__END__|__DATA__)/);
		next if $ignoring || $ignore_line;
		
		my ($indent, $remaining) = (/^([\s\x20]*)(.*)/);
		next unless length $remaining;
		
		if ($indent =~ /\x20/)
		{
			$Test->diag("$file had space indent on line $line");
			$ok = 0;
		}
		if ($remaining =~ /\t/)
		{
			$Test->diag("$file had non-indenting tab on line $line");
			$ok = 0;
		}
		if ($remaining =~ /\s$/)
		{
			$Test->diag("$file had trailing whitespace on line $line");
			$ok = 0;
		}
		if (length($indent) - $last_indent > 1)
		{
			$Test->diag("$file had jumping indent on line $line");
			$ok = 0;
		}
		$last_indent = length $indent;
	}
	$Test->ok($ok, "whitespace for $file");
	return $ok;
}

sub all_perl_files_ok
{
	local $Test::Builder::Level = $Test::Builder::Level + 1;
	my @files = _all_perl_files( @_ );
	_make_plan();
	foreach my $file ( sort @files )
	{
		tabs_ok($file, "OK tabs in '$file'");
	}
}

sub _is_perl_module
{
	$_[0] =~ /\.pm$/i || $_[0] =~ /::/;
}

sub _is_perl_script
{
	my $file = shift;
	return 1 if $file =~ /\.pl$/i;
	return 1 if $file =~ /\.psgi$/;
	return 1 if $file =~ /\.t$/;
	open (my $fh, $file) or return;
	my $first = <$fh>;
	return 1 if defined $first && ($first =~ $PERL_PATTERN);
	return;
}

sub _module_to_path
{
	my $file = shift;
	return $file unless ($file =~ /::/);
	my @parts = split /::/, $file;
	my $module = File::Spec->catfile(@parts) . '.pm';
	foreach my $dir (@INC)
	{
		my $candidate = File::Spec->catfile($dir, $module);
		next unless (-e $candidate && -f _ && -r _);
		return $candidate;
	}
	return $file;
}

sub _make_plan
{
	unless ($Test->has_plan)
	{
		$Test->plan( 'no_plan' );
	}
	$Test->expected_tests;
}

sub _untaint
{
	my @untainted = map { ($_ =~ $UNTAINT_PATTERN) } @_;
	return wantarray ? @untainted : $untainted[0];
}

sub __silly {
	# this is just for testing really.
	print "$_\n"
	  for 1..3;  ##WS
}

## no Test::Tabs
  1;
## use Test::Tabs

__END__

=pod

=encoding utf-8

=for stopwords whitespace heredocs

=head1 NAME

Test::Tabs - check the presence of tabs in your project

=head1 SYNOPSIS

	use Test::Tabs tests => 1;
	tabs_ok('lib/Module.pm', 'Module is indented sanely');

Or

	use Test::Tabs;
	all_perl_files_ok();

Or

	use Test::Tabs;
	all_perl_files_ok( @mydirs );

=head1 DESCRIPTION

This module scans your project/distribution for any perl files (scripts,
modules, etc) for the presence of tabs.

In particular, it checks that all indentation is done using tabs, not
spaces; alignment is done via spaces, not tabs; indentation levels
never jump up (e.g. going from 1 tab indent to 3 tab indent without an
intervening 2 tab indent); and there is no trailing whitespace on any
line (though lines may consist entirely of whitespace).

Comment lines and pod are ignored. (A future version may also ignore
heredocs.)

A trailing comment C<< ##WS >> can be used to ignore all whitespace
rules for that line. C<< ## no Test::Tabs >> can be used to begin ignoring
whitespace rules for all following lines until C<< ## use Test::Tabs >> is
seen. C<< ## skip Test::Tabs >> tells Test::Tabs to skip the current file,
but it must be used I<before> the first whitespace rule violation.

=head2 Functions

=over

=item C<< all_perl_files_ok( @directories ) >>

Applies C<< tabs_ok() >> to all perl files found in C<< @directories >>
recursively. If no C<< @directories >> are given, the starting point is
one level above the current running script, that should cover all the
files of a typical CPAN distribution. A perl file is *.pl or *.pm or *.t
or a file starting with C<< #!...perl >>.

=item C<< tabs_ok( $file, $text ) >>

Run a tab check on C<< $file >>. For a module, either the path
(C<< lib/My/Module.pm >>) or the package name (C<< My::Module >>) can be
used.

C<< $text >> is the optional test name.

=back

=head1 BUGS

Please report any bugs to
L<http://rt.cpan.org/Dist/Display.html?Queue=Test-Tabs>.

=head1 SEE ALSO

L<Test::EOL>, L<Test::More>.

=head1 AUTHOR

Toby Inkster E<lt>tobyink@cpan.orgE<gt>.

Large portions stolen from L<Test::NoTabs> by Nick Gerakines.

=head1 COPYRIGHT AND LICENCE

This software is copyright (c) 2012-2013 by Toby Inkster.

This is free software; you can redistribute it and/or modify it under
the same terms as the Perl 5 programming language system itself.

=head1 DISCLAIMER OF WARRANTIES

THIS PACKAGE IS PROVIDED "AS IS" AND WITHOUT ANY EXPRESS OR IMPLIED
WARRANTIES, INCLUDING, WITHOUT LIMITATION, THE IMPLIED WARRANTIES OF
MERCHANTIBILITY AND FITNESS FOR A PARTICULAR PURPOSE.

