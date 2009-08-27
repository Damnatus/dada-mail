#!/usr/bin/perl 

use CGI::Carp qw(fatalsToBrowser); 

use strict; 

use lib qw(
		./ 
		./DADA/perllib 
		../../ 
		../../DADA/perllib
	); 

use DADA::Config; 
use DADA::App::DBIHandle; 
use DADA::App::Guts; 
use DADA::Template::HTML; 


my $dbi_obj = DADA::App::DBIHandle->new; 
my $dbh  = $dbi_obj->dbh_obj;

use CGI qw(:standard);


if(param('process')){ 
	print list_template(
		-Part => "header", 
		-vars       => { 
			show_profile_widget => 0, 
		}
	); 
	if(step1()) { 
		if(step2()) { 
			if(step3()) {  
				if(step4() ) { 
					if(step5()) { 
						print h1('Migration Complete!');					
					}
				}
			}
		}	
	} 
	print list_template(-Part => "footer"); 
	
}
else { 
	print list_template(-Part => "header",-vars       => { 
			show_profile_widget => 0, 
				}); 
	
               
	print h1($DADA::Config::PROGRAM_NAME . ' 3.0 to 3.1 Migration Assistant '); 
	if(step1()){ 
		print <<EOF
		
		<hr /> 

<p>This migration utility will move over your current $DADA::Config::PROGRAM_NAME Subscriber Fields to the
new database design. Please MAKE SURE to make your own, manual backup of your $DADA::Config::PROGRAM_NAME 
SQL database, as this migration will remove information. Please see the documentation on this utility for
more information. </p> 

<form>
<input type="hidden" name="process" value="1" /> 
<input type="submit" value="Begin Migration!" />
</form> 
		
EOF
; 
	}
	
	print list_template(-Part => "footer"); 

	
}


sub step1 { 
	
	print h1('Step #1 Testing Your Current Setup:');
	my $schema_file = THREEOHCOMPAT::schema_file(); 
	if(! -e $schema_file){ 
		print p('PROBLEM: I cannot find the file, ' . $schema_file . '. Please make sure it exists!'); 
		print p('Stopping Migration.'); 
		return 0; 
	}
	if($DADA::Config::SUBSCRIBER_DB_TYPE ne 'SQL') { 
		print p("Problem: The, " . b('$SUBSCRIBER_DB_TYPE') . " configuration variable is not set to, 'SQL', it's set to '$DADA::Config::SUBSCRIBER_DB_TYPE'."); 
		print p("If you are not using the SQL Backend for Dada Mail, you do not need this utility."); 
		return 0;		
	}
	foreach(qw(profile_table profile_fields_table profile_fields_attributes_table)){ 
		if(THREEOHCOMPAT::table_exists($DADA::Config::SQL_PARAMS{$_})){ 
			print p("Problem: The, " . b($DADA::Config::SQL_PARAMS{$_}) . " table already exists. Stopping. You'll have to remove this table, before we can continue."); 
			print p("If there is important information saved in this table, you may not want to remove the table - make sure to follow the upgrade utility instructions correctly!");
			return 0; 
		}
		else { 
			print p("The, " . b($DADA::Config::SQL_PARAMS{$_}) . " table does not already exist. Good!"); 		
		}
	}
	
	return 1; 
	print p(i('Done!')); 
	print hr; 

}

sub step2 {
	
	print h1('Step #2 Creating Tables:');
	THREEOHCOMPAT::create_tables();
	print p(i('Done!')); 
	print hr;
	return 1; 
}


sub step3 { 
	
	my $fbv = THREEOHCOMPAT::threeoh_get_fallback_field_values(); 
	
	print h1('Step #3 Migrating Fields:');
	require DADA::ProfileFieldsManager; 
	my $dpfm = DADA::ProfileFieldsManager->new; 
	foreach(@{THREEOHCOMPAT::threeoh_subscriber_fields()}){ 
		$dpfm->add_field(
			{
				-field          => $_,
				-fallback_value => $dpfm->{$_},   
			}
		);
	}
	
	
	
	print p(i('Done!')); 
	print hr;
	return 1;
}

sub step4 { 
	print h1('Step #4 Moving Subscriber Profile Fields Information Over:');
	THREEOHCOMPAT::move_profile_info_over();
	print p(i('Done!')); 
	print hr;
	return 1; 
}

sub step5 { 

	print h1('Step #5 Removing Old Subscriber Fields Information');
	THREEOHCOMPAT::remove_old_profile_info();
	print p(i('Done!')); 
	print hr;
	return 1; 
}


package THREEOHCOMPAT;
use CGI qw(:standard); 
use Carp qw(croak confess carp);
use DADA::App::Guts; 

