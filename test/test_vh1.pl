#!/usr/bin/perl -w
# $Id: test_vh1.pl,v 1.4 2005/09/05 10:51:56 frax Exp $
use strict;

use NonameTV::Importer::VH1;

my $vh1imp= NonameTV::Importer::VH1->new();
$vh1imp->Import({});
