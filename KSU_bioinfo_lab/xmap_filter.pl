#!/usr/bin/perl
use strict;
use warnings;

#  xmap_coverter.pl
#  
# USAGE: perl xmap_filter.pl [r.cmap] [q.cmap] [xmap] [new_xmap] [min confidence] [min % aligned] [second min confidence] [second min % aligned]
#
# Script to filter Xmaps by confidence and the precent of the maximum potential length of the alignment and generates summary stats of the more stringent alignement. An xmap with only molecules that scaffold contigs. Script also lists remaining conflicting alignments. These may be candidates for further assembly using the conflicting contigs and paired end reads. 
# perl xmap_filter.pl chicken1_r.cmap chicken1_q.cmap chicken1.xmap new_basename 40 0.3 5 0.8
#  Created by jennifer shelton on 7/10/13.
#

my $infile_rcmap=$ARGV[0];
my $infile_qcmap=$ARGV[1];
my $infile_xmap=$ARGV[2];
my $outfile_base=$ARGV[3];

my $outfile_scf="scaff_"."$outfile_base".".xmap";
my $outfile2="$outfile_base"."_report.txt";
my $outfile3="$outfile_base"."_overlaps.csv";

open (CMAP_MOL, "<$infile_rcmap") or die "can't open $infile_rcmap $!";
open (CMAP_CONTIGS, "<$infile_qcmap")or die "can't open $infile_qcmap $!";
open (XMAP, "<$infile_xmap")or die "can't open $infile_xmap $!";
open (NEWXMAP, ">$outfile_base".".xmap")or die "can't open $outfile_base.xmap $!";
open (SCFXMAP, ">$outfile_scf")or die "can't open $outfile_scf $!";

############################## QC thresholds ##############################
my $min_confidence=$ARGV[4];
my $min_precent_aligned=$ARGV[5];
my $second_min_confidence=$ARGV[6];
my $second_min_precent_aligned=$ARGV[7];
my $first_unknown=0; # first unknown contig in cmap
my $last_unknown=0; # last unknown contig in cmap
my (@xmap_table); # 2D arrays
############################## define variables ##########################################
my (%mol_length, %contig_length,%scaffolding,%cumulative,%unknowns,%knowns,$contig_count); #hashes
my $total_scaffolds=0;
my $total_unknown_scaffolds=0;
my $length_scaffolded_contigs=0;
my $overlap_count=0;
my ($contig_start_pos,$contig_end_pos,$percent_aligned);
my ($main_loop, $nested_loop,$row,$footprint_start,$footprint_end,$key,$value,$overlap);

