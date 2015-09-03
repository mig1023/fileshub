package FilesHub;
use Dancer2;
use Digest::MD5;
use DBI;
use File::Copy;

my $path = 'public/upload/';
my $log_in = '';
my $capcha = 0;
my @files = ();
my $dbh;
my $sbh;

any '/' => sub {
	my $files_l = "";
	my $files_nm = 0;
	if (@files > 3) { $files_nm = 2 }
		else	{ $files_nm = @files - 1 };
	for (0..$files_nm) { 	$files_l .= '<tr><td>' . s_name($files[$_]) . '</td><td>';
				if ($log_in eq '') { 	$files_l .= f_size($path . $files[$_]);
							$files_l .= '</td><td>' . md5_file($path .
								$files[$_]) . '</td></tr>'}
					else	{ 	$files_l .= f_size($path . $log_in  . '/' . $files[$_]);
							$files_l .= '</td><td>' . md5_file($path .
								$log_in  . '/' . $files[$_]) . '</td></tr>' } 
				};
	 	
    	template "index"  => {	'link_add' => uri_for('/add'),
    				'link_lst' => uri_for('/list'),
    				'link_log' => uri_for('/login'),
    				'link_out' => uri_for('/logout'),
    				'link_reg' => uri_for('/reg'),
    				'user_log' => $log_in,
    				'filesnum' => scalar(@files),
    				'fileslst' => $files_l };
	};
	
any '/add' => sub {
	my $uploadedFile = upload('file_name');
	my $f_size;
	my $checked_name = '';
	if ($uploadedFile->size <= (32*1024*1024)) {
		if ($log_in eq '') {
			$checked_name = check_name (params->{'file_name'});
			$uploadedFile->copy_to( $path . $checked_name ); 
			unshift(@files, $checked_name);
			$f_size = f_size( $path . $checked_name); }
		else {
			$checked_name = check_name (params->{'file_name'});
			$uploadedFile->copy_to( $path . $log_in . '/' . $checked_name );
			&connect_dbi();
			$dbh->do("INSERT INTO download VALUES ('0','" . $log_in . "','" . $checked_name . "')");
			$dbh->disconnect();
			unshift(@files, $checked_name);
			$f_size = f_size( $path . $log_in . '/' . $checked_name);
			};
		template "add_done" => {'filename' => params->{'file_name'},
					'filesize' => $f_size }; }
	else { 	template "add_fail" };
	};

any '/login' => sub {
	template "login" => { 'log_done' => uri_for('/log_done') };
	};

any '/log_done' => sub {
	my $logfail = 0;
	&connect_dbi();
	$sbh = $dbh->prepare("SELECT * FROM user_name WHERE user_name = '" . params->{'login'} . "';");
	$sbh->execute or die "\nerror query!";
	my $hashref = $sbh->fetchrow_hashref();
	$dbh->disconnect();
	
	if ( $hashref->{'password'} eq md5_str (params->{'password'}) ) {
		$log_in = params->{'login'};
		&move_file_to_db();
		template "log_done" => { 'username' => params->{'login'} } }
	else {
		$log_in = '';
		template "log_fail" };	
	};

any '/list' => sub {
	&connect_dbi();
	my $files_l = "";
	my $hashref;
	$sbh = $dbh->prepare("SELECT * FROM download WHERE user_name = '" . $log_in . "';");
	$sbh->execute or die "\nerror query!";
		
	while ($hashref = $sbh->fetchrow_hashref()) { $files_l .= '<tr>' .
		'<td>' . s_name($hashref->{'links'}). '</td>' . 
		'<td>' . f_size( $path . $log_in . '/' . $hashref->{'links'} ) . '</td>' . 
	 	'<td>' . md5_file( $path . $log_in . '/' .$hashref->{'links'} ) . '</td>' .
	 	'<td><form style = "margin-bottom:0;" action = "' . uri_for('/del') . '" method = "post">' .
	 		'<input type = "hidden" name = "del_name" value = "' . $hashref->{'links'} . '">' . 
	 		'<input type = "submit" value = "x"></form></td>' . 
	 	'</tr>'; };
	
	$dbh->disconnect();
	template "list" => { 'fileslst' => $files_l } };

any '/del' => sub {
	unlink $path . $log_in . '/' . params->{'del_name'};
	&connect_dbi();
	$dbh->do("DELETE FROM download WHERE links = '" . params->{'del_name'} . "';");
	$dbh->disconnect();
	redirect '/list';
	};

any '/logout' => sub {
	$log_in = '';
	@files = ();
	redirect '/';
	};

any '/reg' => sub {
	capcha();
	
	template "reg" => { 'reg_done' => uri_for('/reg_done') };
	};
	