# ALl I need is the name of the fields I'm moving: 

sub table_exists { 

	my $table_name = shift; 
	my $count = undef; 
	eval { 
		my $query = 'SELECT COUNT(*) FROM ' . $table_name; 
		my $sth = $dbh->prepare($query); 
		$sth->execute; 
		$count =  $sth->fetchrow_array; 
	};
	
	if($@){ 
		return 0; 
	}
	elsif(defined($count)){
		return 1; 
	}
	else { 
		return 0; 
	}


	
}

sub schema_file { 
	
	my $schema_file = undef; 
	
	if($DADA::Config::SQL_PARAMS{dbtype} eq 'mysql') { 	
		$schema_file = DADA::App::Guts::make_safer('./extras/SQL/mysql_schema.sql'); 
	}
	elsif($DADA::Config::SQL_PARAMS{dbtype} eq 'Pg') { 
		$schema_file = DADA::App::Guts::make_safer('./extras/SQL/postgres_schema.sql'); 		
	}
	elsif($DADA::Config::SQL_PARAMS{dbtype} eq 'SQLite') { 
		$schema_file = DADA::App::Guts::make_safer('./extras/SQL/sqlite_schema.sql'); 		
	}
	else { 
		croak "Unknown database type: " . $DADA::Config::SQL_PARAMS{dbtype}; 
	}

	return $schema_file; 
}

sub create_tables { 
	
 	print '<div style="max-height: 200px; overflow: auto; border:1px solid black;background:#fff">';
	print '<pre>';
	my $sql;
	my $schema_file = schema_file(); 

	open(my $SQL, '<', $schema_file ) or croak $!;
	{
	    local $/ = undef;
	    $sql = <$SQL>;

	}
	close($SQL) or die $!;
	
	my @statements = split ( ';', $sql );

	foreach (@statements) {
	    if ( length($_) > 10 ) {
	        print "\nquery:\n" . $_;
	        eval {
	            my $sth = $dbh->prepare($_);
	            $sth->execute
	              or croak "cannot do statement! $DBI::errstr\n";
	        };
	        if ($@) {
	            print "\nProblem executing query:\n$@";
	        }
	        else {
	            print "\nDone!\n";
	        }
	    }
	}
	 print '</div>'; 
	 print '</pre>'; 
	return 1; 
}


sub move_profile_info_over { 
	my @fields = ('email', @{threeoh_subscriber_fields()});
	my $query = 'INSERT INTO ' . $DADA::Config::SQL_PARAMS{profile_fields_table} . ' (' . join(', ', @fields) . ' ) ';
	
	if($DADA::Config::SQL_PARAMS{dbtype} eq 'Pg'){ 
		$query .= ' SELECT DISTINCT ON (' . $DADA::Config::SQL_PARAMS{subscriber_table} . '.email) ';
 	}
	else { 
		$query .= ' SELECT ';
	}
	
	$query .= join(', ', @fields) . ' FROM ' . $DADA::Config::SQL_PARAMS{subscriber_table}; 


	if($DADA::Config::SQL_PARAMS{dbtype} =~ m/^mysql$|^SQLite$/){ 
		$query .= ' GROUP BY ' . $DADA::Config::SQL_PARAMS{subscriber_table} . ' .email';
	}
	
	print code($query); 
	my $sth = $dbh->prepare($query);
	$sth->execute() 
		or croak $DBI::errstr; 
	$sth->dump_results; 
}

sub remove_old_profile_info { 

	my $fields = threeoh_subscriber_fields(); 
	foreach(@$fields){ 
		threeoh_remove_subscriber_field({-field => $_}); 
	}
	return 1; 
}


sub threeoh_columns { 
#	my $self = shift; 
	my $sth = $dbh->prepare("SELECT * FROM " . $DADA::Config::SQL_PARAMS{subscriber_table} ." where (1 = 0)");    
	$sth->execute() or confess "cannot do statement (at: columns)! $DBI::errstr\n";  
	my $i; 
	my @cols;
	for($i = 1; $i <= $sth->{NUM_OF_FIELDS}; $i++){ 
		push(@cols, $sth->{NAME}->[$i-1]);
	} 
	$sth->finish;
	return \@cols;
}