################################ Load input files ########################################
################################ Load molecule cmap ########################################
while (<CMAP_MOL>) #make array of molecule contigs and a hash of their lengths
{
    if ($_ !~ /^#/)
	{
        #print "$_ \n";
        chomp;
        my @cmap_mol=split ("\t");
        s/\s+//g foreach @cmap_mol;
        $mol_length{$cmap_mol[0]} = $cmap_mol[1]; ## hash with id as key and molecule contig length as value
	}
}

################################ Load contig cmap ########################################
while (<CMAP_CONTIGS>) #make array of contigs from the customer and a hash of their lengths
{
    if ($_ !~ /^#/)
	{
        chomp;
        my @cmap_contigs=split ("\t");
        s/\s+//g foreach @cmap_contigs;
        $contig_length{$cmap_contigs[0]} = $cmap_contigs[1]; ## hash with id as key and sequence generated contig length as value
	}
}
################################ Load xmap ########################################
while (<XMAP>) #make array of contigs from the customer and a hash of their lengths
{
	if ($_ =~ /^#/)
	{
		print NEWXMAP;
        	print SCFXMAP;
	}
    elsif ($_ !~ /^#/)
	{
        chomp;
        my @xmap=split ("\t");
        s/\s+//g foreach @xmap;
        push (@xmap_table, [@xmap]);
	}
}
########################## filter xmap rows ##############################################
foreach $row (@xmap_table)## calculate sequence generated contig's footprint on the molecule contig and add contig footprint to the xmap array
{
    if ($row->[3] < $row->[4]) #if contig aligns in the '+' orientation
    {
        $contig_start_pos=$row->[3];
        $contig_end_pos=$row->[4];
    }
    elsif ($row->[3] >= $row->[4]) #if contig aligns in the '-' orientation
    {
        $contig_start_pos=$row->[4];
        $contig_end_pos=$row->[3];
    }
    ############################## calculate footprint ################################
    $footprint_start=$row->[5]-$contig_start_pos+1;
    ## object begining = 5 xmap
    ## comp begining = 3 or 4 xmap
    $footprint_end=$footprint_start + $contig_length{$row->[1]}-1;
    ## contig id = 1 xmap
    $row->[10] = "$footprint_start";
    $row->[11] = "$footprint_end";
    ## end of alignment = 3 or 4 xmap
    ## begining of alignment = 3 or 4 xmap
    
    ############################## calculate percent aligned #######################
    if (($footprint_start<0)&&($footprint_end<=$mol_length{$row->[2]})) #if their is an overhang on one side
    {
        $percent_aligned=($contig_end_pos-$contig_start_pos+1)/($footprint_end);
        # print "contig $row->[1] left overhang";
    }
    if (($footprint_start>=0)&&($footprint_end>$mol_length{$row->[2]}))#if their is an overhang on one side
    {
        $percent_aligned=($contig_end_pos-$contig_start_pos+1)/($mol_length{$row->[2]}-$footprint_start+1);
        # print "contig $row->[1] right overhang";
    }
    if (($footprint_start>=0)&&($footprint_end<=$mol_length{$row->[2]})) ## if contig aligns either perfeactly or within the molecule
    {
        $percent_aligned=($contig_end_pos-$contig_start_pos+1)/$contig_length{$row->[1]};
        # print "contig $row->[1] inside";
    }
    if (($footprint_start<0)&&($footprint_end>$mol_length{$row->[2]})) ## if contig aligns with overhang on both ends of the molecule
    {
        $percent_aligned=($contig_end_pos-$contig_start_pos+1)/$mol_length{$row->[2]};
        # print "contig $row->[1] outside both sides";
    }
    print "contig $row->[1] aligns with $percent_aligned \n";
    
    #################### check to see if alignemnt passes QC filters #################
    if ((($percent_aligned >= $min_precent_aligned)&&($row->[8]>=$min_confidence))||(($percent_aligned >= $second_min_precent_aligned)&&($row->[8]>=$second_min_confidence)))
    {
        $row->[12] = "passed";
        print NEWXMAP "$row->[0]\t$row->[1]\t$row->[2]\t$row->[3]\t$row->[4]\t$row->[5]\t$row->[6]\t$row->[7]\t$row->[8]\t$row->[9]\n";
        if (!$scaffolding{$row->[2]})
        {
            #### initialize new molecule to begin counting total number of alignments ######
            $scaffolding{$row->[2]}->{$row->[1]}=0; ## initialize the hash of uniquely aligned contigs
            #            print "contig $row->[1] aligns with $percent_aligned \n";
            

        }
        ############### check for unknowns and knowns on scaffold ################
        if (($row->[1]>=$first_unknown) && ($row->[1]<=$last_unknown))
        {
        	$unknowns{$row->[2]}->{$row->[1]}=1;
        }
        elsif (($row->[1]<$first_unknown) || ($row->[1]>$last_unknown))
        {
        	$knowns{$row->[2]}->{$row->[1]}=1;
        }
        ############# count scaffolding events per molecule ##########################
        ++$scaffolding{$row->[2]}->{$row->[1]};
    }
    else
    {
        $row->[12] = "failed";
    }
}
############################### print only scaffolding alignments ##########################
foreach $row (@xmap_table)
{
    my $counted_scaffolds=(scalar( keys %{ $scaffolding{$row->[2]} } ));
    if (($row->[12] eq "passed") && ($counted_scaffolds>1))
    {
        print SCFXMAP "$row->[0]\t$row->[1]\t$row->[2]\t$row->[3]\t$row->[4]\t$row->[5]\t$row->[6]\t$row->[7]\t$row->[8]\t$row->[9]\n";
    }
}
close SCFXMAP;
close NEWXMAP;



############################### count scaffolding events #################################
open (REPORT, ">>$outfile2")or die "can't open $outfile2 $!";
for my $mol_with_contig (keys %scaffolding)
{
	my $counted_scaffolds=(scalar( keys %{ $scaffolding{$mol_with_contig} } ));
	if  ($counted_scaffolds>1)
	{
        # 		print REPORT "IrysView alignments suggest Molecule $mol_with_contig has scaffolded $counted_scaffolds contigs\n";
		++$total_scaffolds;
		for my $contig_on_scaffold ( keys %{ $scaffolding{$mol_with_contig} } )
		{
			######### sum non-redundant list of scaffolded contig lengths ################
			if (!$cumulative{$contig_on_scaffold})
			{
				$length_scaffolded_contigs+=$contig_length{$contig_on_scaffold};
				$cumulative{$contig_on_scaffold}=1;
                ++$contig_count;
			}
		}
	}
    	################# check for unknowns and knowns on scaffold ##########################
    	my $unknown_scaffolds=(scalar( keys %{ $unknowns{$mol_with_contig} } ));
    	my $known_scaffolds=(scalar( keys %{ $knowns{$mol_with_contig} } ));
    	if ($unknown_scaffolds>=1 && $known_scaffolds>=1)
    	{
    		++$total_unknown_scaffolds;
    	}
	
}
$length_scaffolded_contigs=($length_scaffolded_contigs/1000000);
#print REPORT "IrysView alignments suggest Molecules have scaffolded $total_scaffolds contigs.\n";
#print REPORT "IrysView alignments suggest Molecules the cummulative length of the scaffolded contigs is $length_scaffolded_contigs.\n";
print REPORT "Total number of contigs used in scaffolds,Total number of scaffolds created,Total number of unknowns scaffolded to known contigs,Cummulative length of the scaffolded contigs (Mb),minimum percent aligned, minimum confidence,Number of overlaps\n";
print REPORT "$contig_count,$total_scaffolds,$total_unknown_scaffolds,$length_scaffolded_contigs,$min_precent_aligned,$min_confidence,";
open (NEWXMAP, "<$outfile_base".".xmap")or die "can't open $outfile_base.xmap $!";
open (OVERLAPS, ">$outfile3")or die "can't open $outfile3 $!";
################################ identify overlaps in filtered outfile #################################
print OVERLAPS "overlapping sequence-based scaffold 1,overlapping sequence-based scaffold 2,overlap length (bp)\n";
foreach $main_loop (@xmap_table) # for each sequence-based contig feature in the xmap
{
 	if ($main_loop->[12] eq "passed")
 	{
 		foreach $nested_loop (@xmap_table) # compare its footprint to every other contig feature's footprint
 		{
         	if ($nested_loop->[12] eq "passed")
         	{
                if (($main_loop->[2] eq $nested_loop->[2]))# check only for footprints on the same molecule contig
                {
                    
                    if ($nested_loop->[10] <= $main_loop->[10] && $main_loop->[10] <= $nested_loop->[11]) # run if the sequenced-based contig in the main loop has start coordinates within any the footprints of any other sequenced-based contig
                    {
                        if ("$main_loop->[1]" ne "$nested_loop->[1]")# don't calculate overlaps of the same sequence-based contig
                        {
                            if ($nested_loop->[11] < $main_loop->[11]) # if the end main loop's footprint is before the end of the nested loop footprint use the end of the main loop's footprint
                            {
                                $overlap=$nested_loop->[11]-$main_loop->[10]+1;
                                print OVERLAPS "$main_loop->[1],$nested_loop->[1],$overlap\n";
                                ++$overlap_count;
                            }
                            else # else use the end of the nested loop's footprint
                            {
                                $overlap=$main_loop->[11]-$main_loop->[10]+1;
                                print OVERLAPS "$main_loop->[1],$nested_loop->[1],$overlap\n";
                                ++$overlap_count;
                            }
                        }
                    }
                }
            }
        }
    }
}
print REPORT "$overlap_count\n";
close REPORT;
close OVERLAPS;