any '/reg_done' => sub {
	my $fail_r = '';
	
	&connect_dbi();
	$sbh = $dbh->prepare("SELECT * FROM user_name WHERE user_name = '" . params->{'login'} . "';");
	$sbh->execute or die "\nError query!";
	my $hashref = $sbh->fetchrow_hashref();
	$dbh->disconnect();
	
	$fail_r = 'логин уже занят' if params->{'login'} eq $hashref->{'user_name'} ;
	$fail_r = 'неправильная каптча' if params->{'s_capcha'} != $capcha;
	$fail_r = 'пароли не совпадают' if params->{'password1'} ne params->{'password2'};
	$fail_r = 'неправильный email' if !(params->{'email'} =~ /.+@.+\..+/i);
	$fail_r = 'не введена капча' if params->{'s_capcha'} eq 'xxxx';
	$fail_r = 'не задан email' if params->{'email'} eq 'mail@mail.com';
	$fail_r = 'не повторён пароль' if params->{'password2'} eq '';
	$fail_r = 'не задан пароль' if params->{'password1'} eq '';
	$fail_r = 'не задан логин' if params->{'login'} eq 'login';
		
	if ($fail_r ne '') { 	template "reg_fail" => { 'fail_txt' => $fail_r,
							 'link_reg' => uri_for('/reg') }; }
		else  	   {	$log_in = params->{'login'};
				mkdir( $path . params->{'login'} );
				&connect_dbi();
				$dbh->do("INSERT INTO user_name VALUES ('0','" . params->{'login'} . "','" .
					md5_str( params->{'password1'}) . "','" . params->{'email'} . "')" );
				$dbh->disconnect();
				&move_file_to_db();
				
				template "reg_done" => { 'username' => params->{'login'} };	
				}
	};

any '/download/*' => sub {
	my ($filename) = splat;
	capcha();
	
	template "file_down" => { 	'filename' => $filename,
					'filelink' => uri_for("/file/" . $filename),
					'filepath' => 'upload/' . $filename,
					'permlink' => uri_for("/download/") . $filename,
					'md5_file' => md5_file('public/upload/' . $filename) }
	};

any '/download/*/*' => sub {
	my ($username, $filename) = splat;
	capcha();
	
	template "file_down" => { 	'filename' => $filename,
					'filelink' => uri_for("/file/" . $filename),
					'filepath' => 'upload/' . $username . '/' . $filename,
					'permlink' => uri_for("/download/") . $username . '/' . $filename,
					'md5_file' => md5_file('public/upload/' . $username . '/' . $filename) };
	};

any '/file/*' => sub {
	if (params->{'s_capcha'} eq $capcha) 	{ send_file(params->{'filepath'}) }
				else		{ template "file_fail" };
	};

sub f_size {
	my $f_size = -s shift;
	my $s_size;
	$s_size = $f_size . ' б' if ($f_size <= 1024);
	$s_size = sprintf("%1d",($f_size / 1024)) . ' Кб'  if ($f_size > 1024 and $f_size < (1024*1024));
	$s_size = sprintf("%1d",($f_size / (1024*1024))) . ' Мб'  if ($f_size > (1024*1024));
	$s_size;
	};
	
sub s_name {
	my $name_full = shift;
	my $name_short = substr($name_full, 0, 15);
	my $addpath = $log_in . '/' if $log_in ne ''; 
	$name_short .= '...' if length($name_full) > 15;
	$name_short = '<a href = "' . uri_for('/download/' . $addpath . $name_full) . '">' . $name_short . '</a>'; 
	$name_short;
	};

sub check_name {
	my $name_file = shift;
	my $addpath = $log_in . '/' if $log_in ne ''; 
	if (-e $path . $addpath . $name_file) {
		my $new_num = 1;
		if ($name_file =~ /[^.]+\.[^.]+$/) {
			$name_file =~ /(.*)(\.[^.]+)$/;
			while (-e $path . $addpath . $1 . '_' . $new_num . $2 )
				{ $new_num++ };
			$name_file = $1 . '_' . $new_num . $2; }
		else {
			while (-e $path . $addpath . $name_file . '_' . $new_num )
				{ $new_num++ };
			$name_file = $name_file . '_' . $new_num;
			}
		};
	$name_file;
	};

sub connect_dbi {
	$dbh = DBI->connect("dbi:mysql:dbname=FileHub", "login", "password") or die "error MySQL connection!";
	$dbh->do("SET CHARACTER SET 'cp1251");
	$dbh->do("SET NAMES 'cp1251");
	}

sub move_file_to_db {
	&connect_dbi();
	for (@files) {
		$dbh->do("INSERT INTO download VALUES ('0','" . params->{'login'} . "','" . $_ . "')");
		move( $path . $_ , $path . $log_in . '/' . $_);
		}
	$dbh->disconnect();
	}

sub capcha {
	my @symbol = ('A','B','C','D');
	$capcha = '';
	for (0..3) {
		my $number = int(rand(9));
		copy( 'public/images/capcha/'.$number.'.JPG' , 'public/images/capcha/'.$symbol[$_].'.JPG');
		$capcha .= $number; }; 
	}

sub md5_file {
	open( my $file, '<', shift );
	binmode( $file );
	my $md5_result = Digest::MD5->new->addfile($file)->hexdigest;
	close( $file );
	$md5_result;
	}

sub md5_str {
	my $md5 = Digest::MD5->new->add(shift);
	$md5->hexdigest;
	}

true;
