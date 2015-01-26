#!/usr/bin/perl -w

#use lib qw(/usr/local/dcheck/perllib);

use Config::General;
use Getopt::Std;
use LWP::UserAgent;
use MIME::Lite;
use XML::RSS::Parser::Lite;
use Data::Dumper;
use HTML::Entities;

use strict;

our $opt_s;

# --- standard vars -----
my $DEFAULTCONFIGFILE = '/etc/dcheck.conf';
my %LOGLEVELS = (
    emerg => 0,
    alert => 1,
    crit => 2,
    err => 3,
    warning => 4,
    notice => 5,
    info => 6,
    debug => 7
);

# --- global vars -----
my %config = ();
my $logsyslog = 0;
my $loglevel = $LOGLEVELS{debug};
my $VERSION="dcheck-0.5";
my $NAME="dchek";

sub get_image
{
    my ($url, $pattern, $get_title_alt) = @_;

    logging('debug', "getting image from url[$url]");

    my $img = undef;
    my $title = undef;
    my $alt = undef;

    my $ua = LWP::UserAgent->new;
    $ua->agent($VERSION);
    $ua->timeout(30);
    $ua->env_proxy;

    my $response = $ua->get($url);
    my @ergs;
    if ($response->is_success) {
        logging('debug', "will search for pattern[$pattern]");

        my $resp = $response->content;

        if ($get_title_alt) {
            ($img, $title, $alt) = $resp =~ m|$pattern|i;
        } else {
            ($img) = $resp =~ m|$pattern|i;
        }
        if (!defined $img) {
            logging('error', "get_image: cannot find image");
            logging('error', "get_image: here is whole response: " . Dumper($resp));
        }
    } else {
        logging('error', "get_image: cannot connect to url: " . $response->status_line);
    }

    return($img, $title, $alt);
}

sub get_latest_url_from_rss
{
    my ($rssurl) = @_;

    my $ua = LWP::UserAgent->new;
    $ua->agent($VERSION);
    $ua->timeout(30);
    $ua->env_proxy;

    #my $url = "http://www.giantitp.com/comics/oots.rss";

    my $response = $ua->get($rssurl);
    if ($response->is_success) {
        my $xml = $response->content;
        my $rp = new XML::RSS::Parser::Lite;
        $rp->parse($xml);

        #print $rp->get('title') . " " . $rp->get('url') . " " . $rp->get('description') . "\n";

        # we only need the first entry aka THE LATEST
        #for (my $i = 0; $i < $rp->count(); $i++) {
        for (my $i = 0; $i < 1; $i++) {
            my $it = $rp->get($i);
            return ($it->get('url'));
        }
    }
    return (undef);
}

sub download_image
{
    my ($img_otd, $tmpfile) = @_;

    logging('debug', "download image[$img_otd]");

    my $img = undef;
    my $ua = LWP::UserAgent->new;
    $ua->agent($VERSION);
    $ua->timeout(30);
    $ua->env_proxy;

    my $response = $ua->get($img_otd);
    my @ergs;
    if ($response->is_success) {
        my $resp = $response->content;

        open(OUTF, ">$tmpfile") or die "cannot open $tmpfile - $!";
        print OUTF "$resp";
        close(OUTF);

    } else {
        logging('error', "download_image: cannot connect to url: " . $response->status_line);
        return(0);
    }

    return(1);
}

sub sendMail
{
    my ($tmpfile, $subject, $msgtxt, $bcc) = @_;

    logging('debug', "sending image with subject[$subject] to bcc[$bcc]");

    my $from = $config{stdfrom};
    my $to = $config{stdto};
    my $mailhost = $config{mailhost};
    my $mailport = $config{mailport};

    my $msg = MIME::Lite->new (
        From => $from,
        To => $to,
        Bcc => $bcc,
        Subject => $subject,
        Type =>'multipart/mixed'
    ) or die "Error creating multipart container: $!\n";

    my ($mailfile) = $tmpfile =~ m|([^/]+)$|;
    $mailfile = sprintf("%s_%s", getDate(), $mailfile);

    if ($msgtxt ne '') {
        $msg->attach (
            Type    => 'TEXT',
            Data    => $msgtxt
        );
    }

    $msg->attach (
        Type => 'image/gif',
        Path => $tmpfile,
        Filename => "$mailfile",
        Disposition => 'attachment'
    ) or die "Error adding image to mail: $!\n";

    MIME::Lite->send('smtp', "$mailhost:$mailport", Timeout=>60);
    $msg->send;
}

sub getDate
{
    my $now = time;
    my @l = localtime($now);
    my $date = sprintf("%04d%02d%02d", $l[5]+1900, $l[4]+1, $l[3]);
    return($date);
}

sub logging
{
    my ($priority, $msg) = @_;
    return unless defined $msg;

    my $level = (exists $LOGLEVELS{$priority}) ? $LOGLEVELS{$priority} : 7;
    return unless $level <= $loglevel;

    if ($logsyslog) {
            syslog($priority, "[$priority] $msg");
    } else {
            my $time = localtime(time);
            print STDERR "$time [$priority] $msg\n";
    }
    die "$msg\n" if $priority =~ /^emerg$/i;
}

