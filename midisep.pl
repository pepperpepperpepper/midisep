#!/usr/bin/perl 
use Data::Dumper;
use Cwd;

our $DEBUG = 1;

our $MIDICSV_BIN = Cwd::abs_path("midicsv-1.1/midicsv");
our $CSVMIDI_BIN = Cwd::abs_path("midicsv-1.1/csvmidi");

our $CHANNEL_EVENTS = [ 
  'Note_on_c', 'Note_off_c', 'Pitch_bend_c', 'Control_c', 
  'Program_c', 'Channel_aftertouch_c', 'Poly_aftertouch_c',
];

our $SYSEX_EVENTS = [
  'System_exclusive', 'System_exclusive_packet'
];


sub usage{
  print STDERR sprintf('$>%s midifile [output_dir]'."\n", $0);
  exit 1;
}



sub error{
  my $msg = shift;
  print STDERR $msg . "\n";
  exit(1);
}

sub warn_sysex_found{
  my $event = shift;
  my $warning = sprintf("Sysex event found on channel %s\n", $event->{channel});
  print STDERR $warning;
}


sub correct_bad_note_ons{
  my $event = shift;
  if ($event->{type} =~ /Note_on/i && $event->{data}->[-1] == 0) {
    $event->{type} = "Note_off_c";
    $event->{data}->[2] =~ s/on/off/i; 
  }
  return $event;
}

sub file_to_list{
  my $file = shift;
  my $total_channels = shift;
  my $csvdata = `$MIDICSV_BIN $file`;
  my $list = [ 
    map { 
      chomp($_); 
      my $ctx = {};

      my $line = [ split(',', $_ ) ]; 
      $ctx->{data} = $line;
      $ctx->{type} = $line->[2];
      if (grep { $ctx->{type} =~ /$_/i } @$CHANNEL_EVENTS ){
        $ctx->{channel} = ($line->[3] =~ m/([0-9]+)/g)[0];
        if (!(grep { $ctx->{channel} == $_ } @$total_channels )){
          push(@$total_channels, $ctx->{channel});
        }
      }
#      [ @line ]; 
      $ctx;
    } split('\n', $csvdata) ];
  return $list;
}

sub add_to_all_outputs{
  my $event = shift;
  my $output_files = shift;
  foreach my $events (values %$output_files){
    push (@$events, join(',' , @{$event->{data}}));
  };
}

sub add_to_single_output{
  my $event = shift;
  my $output_files = shift;
  push(@{$output_files->{$event->{channel}}}, join(',', @{$event->{data}}));
}


sub process_event_list{
  my $event_list = shift;
  my $total_channels = shift;
  my $output_data = {};

  if ($event_list->[0]->{type} !~ /header/i){
    error("Bad header");
  }
  #marker header as type0 
  $event_list->[0]->{data}->[3] =~ s/[0-9]+/0/g;

  #check if file has more than one track/composition
  my $tracks_count = $header->{data}->[4];
  if ($tracks_count > 1){
    error("Multiple tracks in same file, not yet implemented.");
  }
  foreach my $channel(@$total_channels){
    $output_data->{$channel} = [];
  }

  #main loop
  foreach $event(@$event_list){
    if ( grep { $event->{type} =~ /$_/i } @$CHANNEL_EVENTS ){
      $event = correct_bad_note_ons($event);
      add_to_single_output( $event, $output_data );
    }
    elsif ( grep { $event->{type} =~ /$_/i} @$SYSEX_EVENTS ){
      #consider adding special handle for sysex events
      #currently just ignores them
      warn_sysex_found ($event); 
    }
    else {
      add_to_all_outputs( $event, $output_data);
    }
  };

  return $output_data;
}


sub data_to_files{
  my $output_data = shift;
  my $filename_prefix = shift;
  foreach my $channel (keys %$output_data){
    my $midi_filename = sprintf("%s-%s.mid", $filename_prefix, $channel);
    my $csv_filename = sprintf("/tmp/%s-%s.csv", $filename_prefix, $channel);
    open F, ">$csv_filename" or die $!;
    print F (join("\n", @{$output_data->{$channel}}));
    close(F);
    system("$CSVMIDI_BIN $csv_filename $midi_filename");
    unlink($csv_filename);
  }
}

sub main{
  if (scalar(@ARGV) < 1){
    if ($DEBUG){
      print STDERR "DEBUG: using example.mid as default midifile\n";
    }else{
      usage;
    }
  }
  
  my $file = $ARGV[0] || "example.mid";
  my $output_dir = $ARGV[2] || "./";
  our $total_channels = [];

  our $filename_prefix = $output_dir . ($file =~ m/^(.+)\./g)[0];
  my $event_list = file_to_list ($file, $total_channels);
  my $output_data = process_event_list ($event_list, $total_channels); 
  data_to_files($output_data, $filename_prefix);
#  
};
main;
