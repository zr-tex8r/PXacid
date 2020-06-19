#!/usr/bin/perl
# pxpjcid.pl
#
use strict;
our $xetex = "xetex -interaction=batchmode";
our $pltotf = "pltotf";
our $pltotf = "uppltotf";
our $opl2ofm = "opl2ofm";
our $ovp2ovf = "ovp2ovf";
#
our $prog_name = "pxpjcid";
our $version = "0.4.1";
our $mod_date = "2020/06/19";
our $temp_base = "__$prog_name$$";
our $gid_offset = 0;
our $avoid_notdef = 0;

##-----------------------------------------------------------
## Mapping between TeX slots and Unicode points

use Encode qw( decode );

our $tex2ucs_table = {
  'JY1' => sub {
    my ($s) = $_[0];
    my $u = ord(decode('jis0208-raw', pack('n', $s)));
    return ($u == 0xFFFD) ? undef : $u;
  },
  'JY2' => sub {
    return $_[0];
  }
};

# tex2ucs($enc, $tc)
sub tex2ucs {
  my ($enc, $tc) = @_;
  return $tex2ucs_table->{$enc}($tc);
}

##----------------------------------------------------------
## Mapping from Unicode to AJ1 CID

our $ucs2aj_table;
{
  local ($/, $_); my (%t);
  $_ = <DATA>; %t = eval($_);
  for (0x3400 .. 0x4DBF) { $t{$_} = 0; }
  for (0x4E00 .. 0x9FFF) { $t{$_} = 0; }
  for (0xF900 .. 0xFAFF) { $t{$_} = 0; }
  $ucs2aj_table = \%t;
}

## ucs2aj($uc)
sub ucs2aj {
  my $t = $ucs2aj_table->{$_[0]};
  return ($t) ? ($t + $gid_offset) : $t;
}

our $target_ucs;
our $target_aj;
sub gen_target_list {
  $target_ucs = [ sort { $a <=> $b } (keys %$ucs2aj_table) ];
  my %chk = reverse %$ucs2aj_table;
  $target_aj = [ map { $_ + $gid_offset }
      (sort { $a <=> $b } (keys %chk)) ];
}

our $enc_list = [ keys %$tex2ucs_table ];

##----------------------------------------------------------
## Retrieval of glyph metric by means of XeTeX

# get_metric($font, $index, $chars)
sub get_metric {
  my ($font, $index, $chars) = @_;
  write_whole("$temp_base.tex", query_xetex($font, $index, $chars), 1);
  if (-s "$prog_name-save.log") {
    my $t = read_whole("$prog_name-save.log", 1);
    write_whole("$temp_base.log", $t, 1);
  } else {
    system "$xetex $temp_base";
  }
  (-s "$temp_base.log")
    or error("XeTeX execution failed");
  my $lin; my $par = {};
  open(my $hi, '<', "$temp_base.log")
    or error("cannot read file", "$temp_base.log");
  while ($lin = <$hi>) {
    if ($lin =~ m/^! /) {
      error("error occurred in XeTeX process");
    } elsif ($lin =~ m/^!OUT!(.*)$/) {
      nest_assign($par, $1);
    }
  }
  ($avoid_notdef) and purge_notdefish($par);
  close($hi);
  #
  derive_param($par);
  return $par;
}

# nest_assign($base, $text)
sub nest_assign {
  my ($base, $text) = @_;
  my ($pname, $value) = ($text =~ m/^(.*)=(.*)$/) or die;
  my @plist = split(m/:/, $pname);
  if ($value =~ m/^(-?\d+\.\d+)pt$/) {
    $value = $1 / 10;
  }
  nest_assign_sub($base, \@plist, $value);
}
sub nest_assign_sub {
  my ($hash, $plist, $value) = @_;
  my ($name, @plist1) = @$plist;
  if (!@plist1) {
    $hash->{$name} = $value;
  } else {
    (exists $hash->{$name}) or $hash->{$name} = {};
    nest_assign_sub($hash->{$name}, \@plist1, $value);
  }
}

# query_xetex($font, $index, $chars)
sub query_xetex {
  my ($font, $index, $chars) = @_; my ($t);
  (defined $index) and $font = "$font:$index";
  local $_ = <<'END';
\font\fontU="[?FONT?]"
\newcount\cntC
\newcount\cntM
\newbox\boxA
\def\writeLog#1{\immediate\write-1{#1}}
\def\outData#1{\writeLog{!OUT!#1}}
\def\doForEachAj{\do{0}?DO_AJ?}
\def\getMetricAj#1#2{%
  #1\def\pname{#2}\cntM=\XeTeXcountglyphs\font
  \let\do\doGetMetricAj \doForEachAj}
