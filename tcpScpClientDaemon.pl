#!/usr/bin/perl

$INFO{'version_tcpscpd'}="0.01";

use POSIX ":sys_wait_h";
use IO::Socket;
use sigtrap qw(handler my_handler HUP INT QUIT KILL TERM STOP);
use POSIX;
use File::Basename;
use JSON;

my $oldmode = shift || 0;
my($pid, $sess_id, $i);

# je me duplique et je sort...
if ($pid = fork) { exit 0; }

# je me detache du terminal
die "Je ne peux pas me detacher de mon terminal !!! Argglll !!!"
unless $sess_id = POSIX::setsid();

# Precaution pour ne pas reprendre possession d'un terminal
if (!$oldmode) {
    $SIG{'HUP'} = 'IGNORE';
    if ($pid = fork) { exit 0; }
}

# Je change mon repertoire par default (pour ne pas bloquer un file system )
chdir "/";

# je ferme tous les descripteur de ficher eventuellement ouverts.
foreach $i (0 .. 64) { POSIX::close($i); }

## Reouverture de stderr, stdout, stdin vers /dev/null
open(STDIN,  "+>/dev/null");
open(STDOUT, ">/tmp/tcpScpClientDaemon.out");
open(STDERR, ">/tmp/tcpScpClientDaemon.err");

$oldmode ? $sess_id : 0;

$serveur = IO::Socket::INET->new(
   LocalPort => 8888,
   Type => SOCK_STREAM,
   Listen => 1)
or die "Impossible d'ouvrir le socket :$@\n";

$SIG{CHLD} = "IGNORE";

while ( $client = $serveur->accept() ) {
    my $pid = fork();
    if ( $pid == 0 ) {
      close($serveur);
      while ( my $ligne = <$client> ) {
         if ( $ligne =~ /^HELP/i ) {&help ($client);}
         if ( $ligne =~ /^GETFILE /i ) {&getFile ($client,$ligne);}
         if ( $ligne =~ /^LIST/i ) {&listFile ($client,$ligne);}
         if ( $ligne =~ /^QUIT/i ) { &quit($client); }
      }
   } else {
      close($client);
      do {
          $kid = waitpid(-1,&WNOHANG);
         } until $kid == -1;
   }
}

sub help {
   $client = @_[0];
   print $client "Les Commandes sont :\n";
   print $client "\tGETFILE machine:/chemin/vers/fichier.txt /repertoire/destination\n";
   print $client "\tLIST\n";
   print $client "\tQUIT\n";
   print $client "EOT\n";
   &quit($client);
}

sub quit {
   my $client=$_[0];
   print $client "EOT\n";
   shutdown($client,2);
   undef $client;
   sleep 1;
   exit;
}

sub listFile {
   $client = @_[0];
   opendir (DIR, "/tmp") or die $!;
   while (my $filename = readdir(DIR)) {
      if ( $filename =~ /scpout_/ ) {
         ($type,$machine,$fileEI,$pid) = split ( /_|\./,$filename);
         open MYFILE,"/tmp/$filename";
         while (my $readLine = <MYFILE>) {
            $readLine =~  s/\x0D\x0A//g;
            $readLine =~  s/[\x0D]/\x0A/g;
            @tabLine=split(/\n/,$readLine);
            $readLine=pop @tabLine;
            if ( $readLine =~ /$fileEI/ ) {
               $pourcentage = $readLine;
               $pourcentage =~ s/.* (.*%) .*/\1/;
               $FILEDEF{$pid}{'fileEI'}=$fileEI;
               $FILEDEF{$pid}{'machine'}=$machine;
               $FILEDEF{$pid}{'pourcentage'}=$pourcentage;
            }
         }
         close MYFILE;
      }
   }
   closedir(DIR);
   $json_text = to_json(\%FILEDEF, {utf8 => 1, pretty => 1});
   print $client "$json_text\n";
   &quit($client);
}

sub getFile {
   $client = @_[0];
   ($cmd, $completeFile, $dest)=split(" ",@_[1]);
   ($machine,$file)=split(":",$completeFile);
   $fileEI=$file;
   $fileEI =~ s{.*/}{};
   $fileEI =~ s{\.[^.]+$}{};
   print $client "Recupertation fichier $file de $machine vers $dest :\n";
   my $pid = fork();
   if ( $pid == 0 ) {
      open(STDOUT, ">/tmp/scpout_".$machine."_".$fileEI.".$$");
      open(STDERR, ">/tmp/scperr_".$machine."_".$fileEI.".$$");
      exec("/usr/bin/ssh -ttt localhost TERM=linux /usr/bin/scp -o 'StrictHostKeyChecking=no' -i /var/www/.ssh/id_rsa $machine:$file $dest");
   } else {
      &quit($client);
   }
}
