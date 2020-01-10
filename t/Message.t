#!/usr/bin/perl
# -*- indent-tabs-mode: nil; -*-
# vim:ft=perl:et:sw=4
# $Id: tools_data.t 8606 2013-02-06 08:44:02Z rousse $

use strict;
use warnings;
use Data::Dumper;
use English;
use File::Path qw(make_path rmtree);
use File::Copy::Recursive qw(fcopy rcopy dircopy fmove rmove dirmove);

use FindBin qw($Bin);
use lib "$Bin/../src/lib";
use lib 't/stub';

use Test::More;

BEGIN {
    use_ok('Sympa::Message');
}

my $tmp_dir = 't/tmp';
my $db_dir = $tmp_dir.'/db';
my $home_dir = $tmp_dir.'/list_data';
my $etc_dir = $tmp_dir.'/etc';
my $test_list_name = 'test';

%Conf::Conf = (
    domain     => 'lists.example.com',     # mandatory
    listmaster => 'dude@example.com',      # mandatory
    lang       => 'en-US',
    sender_headers => 'From',
    tmpdir => $tmp_dir,
    db_type    => 'SQLite',
    db_name    => $db_dir.'/message-test-db.sqlite',
    update_db_field_types    => 'auto',
    home => $home_dir,
    etc => $etc_dir,
    cache_list_config => '',
    supported_lang => 'en-US',
    filesystem_encoding => 'utf-8',
    urlize_min_size => 0,
);

if (-d $tmp_dir) {
  rmtree($tmp_dir);
}
make_path($tmp_dir);
make_path($db_dir);
make_path($home_dir);
dircopy('t/data/list_data/', $home_dir);
make_path($etc_dir);

my $log = Sympa::Log->instance;
$log->{log_to_stderr} = 'err';

if (-f $Conf::Conf{db_name}) {
    unlink $Conf::Conf{db_name};
}

open my $fileHandle, ">", "$Conf::Conf{db_name}" or die "Can't create '$Conf::Conf{db_name}'\n";
close $fileHandle;

my $sdm = Sympa::DatabaseManager->instance;
Sympa::DatabaseManager::probe_db();

my $list = Sympa::List->new($test_list_name, '*');
$list->_update_list_db;
my $root_url = '/attach/test/';

my @to_urlize = (
    {
        test_case => 'simple',
        filename => 't/samples/urlize-simple.eml',
        attachments =>
            [
                {
                    name => 'attachment.pdf',
                    escaped_name => 'attachment.pdf',
                },
            ],
        dirname => 'simple@example.com',
        escaped_dirname => 'simple%40example.com',
    },
    {
        test_case => 'simple with several attachments',
        filename => 't/samples/urlize-simple-mutiple-attachments.eml',
        attachments =>
            [
                {
                    name => 'attachment.pdf',
                    escaped_name => 'attachment.pdf',
                },
                {
                    name => 'text.txt',
                    escaped_name => 'text.txt',
                },
                {
                    name => 'image.png',
                    escaped_name => 'image.png',
                },
            ],
        dirname => 'simple@example.com',
        escaped_dirname => 'simple%40example.com',
    },
    {
        test_case => 'encoding',
        filename => 't/samples/urlize-encoding.eml',
        attachments =>
            [
                {
                    name => 'ございます.pdf',
                    escaped_name => '%25e3%2581%2594%25e3%2581%259',
                },
            ],
        dirname => 'globuz_24_3c_3e_25@example.com',
        escaped_dirname => 'globuz_24_3c_3e_25%40example.com',
    },
    {
        test_case => 'nested in multipart/mixed message',
        filename => 't/samples/urlize-nested-mixed.eml',
        attachments =>
            [
                {
                    name => 'Würzburg.txt',
                    escaped_name => 'W%25c3%25bcrzburg.txt',
                },
            ],
        dirname => '3_24@domain.tld',
        escaped_dirname => '3_24%40domain.tld',
    },
    {
        test_case => 'nested in multipart/alternative message',
        filename => 't/samples/urlize-nested-alternative.eml',
        attachments =>
            [
                {
                    name => 'globuz.pdf',
                    escaped_name => 'globuz.pdf',
                },
            ],
        dirname => '4_24@domain.tld',
        escaped_dirname => '4_24%40domain.tld',
    },
    {
        test_case => 'Deep nested message',
        filename => 't/samples/urlize-deep-nested-mixed.eml',
        attachments =>
            [
                {
                    name => 'Würzburg.txt',
                    escaped_name => 'W%25c3%25bcrzburg.txt',
                },
                {
                    name => 'msg.1.bin',
                    escaped_name => 'msg.1.bin',
                },
            ],
        dirname => 'deep-nested@domain.tld',
        escaped_dirname => 'deep-nested%40domain.tld',
    },
);