\def\doGetMetricAj#1{%
  \cntC=#1
  \ifnum\cntC<\cntM
    \setbox\boxA=\hbox{\XeTeXglyph\cntC}%
    \outData{\pname:#1:wd=\the\wd\boxA}%
    \outData{\pname:#1:ht=\the\ht\boxA}%
    \outData{\pname:#1:dp=\the\dp\boxA}%
  \fi}
\getMetricAj\fontU{aj}
\bye
END
  s/%%.*$/%/gm; s/\?FONT\?/$font/g;
  $t = do_list($target_aj); s/\?DO_AJ\?/$t/g;
  return $_;
}

# do_list($vals)
sub do_list {
  my ($vals) = @_;
  return join("%\n", map { "\\do{$_}" } (@$vals));
}

# purge_notdefish($par)
sub purge_notdefish {
  my ($par) = @_;
  my $aj = $par->{aj};
  local $_ = $aj->{0}; (defined $_) or die;
  my ($wd, $ht, $dp) = ($_->{wd}, $_->{ht}, $_->{dp});
  foreach my $gc (keys %$aj) {
    $_ = $aj->{$gc};
    if ($wd == $_->{wd} && $ht == $_->{ht} && $dp == $_->{dp}) {
      delete $aj->{$gc};
    }
  }
}

# derive_param($par)
sub derive_param {
  my ($par) = @_; my ($cc);
  # xheight
  (defined($cc = ucs2aj(ord('x'))) &&
   defined($par->{xheight} = $par->{aj}{$cc}{ht}))
    or $par->{xheight} = 0.5;
  # capheight
  (defined($cc = ucs2aj(ord('I'))) &&
   defined($par->{capheight} = $par->{aj}{$cc}{ht}))
    or $par->{capheight} = 0.75;
  # ascheight
  (defined($cc = ucs2aj(ord('h'))) &&
   defined($par->{ascheight} = $par->{aj}{$cc}{ht}))
    or $par->{ascheight} = 0.75;
  # space
  (defined($cc = ucs2aj(ord(' '))) &&
   defined($par->{space} = $par->{aj}{$cc}{wd}))
    or $par->{space} = 0.5;
}

##----------------------------------------------------------
## Generating TeX metric files

use constant { STDHT => 0.88, STDDP => 0.12 };

# source_opl($par, $fam)
sub source_opl {
  my ($par, $fam) = @_;
  my @cnks = (<<"END");
(OFMLEVEL H 0)
(FAMILY $fam)
(CODINGSCHEME )
(FONTDIMEN
   (XHEIGHT R 1.0)
   (QUAD R 1.0)
   )
END
  my $paraj = $par->{aj};
  foreach my $cc (@$target_aj) {
    my $t = $paraj->{$cc};
    (defined $t) or next;
    my ($wd, $ht, $dp) = ($t->{wd}, $t->{ht}, $t->{dp});
    push(@cnks, <<"END");
(CHARACTER H @{[FH($cc)]}
   (CHARWD R @{[FR($wd)]})
   (CHARHT R @{[FR($ht)]})
   (CHARDP R @{[FR($dp)]})
   )
END
  }
  return join('', @cnks);
}
# source_virtual()
sub source_virtual {
  my ($par, $fam, $ser, $enc, $tfmfam, $wdp) = @_;
  my (%rwd, @rwd, @rct);
  if ($wdp) { info("width precision set to $wdp"); }
  # OVP CHARACTER
  my (@pccnks, @ptcnks, @vccnks, @valid);
  my ($stc, $etc) = tc_range($enc);
  foreach my $tc ($stc .. $etc) {
    my $uc = tex2ucs($enc, $tc) or next;
    my $dat = resolve_map($uc, $par, $tc, $wdp);
    #$valid[$tc] = 1; $ctchar += 1;
    my ($map, $wd, $ht, $dp, $rdwd) = @$dat;
    if (@$map) {
      $map = join("\n", map { "      $_" } (@$map));
      $map = "   (MAP\n$map\n      )";
    } else { $map = "   (MAP)"; }
    push(@vccnks, <<"END");
(CHARACTER H @{[FH($tc)]}
   (CHARWD R @{[FR($rdwd)]})
$map
   )
END
    # PL
    if ($rdwd != 1.0) {
      push(@{$rwd{$rdwd}}, $tc);
    }
  }

  # 
  {
    my @w = sort { $a <=> $b } (keys %rwd);
    my $nct = scalar(@w);
    if ($nct > 250) {
      info("Char type limit exceeded ($nct > 250)");
      return;
    }
    foreach (0 .. $#w) {
      $rwd[$_ + 1] = [$w[$_], $rwd{$w[$_]}];
    }
    $rwd[0] = [1.0];
  }

  foreach my $ct (0 .. $#rwd) {
    (defined $rwd[$ct]) or die;
    my ($wd, $cs) = @{$rwd[$ct]};
    push(@ptcnks, <<"END");
(TYPE D $ct
   (CHARWD R @{[FR($wd)]})
   (CHARHT R @{[FR(STDHT)]})
   (CHARDP R @{[FR(STDDP)]})
   )
END
    if (defined $cs) {
      push(@pccnks, "(CHARSINTYPE D $ct\n");
      foreach my $uc (@$cs) {
        push(@pccnks, sprintf("U%04X\n", $uc));
      }
      push(@pccnks, "   )\n");
    }
  }

  # PL LIGTABLE
  my @lkcnks = ();
  push(@lkcnks, "(LABEL D 5)", "(KRN D 5 R 0.0)", "(STOP)");
  @lkcnks = map { "   $_\n" } (@lkcnks);

  # entire OVP
  my $rjfmname = fontname($tfmfam, $ser, $enc, 1);
  my $ofmname = fontname($tfmfam, $ser, 'J40');
  my $ovp = join('', <<"END", @vccnks);
(OFMLEVEL H 0)
(VTITLE $fam)
(FAMILY $fam)
(FONTDIMEN
   (QUAD R 1.0)
   (XHEIGHT R 1.0)
   )
(MAPFONT D 0
   (FONTNAME $rjfmname)
   )
(MAPFONT D 1
   (FONTNAME $ofmname)
   )
END

  # entire PL
  my $space = $par->{space};
  my $xheight = $par->{xheight};
  my $slant = 0;
  my $pl = join('', <<"END1", @lkcnks, <<"END2", @pccnks, @ptcnks);
(FAMILY $fam)
(CODINGSCHEME )
(FONTDIMEN
   (SLANT R 0.0)
   (SPACE R 0.0)
   (STRETCH R 0.06)
   (SHRINK R 0.0)
   (XHEIGHT R 1.0)
   (QUAD R 1.0)
   (EXTRASPACE R 0.12)
   (EXTRASTRETCH R 0.06)
   (EXTRASHRINK R 0.03)
   )
(GLUEKERN
END1
   )
END2

  # done
  return ($pl, $ovp);
}

sub resolve_map {
  my ($uc, $par, $tc, $wdp) = @_;
  my $paraj = $par->{aj};
  {
    my $cc = ucs2aj($uc) or last;
    my $t = $paraj->{$cc} or last;
    my $wd = $t->{wd}; my $rdwd = $wd;
    if ($wdp) {
      $rdwd = int($wd / $wdp + 0.5) * $wdp;
    }
    return [ [ "(SELECTFONT D 1)", "(SETCHAR H @{[FH($cc)]})" ],
             $wd, $t->{ht}, $t->{dp}, $rdwd ];
  }
  return [ [ "(SETCHAR H @{[FH($tc)]})" ],
           1.0, STDHT, STDDP, 1.0 ];
}

sub standard_pl {
  return <<'END';
(FAMILY )
(CODINGSCHEME )
(FONTDIMEN
   (SLANT R 0.0)
   (SPACE R 0.0)
   (STRETCH R 0.0)
   (SHRINK R 0.0)
   (XHEIGHT R 1.0)
   (QUAD R 1.0)
   (EXTRASPACE R 0.0)
   (EXTRASTRETCH R 0.0)
   (EXTRASHRINK R 0.0)
   )
(TYPE O 0
   (CHARWD R 1.0)
   (CHARHT R 0.9)
   (CHARDP R 0.1)
   )
END
}

# FR($value)
sub FR {
  local $_ = sprintf("%.7f", $_[0]); s/0+$/0/; return $_;
}
# FH($value)
sub FH {
  return sprintf("%X", $_[0]);
}

# tc_range($enc)
our $range = {
  'JY1' => [ 0x2121, 0x7E7E ],
  'JY2' => [ 0x0, 0xFFFF ],
};
sub tc_range { return @{$range->{$_[0]}}; }

# standard_cmap($enc)
our $std_cmap = {
  'JY1' => "H",
  'JY2' => "UniJIS-UTF16-H",
};
sub standard_cmap { return $std_cmap->{$_[0]}; }

# use_berry($sw)
sub use_berry { } # no-pp

# NFSS series -> Berry
our $ser_kb = {
  ul => 'a',  # UltraLight
  el => 'j',  # ExtraLight
  l  => 'l',  # Light
  dl => 'dl', # DemiLight (NON-STANDARD)
  r  => 'r',  # Regular
  m  => 'r',  # Regular
  mb => 'm',  # Medium
  db => 'd',  # DemiBold
  sb => 's',  # SemiBold
  b  => 'b',  # Bold
  bx => 'b',  # Bold
  eb => 'x',  # ExtraBold
  h  => 'h',  # Heavy
  eh => 'xh', # ExtraHeavy (NON-STANDARD)
  ub => 'u',  # Ultra
  uh => 'uh'  # UltraHeavy (NON-STANDARD)
};
# counterpart
our $enc_tate = {
  JY1 => 'JT1', JY2 => 'JT2'
};
# fontname($tfmfam, $ser, $enc, $raw)
sub fontname {
  my ($tfmfam, $ser, $enc, $raw) = @_;
  $raw = ($raw) ? "r-" : "";
  $ser = $ser_kb->{$ser};
  $enc = lc($enc);
  return "$raw$tfmfam-$ser-$enc";
}

##----------------------------------------------------------
## LaTeX font definition files

# set_scale($scale)
our $scale = 0.924715;
sub set_scale {
  $scale = $_[0] if (defined $_[0]);
}

# source_fd($fam, $ser, $enc, $tfmfam, $orgsrc)
sub source_fd {
  my ($fam, $ser, $enc, $tfmfam, $orgsrc) = @_;
  my (%spec, @pos, $ser1, $text);
  my $tenc = $enc_tate->{$enc} or die;
  my $rx = qr/^\\DeclareFontShape\{$enc\}\{$fam\}
              \{(\w+)\}\{n\}\{<->(?:s\*\[[\d\.]+\])(.*?)\}/x;
  # parse original
  foreach my $lin (split(m/\n/, $orgsrc)) {
    if (($ser1, $text) = $lin =~ $rx) {
      push(@pos, $ser1);
      $spec{$ser1} = ($text =~ m/^ssub\*/) ? undef : $text;
    }
  }
  if (!@pos) {
    foreach $ser1 ('m', 'b', 'bx') {
      push(@pos, $ser1); $spec{$ser1} = undef;
    }
  }
  if (!exists $spec{$ser}) { push(@pos, $ser); }
  $spec{$ser} = fontname($tfmfam, $ser, $enc);
  #
  my ($mdser, $bfser);
  foreach my $ent (@pos) {
    (defined $spec{$ent}) or next;
    (defined $mdser) or ($mdser) = $ent =~ m|^([mr])$/|;
    (defined $bfser) or ($bfser) = $ent =~ m|^(bx?)$/|;
  }
  # generate new
  my (@cnks, $text, @cnkst, $textt);
  foreach $ser1 (@pos) {
    if (defined $spec{$ser1}) {
      $text = "s*[$scale]" . $spec{$ser1};
    } else {
      my $ser2 = ($mdser && $ser1 =~ m/^[mr]$/) ? $mdser :
                 ($bfser && $ser1 =~ m/^bx?$/) ? $bfser :
                 ($ser1 eq 'm') ? $ser : 'm';
      $text = "ssub*$fam/$ser2/n";
    }
    my $text2 = "ssub*$fam/$ser1/n";
    my $text3 = "ssub*mc/m/n";
    push(@cnks,
      "\\DeclareFontShape{$enc}{$fam}{$ser1}{n}{<->$text}{}",
      "\\DeclareFontShape{$enc}{$fam}{$ser1}{it}{<->$text2}{}",
      "\\DeclareFontShape{$enc}{$fam}{$ser1}{sl}{<->$text2}{}");
    push(@cnkst,
      "\\DeclareFontShape{$tenc}{$fam}{$ser1}{n}{<->$text3}{}",
      "\\DeclareFontShape{$tenc}{$fam}{$ser1}{it}{<->$text3}{}",
      "\\DeclareFontShape{$tenc}{$fam}{$ser1}{sl}{<->$text3}{}");
  }
  $text = join("\n", @cnks);
  $textt = join("\n", @cnkst);
  # 
  my $fdname = lc("$enc$fam");
  my $tfdname = lc("$tenc$fam");
  return (<<"END1", <<"END2");
% $fdname.fd
\\DeclareFontFamily{$enc}{$fam}{}
$text
%% EOF
END1
% $tfdname.fd
\\DeclareFontFamily{$tenc}{$fam}{}
$textt
%% EOF
END2
}

##----------------------------------------------------------
## dvipdfmx map files

# source_map($fam, $ser, $tfmfam, $font, $index, $orgsrc, $encset)
sub source_map {
  my ($fam, $ser, $tfmfam, $font, $index, $orgsrc, $encset) = @_;
  (defined $index) and $font = ":$index:$font";
  my @spec;
  foreach my $lin (split(m/\n/, $orgsrc)) {
    if ($lin !~ m/^\s*(\#|$)/) {
      push(@spec, $lin);
    }
  }
  my $ofmname = fontname($tfmfam, $ser, 'J40');
  push(@spec, "$ofmname  Identity-H  $font");
  foreach my $enc (@$encset) {
    my $rjfmname = fontname($tfmfam, $ser, $enc, 1);
    my $cmap = standard_cmap($enc);
    push(@spec, "$rjfmname  $cmap  $font");
  }
  my $text = join("\n", @spec);
  return <<"END";
# pdfm-$fam.map
$text
# EOF
END
}

##----------------------------------------------------------
## LaTeX style files

# source_style($font)
sub source_style {
  my ($fam) = @_; local ($_);
  $_ = <<'END';
% pxpjcid-?FAM?.sty
\NeedsTeXFormat{pLaTeX2e}
\ProvidesPackage{pxpjcid-?FAM?}
\DeclareRobustCommand*{\?FAM?family}{%
  \not@math@alphabet\?FAM?family\relax
  \fontfamily{?FAM?}\selectfont}
\DeclareTextFontCommand{\text?FAM?}{\?FAM?family}
% EOF
END
  s/\?FAM\?/$fam/g;
  return $_;
}

my $testtext; # My hovercraft is full of eels.
{
  my $src = <<'EOT';
E7A781E381AEE3839BE38390E383BCE382AFE383
A9E38395E38388E381AFE9B0BBE381A7E38184E3
81A3E381B1E38184E381A7E38199E38082
EOT
  $src =~ s/\s//g; $testtext = pack('H*', $src);
}

# source_test($fam, $ser)
sub source_test {
  my ($fam, $ser) = @_; local ($_);
  $_ = <<'END';
\documentclass[a4paper]{jsarticle}
\AtBeginDvi{\special{pdf:mapfile pdfm-?FAM?}}
\usepackage{pxpjcid-?FAM?}
\begin{document}
\?FAM?family\kanjiseries{?SER?}\selectfont
?TEXT?
\end{document}
END
  s/\?FAM\?/$fam/g; s/\?SER\?/$ser/g;
  s/\?TEXT\?/$testtext/g;
  return "\xEF\xBB\xBF" . $_; # BOM added
}

##----------------------------------------------------------
## Main

# append_mode($value)
our $append_mode;
sub append_mode { $append_mode = $_[0]; }

# save_source($value)
our $save_source;
sub save_source { $save_source = $_[0]; }

# generate($font, $fam, $enclist)
sub generate {
  my ($font, $fam, $ser, $tfmfam, $index) = @_;
  #
  my $par = get_metric($font, $index, $target_ucs);
  #
  my $ofmname = fontname($tfmfam, $ser, 'J40');
  info("Process for $ofmname...");
  write_whole("$ofmname.opl", source_opl($par, $fam), 1);
  system("$opl2ofm $ofmname.opl $ofmname.ofm");
  (-s "$ofmname.ofm")
    or error("failed in converting OPL -> OFM", "$ofmname.ofm");
  if (!$save_source) { unlink("$ofmname.opl"); }
  #
  my @encset = ('JY1', 'JY2');
  foreach my $enc (@encset) {
    #
    my $vfname = fontname($tfmfam, $ser, $enc);
    info("Process for $vfname...");
    my ($pl, $ovp, $wdpd);
    while (!defined $pl) {
      ($pl, $ovp) = source_virtual($par, $fam, $ser, $enc, $tfmfam,
          (defined $wdpd) ? (1 / $wdpd) : undef);
      $wdpd = (defined $wdpd) ? ($wdpd / 2) : 8192;
    }
    write_whole("$vfname.pl", $pl, 1);
    system("$pltotf $vfname.pl $vfname.tfm");
    (-s "$vfname.tfm")
      or error("failed in converting PL -> TFM", "$vfname.tfm");
    write_whole("$vfname.ovp", $ovp, 1);
    #
    system("$ovp2ovf $vfname.ovp $vfname.ovf $temp_base.ofm");
    unlink("$vfname.vf"); rename("$vfname.ovf", "$vfname.vf");
    (-s "$vfname.vf")
      or error("failed in converting OPL -> VF", "$vfname.vf");
    if (!$save_source) { unlink("$vfname.pl", "$vfname.ovp"); }
    # (raw)
    my $rjfmname = fontname($tfmfam, $ser, $enc, 1);
    write_whole("$rjfmname.pl", standard_pl(), 1);
    system("$pltotf $rjfmname.pl $rjfmname.tfm");
    unlink("$rjfmname.pl");
    #
    my $orgfd; my $tenc = $enc_tate->{$enc} or die;
    my $fdname = lc("$enc$fam");
    my $tfdname = lc("$tenc$fam");
    if ($append_mode && -f "$fdname.fd") {
      $orgfd = read_whole("$fdname.fd");
    }
    my ($fd, $tfd) = source_fd($fam, $ser, $enc, $tfmfam, $orgfd);
    write_whole("$fdname.fd", $fd);
    write_whole("$tfdname.fd", $tfd);
  }
  #
  my $mapname = "pdfm-$fam"; my $orgmap;
  if ($append_mode && -f "$mapname.map") {
    $orgmap = read_whole("$mapname.map");
  }
  my $map = source_map($fam, $ser, $tfmfam, $font, $index, $orgmap, \@encset);
  write_whole("$mapname.map", $map);
  #
  my $styname = "pxpjcid-$fam";
  my $sty = source_style($fam);
  if (!$append_mode) { write_whole("$styname.sty", $sty); }
  my $texname = "pxpjcid-test-$fam-$ser";
  my $tex = source_test($fam, $ser);
  write_whole("$texname.tex", $tex);
}

#-----------------------------------------------------------

# main()
sub main {
  my $prop = read_option();
  (defined $prop->{gid_offset}) and $gid_offset = $prop->{gid_offset};
  append_mode($prop->{append});
  use_berry($prop->{use_berry});
  save_source($prop->{save_source});
  set_scale($prop->{scale});
  (defined $prop->{avoidnotdef}) and $avoid_notdef = 1;
  (defined $prop->{debug}) and apply_debug($prop->{debug});
  gen_target_list();
  generate($prop->{font}, $prop->{family}, $prop->{series},
    $prop->{tfm_family}, $prop->{index});
}

our $debug_proc = {
  savelog => sub {
    save_log(1);
  },
};

# apply_debug($names)
sub apply_debug {
  foreach (@{$_[0]}) {
    if (exists $debug_proc->{$_}) {
      $debug_proc->{$_}();
    } else {
      info("WARNING: no such debug process '$_'");
    }
  }
}

# read_option()
sub read_option {
  my $prop = {};
  if (!@ARGV) { show_usage(); exit; }
  while ($ARGV[0] =~ m/^-/) {
    my $opt = shift(@ARGV); my $arg;
    if ($opt =~ m/^--?h(elp)?/) {
      show_usage(); exit;
    } elsif ($opt eq '-a' || $opt eq '--append') {
      $prop->{append} = 1;
    } elsif ($opt eq '-b' || $opt eq '--use-berry') {
      $prop->{use_berry} = 1;
    } elsif ($opt eq '-s' || $opt eq '--save-source') {
      $prop->{save_source} = 1;
    } elsif ($opt eq '--save-log') {
      error("option '--save-log' is abolished (use --debug=savelog)");
    } elsif ($opt eq '--avoid-notdef') {
      $prop->{avoidnotdef} = 1;
    } elsif (($arg) = $opt =~ m/^-(?:t|-tfm-family)(?:=(.*))?$/) {
      (defined $arg) or $arg = shift(@ARGV);
      ($arg =~ m/^[a-z0-9]+$/) or error("bad family name", $arg);
      $prop->{tfm_family} = $arg;
    } elsif (($arg) = $opt =~ m/^--scale(?:=(.*))?$/) {
      (defined $arg) or $arg = shift(@ARGV);
      ($arg =~ m/^[.0-9]+$/ && 0 <= $arg && $arg < 10)
        or error("bad scale value", $arg);
      $prop->{scale} = $arg;
    } elsif (($arg) = $opt =~ m/^--gid-offset(?:=(.*))?$/) {
      (defined $arg) or $arg = shift(@ARGV);
      ($arg =~ m/^[0-9]+$/) or error("bad gid-offset value", $arg);
      $prop->{gid_offset} = $arg;
    } elsif (($arg) = $opt =~ m/^-(?:i|-index)(?:=(.*))?$/) {
      (defined $arg) or $arg = shift(@ARGV);
      ($arg =~ m/^[0-9]+$/) or error("bad TTC index value", $arg);
      $prop->{index} = $arg;
    } elsif (($arg) = $opt =~ m/^--debug(?:=(.*))?$/) {
      (defined $arg && $arg ne '') or error("missing argument", $opt);
      $prop->{debug} = [split(m/,/, $arg)];
    } else {
      error("invalid option", $opt);
    }
  }
  ($#ARGV == 1) or error("wrong number of command arguments");
  my ($fam, $ser) = ($ARGV[0] =~ m|^(.*?)/(.*)$|) ?
       ($1, $2) : ($ARGV[0], 'm');
  ($fam =~ m/^[a-z]+$/) or error("bad family name", $fam);
  ($ser =~ m/^[a-z]+$/) or error("bad series name", $ser);
  (exists $ser_kb->{$ser}) or error("unknown series name", $ser);
  $prop->{family} = $fam; $prop->{series} = $ser;
  $prop->{font} = $ARGV[1];
  (defined $prop->{tfm_family})
    or $prop->{tfm_family} = $prop->{family};
  return $prop;
}

# show_usage()
sub show_usage {
  print <<"END";
This is $prog_name v$version <$mod_date> by 'ZR'.
Usage: $prog_name [<option>...] <family>[/<series>] <font_file>
  <family>    LaTeX family name to designate the font
  <series>    LaTeX series name to designate the font
  <font_file> file name of the target font (NOT font name); the file
              must be put in the location Kpathsea can find
Options are:
  -a / --append             append mode (for .fd & .map)
  -t / --tfm-family=<name>  font family name used in tfm names
  -s / --save-source        save PL/OPL/OVP files
       --scale              scale value
       --gid-offset=<val>   offset between CID and GID
       --avoid-notdef       avoid glyphs that seem like notdef
END
}

# info($msg, ...)
sub info {
  print STDERR (join(": ", $prog_name, @_), "\n");
}

# error($msg, ...)
sub error {
  print STDERR (join(": ", $prog_name, @_), "\n");
  exit(-1);
}

# max($x, $y)
sub max {
  return ($_[0] > $_[1]) ? $_[0] : $_[1];
}

# save_log($value)
our $save_log;
sub save_log { $save_log = $_[0]; }

# write_whole($name, $dat, $bin)
sub write_whole {
  my ($name, $dat, $bin) = @_;
  open(my $ho, '>', $name)
    or error("cannot create file", $name);
  if ($bin) { binmode($ho); }
  print $ho ($dat);
  close($ho);
}

# read_whole($name, $bin)
sub read_whole {
  my ($name, $bin) = @_; local ($/);
  open(my $hi, '<', $name)
    or error("cannot open file for input", $name);
  if ($bin) { binmode($hi); }
  my $dat = <$hi>;
  close($hi);
  return $dat;
}

END {
  if ($save_log) {
    unlink("$prog_name-save.log");
    rename("$temp_base.log", "$prog_name-save.log");
  }
  unlink("$temp_base.tex", "$temp_base.log", "$temp_base.ofm");
}

#-----------------------------------------------------------
main();
__DATA__
(
0,1,
1,1,
2,1,
3,1,
4,1,
5,1,
6,1,
7,1,
8,1,
9,1,
10,1,
11,1,
12,1,
13,1,
14,1,
15,1,
16,1,
17,1,
18,1,
19,1,
20,1,
21,1,
22,1,
23,1,
24,1,
25,1,
26,1,
27,1,
28,1,
29,1,
30,1,
31,1,
32,1,
33,2,
34,3,
35,4,
36,5,
37,6,
38,7,
39,8,
40,9,
41,10,
42,11,
43,12,
44,13,
45,14,
46,15,
47,16,
48,17,
49,18,
50,19,
51,20,
52,21,
53,22,
54,23,
55,24,
56,25,
57,26,
58,27,
59,28,
60,29,
61,30,
62,31,
63,32,
64,33,
65,34,
66,35,
67,36,
68,37,
69,38,
70,39,
71,40,
72,41,
73,42,
74,43,
75,44,
76,45,
77,46,
78,47,
79,48,
80,49,
81,50,
82,51,
83,52,
84,53,
85,54,
86,55,
87,56,
88,57,
89,58,
90,59,
91,60,
92,97,
93,62,
94,63,
95,64,
96,65,
97,66,
98,67,
99,68,
100,69,
101,70,
102,71,
103,72,
104,73,
105,74,
106,75,
107,76,
108,77,
109,78,
110,79,
111,80,
112,81,
113,82,
114,83,
115,84,
116,85,
117,86,
118,87,
119,88,
120,89,
121,90,
122,91,
123,92,
124,99,
125,94,
126,100,
160,1,
161,101,
162,102,
163,103,
164,107,
165,61,
166,93,
167,106,
168,132,
169,152,
170,140,
171,109,
172,153,
174,154,
175,129,
176,155,
177,156,
178,157,
179,158,
180,127,
181,159,
182,118,
183,117,
184,134,
185,160,
186,144,
187,123,
188,161,
189,162,
190,163,
191,126,
192,164,
193,165,
194,166,
195,167,
196,168,
197,169,
198,139,
199,170,
200,171,
201,172,
202,173,
203,174,
204,175,
205,176,
206,177,
207,178,
208,179,
209,180,
210,181,
211,182,
212,183,
213,184,
214,185,
215,186,
216,142,
217,187,
218,188,
219,189,
220,190,
221,191,
222,192,
223,150,
224,193,
225,194,
226,195,
227,196,
228,197,
229,198,
230,145,
231,199,
232,200,
233,201,
234,202,
235,203,
236,204,
237,205,
238,206,
239,207,
240,208,
241,209,
242,210,
243,211,
244,212,
245,213,
246,214,
247,215,
248,148,
249,216,
250,217,
251,218,
252,219,
253,220,
254,221,
255,222,
256,9366,
257,9361,
258,15756,
259,15769,
260,15737,
261,15745,
262,15758,
263,15771,
264,15783,
265,15789,
266,20333,
267,20352,
268,15759,
269,15772,
270,15761,
271,15774,
272,20322,
273,15775,
274,9369,
275,9364,
278,20334,
279,20353,
280,15760,
281,15773,
282,9395,
283,9407,
284,15784,
285,15790,
286,20335,
287,20355,
288,20337,
289,20356,
290,20336,
292,15785,
293,15791,
294,20323,
295,15816,
296,9400,
297,9412,
298,9367,
299,9362,
302,20339,
303,20357,
304,20338,
305,146,
306,20324,
307,20328,
308,15786,
309,15792,
310,20340,
311,20358,
312,20329,
313,15757,
314,15770,
315,20342,
316,20360,
317,15739,
318,15747,
319,20325,
320,20330,
321,141,
322,147,
323,15762,
324,15776,
325,20343,
326,20361,
327,15763,
328,15777,
329,20331,
330,20326,
331,9436,
332,9370,
333,9365,
336,15764,
337,15778,
338,143,
339,149,
340,15755,
341,15768,
342,20344,
343,20362,
344,15765,
345,15779,
346,15740,
347,15748,
348,15787,
349,15793,
350,15741,
351,15750,
352,223,
353,227,
354,15767,
355,15781,
356,15742,
357,15751,
358,20327,
359,20332,
360,9405,
361,9417,
362,9368,
363,9363,
364,15788,
365,15794,
366,9404,
367,9416,
368,15766,
369,15780,
370,20345,
371,20363,
372,20350,
373,20364,
374,20351,
375,20365,
376,224,
377,15743,
378,15752,
379,15744,
380,15754,
381,225,
382,229,
402,105,
403,15826,
450,15821,
461,9394,
462,9406,
463,9398,
464,9410,
465,9401,
466,9413,
467,9403,
468,9415,
469,20349,
470,15733,
471,20346,
472,15734,
473,20348,
474,15735,
475,20347,
476,15736,
501,20354,
504,15731,
505,15732,
509,9421,
567,9435,
592,15832,
593,9418,
594,15836,
595,15822,
596,9423,
597,15841,
598,15802,
599,15823,
600,15829,
601,9426,
602,9429,
603,9432,
604,15830,
606,15831,
607,15809,
608,15825,
609,15813,
610,15883,
611,15884,
612,15835,
613,15838,
614,15819,
615,15844,
616,15827,
618,15885,
620,15798,
621,15808,
622,15799,
623,15833,
624,15814,
625,15795,
626,15810,
627,15803,
628,15886,
629,9437,
630,15887,
632,15888,
633,15800,
634,15843,
635,15807,
637,15804,
638,15797,
640,15889,
641,15815,
642,15805,
643,9442,
644,15824,
648,15801,
649,15828,
650,15834,
651,15796,
652,9438,
653,15837,
654,15812,
655,15890,
656,15806,
657,15842,
658,9441,
660,15818,
661,15817,
664,15820,
665,15891,
668,15892,
669,15811,
671,15893,
673,15840,
674,15839,
688,15894,
690,15895,
695,15896,
699,98,
700,96,
705,15897,
710,128,
711,15749,
712,15846,
716,15847,
720,9443,
721,15848,
728,15738,
729,15782,
730,133,
731,15746,
732,95,
733,15753,
734,15867,
736,15898,
737,15899,
741,15851,
742,15852,
743,15853,
744,15854,
745,15855,
768,65,
769,127,
770,128,
771,95,
772,129,
773,226,
774,130,
775,131,
776,132,
778,133,
779,135,
780,137,
783,15850,
792,15874,
793,15875,
794,15879,
796,15861,
797,15872,
798,15873,
799,15862,
800,15863,
804,15868,
805,15858,
807,134,
808,136,
809,15865,
810,15876,
812,15859,
815,15866,
816,15869,
818,64,
820,15871,
822,138,
825,15860,
826,15877,
827,15878,
828,15870,
829,15864,
865,15845,
900,20317,
901,20318,
937,9355,
956,159,
7742,15729,
7743,15730,
7868,9397,
7869,9409,
8048,9420,
8049,9419,
8050,9434,
8051,9433,
8194,1,
8195,1,
8208,14,
8209,14,
8210,114,
8211,114,
8212,138,
8213,138,
8214,666,
8216,98,
8217,96,
8218,120,
8220,108,
8221,122,
8222,121,
8224,115,
8225,116,
8226,119,
8229,669,
8230,124,
8240,125,
8242,9356,
8243,9357,
8249,110,
8250,111,
8251,734,
8254,226,
8255,15849,
8260,104,
8304,9377,
8308,9378,
8309,9379,
8310,9380,
8311,9381,
8312,9382,
8313,9383,
8320,9384,
8321,9385,
8322,9386,
8323,9387,
8324,9388,
8325,9389,
8326,9390,
8327,9391,
8328,9392,
8329,9393,
8364,9354,
8451,15461,
8463,15514,
8482,228,
8486,9355,
8487,15515,
8494,20366,
8501,15513,
8531,9375,
8532,9376,
8533,15727,
8539,9371,
8540,9372,
8541,9373,
8542,9374,
8592,737,
8593,738,
8594,736,
8595,739,
8596,15511,
8644,8310,
8645,8311,
8646,8309,
8658,15482,
8660,15483,
8678,8013,
8679,8012,
8680,8014,
8681,8011,
8704,15484,
8706,15493,
8707,15485,
8709,15477,
8710,20367,
8711,15494,
8712,15464,
8713,15476,
8714,15900,
8715,15465,
8719,20368,
8721,15901,
8722,151,
8723,15512,
8729,117,
8730,15499,
8733,15501,
8734,15459,
8735,15881,
8736,15491,
8741,15489,
8742,15490,
8743,15480,
8744,15481,
8745,15471,
8746,15470,
8747,15503,
8748,15504,
8749,15902,
8750,15880,
8756,15460,
8757,15502,
8764,100,
8765,15500,
8771,15506,
8773,15507,
8776,15508,
8786,15496,
8800,15456,
8801,15495,
8802,15505,
8804,20369,
8805,20370,
8806,15457,
8807,15458,
8810,15497,
8811,15498,
8818,15903,
8819,15904,
8822,15509,
8823,15510,
8834,15468,
8835,15469,
8836,15472,
8837,15473,
8838,15466,
8839,15467,
8842,15474,
8843,15475,
8853,15486,
8854,15487,
8855,15488,
8856,15905,
8862,15906,
8864,15907,
8869,15492,
8895,15882,
8922,15725,
8923,15726,
8965,15478,
8966,15479,
8984,15728,
9115,12143,
9116,12167,
9117,12144,
9118,12145,
9119,12167,
9120,12146,
9121,12151,
9122,12167,
9123,12152,
9124,12153,
9125,12167,
9126,12154,
9127,8178,
9128,8179,
9129,8180,
9130,12167,
9131,8174,
9132,8175,
9133,8176,
9136,16312,
9137,16313,
9472,7479,
9473,7480,
9474,7481,
9475,7482,
9476,7483,
9477,7484,
9478,7485,
9479,7486,
9480,7487,
9481,7488,
9482,7489,
9483,7490,
9484,7491,
9485,7492,
9486,7493,
9487,7494,
9488,7495,
9489,7496,
9490,7497,
9491,7498,
9492,7499,
9493,7500,
9494,7501,
9495,7502,
9496,7503,
9497,7504,
9498,7505,
9499,7506,
9500,7507,
9501,7508,
9502,7509,
9503,7510,
9504,7511,
9505,7512,
9506,7513,
9507,7514,
9508,7515,
9509,7516,
9510,7517,
9511,7518,
9512,7519,
9513,7520,
9514,7521,
9515,7522,
9516,7523,
9517,7524,
9518,7525,
9519,7526,
9520,7527,
9521,7528,
9522,7529,
9523,7530,
9524,7531,
9525,7532,
9526,7533,
9527,7534,
9528,7535,
9529,7536,
9530,7537,
9531,7538,
9532,7539,
9533,7540,
9534,7541,
9535,7542,
9536,7543,
9537,7544,
9538,7545,
9539,7546,
9540,7547,
9541,7548,
9542,7549,
9543,7550,
9544,7551,
9545,7552,
9546,7553,
9547,7554,
9650,731,
9651,730,
9673,8210,
9674,20371,
9675,723,
9678,725,
9702,12254,
9756,8220,
9757,8221,
9758,8219,
9759,8222,
9792,706,
9794,705,
9986,12176,
10145,8206,
10687,16203,
11013,8207,
11014,8208,
11015,8209,
12288,1,
12289,634,
12290,635,
12291,15453,
12294,15454,
12296,110,
12297,111,
12298,109,
12299,123,
12300,686,
12301,687,
12302,688,
12303,689,
12304,690,
12305,691,
12306,735,
12307,740,
12308,676,
12309,677,
12310,16197,
12311,16198,
12312,12129,
12313,12130,
12316,100,
12317,7608,
12319,7609,
12353,15517,
12354,15518,
12355,15519,
12356,15520,
12357,15521,
12358,15522,
12359,15523,
12360,15524,
12361,15525,
12362,15526,
12363,15527,
12364,15528,
12365,15529,
12366,15530,
12367,15531,
12368,15532,
12369,15533,
12370,15534,
12371,15535,
12372,15536,
12373,15537,
12374,15538,
12375,15539,
12376,15540,
12377,15541,
12378,15542,
12379,15543,
12380,15544,
12381,15545,
12382,15546,
12383,15547,
12384,15548,
12385,15549,
12386,15550,
12387,15551,
12388,15552,
12389,15553,
12390,15554,
12391,15555,
12392,15556,
12393,15557,
12394,15558,
12395,15559,
12396,15560,
12397,15561,
12398,15562,
12399,15563,
12400,15564,
12401,15565,
12402,15566,
12403,15567,
12404,15568,
12405,15569,
12406,15570,
12407,15571,
12408,15572,
12409,15573,
12410,15574,
12411,15575,
12412,15576,
12413,15577,
12414,15578,
12415,15579,
12416,15580,
12417,15581,
12418,15582,
12419,15583,
12420,15584,
12421,15585,
12422,15586,
12423,15587,
12424,15588,
12425,15589,
12426,15590,
12427,15591,
12428,15592,
12429,15593,
12430,15594,
12431,15595,
12432,15596,
12433,15597,
12434,15598,
12435,15599,
12436,15600,
12437,15601,
12438,15602,
12443,643,
12444,644,
12445,15451,
12446,15452,
12447,15463,
12448,15516,
12449,15608,
12450,15609,
12451,15610,
12452,15611,
12453,15612,
12454,15613,
12455,15614,
12456,15615,
12457,15616,
12458,15617,
12459,15618,
12460,15619,
12461,15620,
12462,15621,
12463,15622,
12464,15623,
12465,15624,
12466,15625,
12467,15626,
12468,15627,
12469,15628,
12470,15629,
12471,15630,
12472,15631,
12473,15632,
12474,15633,
12475,15634,
12476,15635,
12477,15636,
12478,15637,
12479,15638,
12480,15639,
12481,15640,
12482,15641,
12483,15642,
12484,15643,
12485,15644,
12486,15645,
12487,15646,
12488,15647,
12489,15648,
12490,15649,
12491,15650,
12492,15651,
12493,15652,
12494,15653,
12495,15654,
12496,15655,
12497,15656,
12498,15657,
12499,15658,
12500,15659,
12501,15660,
12502,15661,
12503,15662,
12504,15663,
12505,15664,
12506,15665,
12507,15666,
12508,15667,
12509,15668,
12510,15669,
12511,15670,
12512,15671,
12513,15672,
12514,15673,
12515,15674,
12516,15675,
12517,15676,
12518,15677,
12519,15678,
12520,15679,
12521,15680,
12522,15681,
12523,15682,
12524,15683,
12525,15684,
12526,15685,
12527,15686,
12528,15687,
12529,15688,
12530,15689,
12531,15690,
12532,15691,
12533,15692,
12534,15693,
12535,15719,
12536,15720,
12537,15721,
12538,15722,
12539,331,
12540,15455,
12541,15449,
12542,15450,
12543,15462,
12784,15702,
12785,15703,
12786,15704,
12787,15705,
12788,15706,
12789,15707,
12790,15708,
12791,15709,
12792,15710,
12793,15711,
12794,15713,
12795,15714,
12796,15715,
12797,15716,
12798,15717,
12799,15718,
13056,8048,
13057,11874,
13058,11875,
13059,8042,
13060,11876,
13061,8183,
13062,11877,
13063,11881,
13064,11879,
13065,11884,
13066,11882,
13067,11886,
13068,11888,
13069,7595,
13070,11889,
13071,11890,
13072,11891,
13073,11892,
13074,11893,
13075,11894,
13076,7586,
13077,8041,
13078,8039,
13079,11896,
13080,8040,
13081,11898,
13082,11900,
13083,11901,
13084,11902,
13085,11903,
13086,8051,
13087,11904,
13088,11905,
13089,11906,
13090,8038,
13091,8043,
13092,11907,
13093,11909,
13094,7596,
13095,7590,
13096,11912,
13097,11913,
13098,8052,
13099,7598,
13101,11915,
13102,11918,
13103,11919,
13104,11920,
13105,8049,
13106,11921,
13107,8327,
13108,11924,
13109,11925,
13110,7592,
13111,11930,
13112,11932,
13113,8046,
13114,11933,
13115,8047,
13116,11926,
13117,11934,
13118,11936,
13119,11937,
13120,11938,
13121,11935,
13122,8045,
13123,11939,
13124,11940,
13125,11941,
13126,11942,
13127,8050,
13128,11943,
13129,7585,
13130,7599,
13131,11944,
13132,11945,
13133,7588,
13134,8328,
13135,11946,
13136,11947,
13137,7593,
13138,11950,
13139,11954,
13140,11951,
13141,11955,
13142,11956,
13143,8044,
13179,8323,
13180,7623,
13181,7622,
13182,7621,
13183,8054,
64256,9358,
64257,112,
64258,113,
64259,9359,
64260,9360,
65077,7899,
65078,7900,
65081,7901,
65082,7902,
65281,2,
65282,3,
65283,4,
65284,5,
65285,6,
65286,7,
65287,8,
65288,9,
65289,10,
65290,11,
65291,12,
65292,13,
65293,151,
65294,15,
65295,104,
65296,17,
65297,18,
65298,19,
65299,20,
65300,21,
65301,22,
65302,23,
65303,24,
65304,25,
65305,26,
65306,27,
65307,28,
65308,29,
65309,30,
65310,31,
65311,32,
65312,33,
65313,34,
65314,35,
65315,36,
65316,37,
65317,38,
65318,39,
65319,40,
65320,41,
65321,42,
65322,43,
65323,44,
65324,45,
65325,46,
65326,47,
65327,48,
65328,49,
65329,50,
65330,51,
65331,52,
65332,53,
65333,54,
65334,55,
65335,56,
65336,57,
65337,58,
65338,59,
65339,60,
65340,97,
65341,62,
65342,128,
65343,64,
65344,65,
65345,66,
65346,67,
65347,68,
65348,69,
65349,70,
65350,71,
65351,72,
65352,73,
65353,74,
65354,75,
65355,76,
65356,77,
65357,78,
65358,79,
65359,80,
65360,81,
65361,82,
65362,83,
65363,84,
65364,85,
65365,86,
65366,87,
65367,88,
65368,89,
65369,90,
65370,91,
65371,92,
65372,99,
65373,94,
65374,100,
65375,12131,
65376,12132,
65377,327,
65378,328,
65379,329,
65380,330,
65381,331,
65382,15689,
65383,15608,
65384,15610,
65385,15612,
65386,15614,
65387,15616,
65388,15674,
65389,15676,
65390,15678,
65391,15642,
65392,15455,
65393,15609,
65394,15611,
65395,15613,
65396,15615,
65397,15617,
65398,15618,
65399,15620,
65400,15622,
65401,15624,
65402,15626,
65403,15628,
65404,15630,
65405,15632,
65406,15634,
65407,15636,
65408,15638,
65409,15640,
65410,15643,
65411,15645,
65412,15647,
65413,15649,
65414,15650,
65415,15651,
65416,15652,
65417,15653,
65418,15654,
65419,15657,
65420,15660,
65421,15663,
65422,15666,
65423,15669,
65424,15670,
65425,15671,
65426,15672,
65427,15673,
65428,15675,
65429,15677,
65430,15679,
65431,15680,
65432,15681,
65433,15682,
65434,15683,
65435,15684,
65436,15686,
65437,15690,
65438,388,
65439,389,
65504,102,
65505,103,
65507,226,
65508,93,
65509,61,
65512,99,
# adjustments
8212,661,
8213,661,
8216,98,
8217,96,
8220,108,
8221,122,
8229,669,
8230,668,
8242,708,
8243,709,
12289,330,
12290,327,
12296,506,
12297,507,
12298,508,
12299,509,
12300,328,
12301,329,
12302,510,
12303,511,
12304,512,
12305,513,
12308,504,
12309,505,
12312,12076,
12313,12077,
12317,423,
12319,424,
12539,331,
65288,239,
65289,240,
65292,243,
65294,245,
65306,257,
65307,258,
65339,290,
65341,292,
65371,322,
65373,324,
65375,12078,
65376,12079,
);