sub threeoh_subscriber_fields { 

   #my $self = shift;
    my ($args) = @_; 
    
	my $l = [] ;
	
	#if(exists( $self->{cache}->{subscriber_fields} ) ) { 
	#	$l = $self->{cache}->{subscriber_fields};
	#} 
	#else { 
    	# I'm assuming, "columns" always returns the columns in the same order... 
	    #$l = $self->columns;
	 $l = threeoh_columns();
	 #   $self->{cache}->{subscriber_fields} = $l; 
    #}


    if(! exists($args->{-show_hidden_fields})){ 
        $args->{-show_hidden_fields} = 1; 
    }
    if(! exists($args->{-dotted})){ 
        $args->{-dotted} = 0; 
    }
    
    
    # We just want the fields *other* than what's usually there...
    my %omit_fields = (
        email_id    => 1,
        email       => 1,
        list        => 1,
        list_type   => 1,
        list_status => 1
    );

    
    my @r;
    foreach(@$l){ 
    
        if(! exists($omit_fields{$_})){
    
            if($args->{-show_hidden_fields} == 1){ 
                if($args->{-dotted} == 1){ 
                    push(@r, 'subscriber.' . $_);
                }
                else { 
                    push(@r, $_);
                }
             }
             elsif($DADA::Config::HIDDEN_SUBSCRIBER_FIELDS_PREFIX eq undef){ 
                if($args->{-dotted} == 1){ 
                    push(@r, 'subscriber.' . $_);
                }
                else { 
                
                    push(@r, $_);
                }
             }  
             else { 
             
                if($_ !~ m/^$DADA::Config::HIDDEN_SUBSCRIBER_FIELDS_PREFIX/ && $args->{-show_hidden_fields} == 0){ 
                    if($args->{-dotted} == 1){ 
                        push(@r, 'subscriber.' . $_);
                    }
                    else { 
                
                        push(@r, $_);
                    }
                }
                else { 
                
                    # ... 
                }
            }
        }
    }
    
    return \@r;
}


sub threeoh_remove_subscriber_field { 

    #my $self = shift; 
    
	
    my ($args) = @_;
    if(! exists($args->{-field})){ 
        croak "You MUST pass a field name in, -field!"; 
    }
    $args->{-field} = lc($args->{-field}); 
    
    #$self->validate_remove_subscriber_field_name(
    #    {
    #    -field      => $args->{-field}, 
    #    -die_for_me => 1, 
    #    }
    #); 
   
        
    my $query =  'ALTER TABLE '  . $DADA::Config::SQL_PARAMS{subscriber_table} . 
                ' DROP COLUMN ' . $args->{-field}; 
    
    my $sth = $dbh->prepare($query);    
    
    my $rv = $sth->execute() 
        or croak "cannot do statement! (at: remove_subscriber_field) $DBI::errstr\n";   
 	
	# I don't know if I *really* want this to be done, 
	# $self->_remove_fallback_value({-field => $args->{-field}}); 
	
	return 1; 
	
}

sub threeoh_get_fallback_field_values { 

    my $v    = {}; 
#    return $v if  $self->can_have_subscriber_fields == 0; 
    require  DADA::MailingList::Settings; 
 
	my @lists = available_lists(); 
	
   if(exists($lists[0])){ 
	
  	 my $ls = DADA::MailingList::Settings->new({-list => $lists[0]});
	    my $li = $ls->get; 
	    my @fallback_fields = split("\n", $li->{fallback_field_values}); 
	    foreach(@fallback_fields){ 
	        my ($n, $val) = split(':', $_); 
	        $v->{$n} = $val; 
	    }
		return $v; 
	}
	else { 
		return {}; 
	}

}




=cut

=pod

=head1 Dada Mail 3.0 to 3.1 Migration Utility

=head1 Description

The SQL table schema between Dada Mail 3.0 and Dada Mail 3.1 has changed. 

Most importantly, Profile Subscriber Fields that were once saved in the, 
C<dada_subscribers> table now are saved in a few different tables (C<dada_profile>, 
C<dada_profile_fields> ,C<dada_profile_fields_attributes>)

This utility creates any missing tables, moves the old Profile Subscriber 
Fields information to the new tables and removes the old information. 

=head1 REQUIREMENTS

This utility should only be used when B<upgrading> Dada Mail to version 3.1. 

This utility should also, only be used if you're using the SQL Backend. 
If you are not using the B<SQL> Backend, you would not need this utility. 

=head1 INSTALLATION

Upgrade your Dada Mail installation to B<3.1> I<before> attempting to use this utility. 

This utility is located in the Dada Mail distribution, in: 

 dada/extras/scripts/dada_3_to_dada_3.1_sql.pl

You'll most likely want to B<move> it to the, C<dada> directory. 

Change it's persmissions to, C<0755> and visit the script in your web browser. 

No other configuration is needed. 

From there, migration should be straightforward. Follow the directions in your browser window. 

Once the migration is complete, please B<REMOVE> this utility from your hosting account. 
=cut