foreach my $test_file (@to_urlize) {
    my $to_urlize_file = $test_file->{filename};
    my $lock_fh =  Sympa::LockedFile->new($to_urlize_file, -1, '+<');
    my $to_urlize_string = do { local $RS; <$lock_fh> };
    my $to_urlize = Sympa::Message->new($to_urlize_string);

    my $parser = MIME::Parser->new;
    $parser->extract_nested_messages(0);
    $parser->extract_uuencode(1);
    $parser->output_to_core(1);
    $parser->tmp_dir($Conf::Conf{'tmpdir'});

    my $msg_string = $to_urlize->as_string;
    $msg_string =~ s/\AReturn-Path: (.*?)\n(?![ \t])//s;
    my $entity = $parser->parse_data($msg_string);

    my $new_entity = Sympa::Message::_urlize_parts($entity, $list, $to_urlize->{'message_id'});

    ### Preparation done. Actual testing starts here.

    my $urlized_directory;
    opendir my $dh, $home_dir.'/'.$test_list_name.'/urlized/';
    foreach my $file (readdir $dh) {
      next if $file =~ m{\A\.+\Z};
      $urlized_directory = $file; last;
    }
    closedir $dh;

    is($urlized_directory, $test_file->{dirname}, 'Test case: '.$test_file->{test_case}.' - Directory where urlized parts are stored correctly escaped.');

    ok(! -f $home_dir.'/'.$test_list_name.'/urlized/'.$urlized_directory.'/msg.0.bin', 'Test case: '.$test_file->{test_case}.' - The text of the message has not been converted to binary attachment.') ;

    ok(! -f $home_dir.'/'.$test_list_name.'/urlized/'.$urlized_directory.'/msg.0.txt', 'Test case: '.$test_file->{test_case}.' - The text of the message has not been converted to text attachment.') ;
    
    my @expected_files;
    foreach my $file (@{$test_file->{attachments}}) {
        ok( -f "$home_dir/$test_list_name/urlized/$urlized_directory/$file->{name}", 'Test case: '.$test_file->{test_case}.' - The attachment '.$file->{name}.' has been stored on the filesystem.') ;
        if (-f "$home_dir/$test_list_name/urlized/$urlized_directory/$file->{name}") {
            push @expected_files, $file->{name};
        }
        my $found_url_to_attachment = 0;
        foreach my $line (split '\n', $new_entity->as_string()) {
            my $line_to_match = $root_url.$test_file->{escaped_dirname}.'/'.$file->{escaped_name};
            if ($line =~ m{$line_to_match}) {
                $found_url_to_attachment = 1;
                last;
            }
        }
        
        is( $found_url_to_attachment, 1, 'Test case: '.$test_file->{test_case}.' - The attachment '.$file->{name}.' stored on the filesystem has an URL to retrieve it in the new message.');
    }
    my @found_files;
    opendir my $dh2, "$home_dir/$test_list_name/urlized/$urlized_directory/";
    foreach my $file (readdir $dh2) {
      next if $file =~ m{\A\.+\Z};
      push @found_files, $file;
    }
    closedir $dh2;
    my $total_expected_files = $#expected_files+1;
    is($#found_files, $#expected_files, 'Test case: '.$test_file->{test_case}.' - Found the urlized attachments (total: '.$total_expected_files.') and only them.');
    rmtree $home_dir.'/'.$test_list_name.'/urlized/'.$urlized_directory;
}
rmtree $tmp_dir;
done_testing();