sub read_config
{
    my ($configfile) = @_;

    %config = Config::General::ParseConfig(-ConfigFile=>$configfile, -LowerCaseNames=>1);

    if ($config{logging} =~ /^syslog$/i) {
        $logsyslog = 1;
        checkDefault('logfacility');
        my $facility = $config{logfacility};
        openlog($NAME, 'cons,pid', $facility) or die("cannot open syslog\n");
    }
    $loglevel = $LOGLEVELS{$config{loglevel}};

    logging('debug', "Configuration: " . Dumper(\%config));
}

sub check_strip_elements
{
    my ($strip, @elements) = @_;

    for (@elements) {
        if (!exists $strip->{$_} and !defined $strip->{$_}) {
            logging('error', "$_ not set in strip-config");
            return(0);
        }
    }
    return(1);
}

sub write_data
{
    my ($file, $strips) = @_;
    open(OUT, ">$file") or die "cannot open histfile[$file] for write - $!\n\n";
    foreach my $strip (keys %$strips) {
        if (exists $strips->{$strip}->{'md5sum'} && $strips->{$strip}->{'md5sum'} ne '') {
            print OUT "$strip:", $strips->{$strip}->{'md5sum'}, "\n";
        }
    }
    close(OUT);
    return(1);
}

sub read_data
{
    my ($file, $strips) = @_;
    open(IN, $file) or die "cannot open histfile[$file] - $!\n\n";
    while(<IN>) {
        next if (/^\s*\#/ || /^\s*$/);
        chomp;
        my @l = split(/:/);
        next if $#l<1;
        my $stripname = $l[0];
        my $sum = $l[1];
        $strips->{$stripname}->{'md5sum'} = $sum;
    }
    close(IN);
    return(1);
}

sub check4new_strip
{
    my ($stripname, $md5sum, $strips) = @_;
    if (exists $strips->{$stripname}->{'md5sum'} && $strips->{$stripname}->{'md5sum'} ne '') {
        if ($md5sum eq $strips->{$stripname}->{'md5sum'}) {
            return(0);
        }
    }
    $strips->{$stripname}->{'md5sum'} = $md5sum;
    return(1);
}

sub main
{
    read_config($DEFAULTCONFIGFILE);
    my $strips = $config{strip};

    getopts('s:');
    logging('info', "only perform strip[$opt_s]") if defined $opt_s;

    if (defined $config{datafile}) {
        logging('debug', "found datafile-directive in config");
        if (-e $config{datafile}) {
            read_data($config{datafile}, $strips);
        }
    }

    foreach my $strip (keys %$strips) {
        my $img_otd = "";
        my $title = "";
        my $alt = "";
        my $get_alt_text = 0;

        if (defined $opt_s && $strip ne $opt_s) {
            next;
        }

        logging('info', "-- found strip $strip");

        if (!check_strip_elements($config{strip}->{$strip}, 'url', 'tmpfile', 'pattern', 'bcc', 'subject')) {
            logging('info', "not all elements set for strip $strip - continue with next one");
            next;
        }

        my $url = $config{strip}->{$strip}->{url};
        my $enabled = $config{strip}->{$strip}->{enabled};
        my $pattern = $config{strip}->{$strip}->{pattern};
        my $tmpfile = $config{strip}->{$strip}->{tmpfile};
        my $subject = $config{strip}->{$strip}->{subject};
        my $bcc = $config{strip}->{$strip}->{bcc};

        if (not defined $opt_s and $enabled eq "0") {
            logging('info', "strip $strip is disabled in configuration - continue with next one");
            next;
        }

        if ($config{strip}->{$strip}->{type} eq 'xkcd') {
            $get_alt_text = 1;
        } elsif ($config{strip}->{$strip}->{type} eq 'oots') {
            $url = get_latest_url_from_rss($config{strip}->{$strip}->{rssurl});
            logging('debug', "got $url as latest from rss");
        }

        ($img_otd, $title, $alt) = get_image($url, $pattern, $get_alt_text);
        if (! defined $img_otd) {
            logging('error', "cannot determine image of strip[$strip] - continue with next one");
            next;
        }

        my $msgtxt = "";
        if (defined $alt) {
            $msgtxt .= sprintf("-= %s -=\n\n", decode_entities($alt));
        }

        if (defined $title) {
            $msgtxt .= sprintf("%s\n", decode_entities($title));
        }

        if (!($img_otd =~ /http:/)) {
            $url = $config{strip}->{$strip}->{url};

            # new dilbert fast url hack
            $url =~ s/\/fast//;

            $img_otd = "$url/$img_otd";
        }

        # nichtlustig uses redirect
        if ($config{strip}->{$strip}->{type} eq 'nichtlustig') {
            $img_otd =~ s/\/main\.html//;
        }

        if (!download_image($img_otd, $tmpfile)) {
            logging('error', "cannot download image of strip[$strip] - continue with next one");
            next;
        }

        my $md5sum = `md5sum $tmpfile`;
        ($md5sum) = $md5sum =~ /^(.*?)\s+/;
        logging('debug', "$md5sum for strip $strip");
        if (check4new_strip($strip, $md5sum, $strips) == 0) {
            logging('info', "image of strip $strip not changed since last check - continue with next one");
            next;
        }

        sendMail($tmpfile, $subject, $msgtxt, $bcc) if $config{sendmail} == 1;
        unlink($tmpfile);
        logging('info', "-- done for strip $strip");
    }

    if (defined $config{datafile}) {
        write_data($config{datafile}, $strips);
    }
}

main();
