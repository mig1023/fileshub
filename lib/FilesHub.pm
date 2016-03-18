package FilesHub;
use Dancer2;
#use Dancer2::Core::Request;
use Digest::MD5;
use DBI;
use File::Copy;
use File::Spec;
use Data::Dumper;

my $main_path = normal_name( (File::Spec->splitpath( __FILE__ ))[1]);
my $path = $main_path . 'public/upload/';
my $path_capcha = $main_path . 'public/images/capcha/';
my $log_in = '';
my $capcha = {};
my @files = ();
my $dbh;

## главная страница
any '/' => sub { 
	my $files_l;
	
	# загрузка списка последних загруженных файлов
	&connect_dbi();
	my $hashrefs = $dbh->selectall_arrayref("SELECT user_name, original_name, md5 FROM download ORDER BY uptime DESC LIMIT 3", {Slice => {}});
	$dbh->disconnect();

	for my $hashref (@$hashrefs) { 
		$files_l .= 	'<tr><td>' . s_name($hashref->{original_name}, $hashref->{user_name}, $hashref->{md5}) . 
				'</td><td>' . f_size($path.$hashref->{user_name}.'/'.$hashref->{mp5}) . '</td><td>' . 
				$hashref->{md5} . '</td></tr>';
		};
	 	
    	template "index"  => {	'link_add' => uri_for('/add'),
    				'link_lst' => uri_for('/list'),
    				'link_log' => uri_for('/login'),
    				'link_out' => uri_for('/logout'),
    				'link_reg' => uri_for('/reg'),
    				'user_log' => $log_in,
    				'filesnum' => scalar(@$hashrefs),
    				'fileslst' => $files_l,
    				'file_num' => &server_num('download'),
    				'user_num' => &server_num('username') };
	};

## загрузка файла на сервер
any '/add' => sub {
	my $uploadedFile = upload('file_name');
	my $login_for_file = ($log_in eq '' ? 'shared' : $log_in);
	
	if ($uploadedFile->size <= (32*1024*1024)) { # ограничение в 30Мб
		my $tmp_name = tmp_name (params->{file_name});
		$uploadedFile->copy_to( $path.$login_for_file.'/'.$tmp_name );
		my $mp5 = md5_file($path.$login_for_file.'/'.$tmp_name);
		move( $path.$login_for_file.'/'.$tmp_name , $path.$login_for_file.'/'.$mp5 );
		
		&connect_dbi();
		$dbh->do("INSERT INTO download (user_name, original_name, md5, uptime, ip) VALUES (?,?,?,now(),?)",
				{}, $login_for_file, params->{file_name}, $mp5, request->address);
		$dbh->disconnect();
		
		my $f_size = f_size( $path.$login_for_file.'/'.$mp5);
		
		template "add_done" => {'filename' => antixss( params->{file_name} ),
					'filesize' => $f_size }; }
	else { 	template "add_fail" }; # ошибка загрузки
	};

## форма для авторизации
any '/login' => sub {
	template "login" => { 'log_done' => uri_for('/log_done') };
	};

## авторизация
any '/log_done' => sub {
	my $logfail = 0;
	
	# запрос данных из базы по введённому логину
	&connect_dbi();
	my $hashref = $dbh->selectrow_hashref("SELECT password FROM username WHERE user_name = ?",
					{}, params->{login});
	$dbh->disconnect();
	
	# проверка пароля
	if ( $hashref->{password} eq md5_str (params->{password}) ) {
		$log_in = params->{login};
		template "log_done" => { 'username' => antixss( params->{login} ) } }
	else {
		$log_in = '';
		template "log_fail" };	
	};

## личный кабинет со списком загруженных файлов
any '/list' => sub {
	&connect_dbi();
	my $files_l;
	my $hashrefs = $dbh->selectall_arrayref("SELECT user_name, original_name, md5 FROM download WHERE user_name = ?", {Slice => {}}, $log_in);

	# список личных файлов с возможностью удаления
	for my $hashref (@$hashrefs) {
		$files_l .= '<tr>' .
			'<td>' . s_name($hashref->{original_name}, $hashref->{user_name}, $hashref->{md5}). '</td>' . 
			'<td>' . f_size( $path . $hashref->{user_name} . '/' . $hashref->{md5} ) . '</td>' . 
	 		'<td>' . md5_file( $path . $hashref->{user_name} . '/' .$hashref->{md5} ) . '</td>' .
	 		'<td><form style = "margin-bottom:0;" action = "' . uri_for('/del') . '" method = "post">' .
	 		'<input type = "hidden" name = "del_name" value = "' . $hashref->{md5} . '">' . 
	 		'<input type = "submit" value = "x"></form></td>' . 
	 	'</tr>'; };
	
	$dbh->disconnect();
	my $need_scroll = ( @$hashrefs > 12 ? 'overflow-y: scroll;' : '');
	template "list" => { 	'fileslst' => $files_l,
				'scroll' => $need_scroll }
	};

# удаление файла
any '/del' => sub {
	unlink $path . $log_in . '/' . params->{del_name};
	&connect_dbi();
	$dbh->do("DELETE FROM download WHERE md5 = ?", {}, params->{del_name});
	$dbh->disconnect();
	
	redirect '/list';
	};

## выход из личного кабинета
any '/logout' => sub {
	$log_in = '';
	
	redirect '/';
	};

## форма регистрации 
any '/reg' => sub {
	my ($capcha_code, $capcha_dir) = capcha();
	$capcha->{$capcha_dir} = $capcha_code;
	
	template "reg" => { 	'reg_done' => uri_for('/reg_done'),
				'capcha_dir' => $capcha_dir };
	};

## регистрация	
any '/reg_done' => sub {
	my $fail_r = '';
	
	# проверка уникальности логина
	&connect_dbi();
	my $hashref = $dbh->selectrow_hashref("SELECT user_name FROM username WHERE user_name = ?", {}, params->{login});
	$dbh->disconnect();
	
	clean_capcha(params->{p_capcha});
	
	$fail_r = 'логин уже занят' if params->{login} eq $hashref->{user_name};	
	$fail_r = 'такой логин недопустим' if params->{login} eq 'shared';
	$fail_r = 'неправильная каптча' if params->{s_capcha} != $capcha->{params->{p_capcha}};
	$fail_r = 'пароли не совпадают' if params->{password1} ne params->{password2};
	$fail_r = 'неправильный email' if !(params->{email} =~ /.+@.+\..+/i);
	$fail_r = 'не введена капча' if params->{s_capcha} eq 'xxxx';
	$fail_r = 'не задан email' if params->{email} eq 'mail@mail.com';
	$fail_r = 'не повторён пароль' if params->{password2} eq '';
	$fail_r = 'не задан пароль' if params->{password1} eq '';
	$fail_r = 'не задан логин' if params->{login} eq 'login';
		
	if ($fail_r ne '') {
		template "reg_fail" => { 'fail_txt' => $fail_r,
					 'link_reg' => uri_for('/reg') }; }
	else {
		$log_in = params->{login};
		mkdir( $path . params->{login} );
		
		&connect_dbi();
		$dbh->do("INSERT INTO username (user_name, password, email) VALUES (?,?,?)", {}, params->{login},
					md5_str( params->{password1} ), params->{email});
		$dbh->disconnect();
			
		template "reg_done" => { 'username' => antixss( params->{login} ) };	
		}
	};

## форма скачивания файла
any '/download/*/*' => sub {
	my ($username, $filename) = splat;
	my ($capcha_code, $capcha_dir) = capcha();
	$capcha->{$capcha_dir} = $capcha_code;
	
	&connect_dbi();
	my $hashref = $dbh->selectrow_hashref("SELECT original_name FROM download WHERE md5 = ?", {}, $filename);
	$dbh->disconnect();
	
	template "file_down" => { 	'filename' => $hashref->{original_name},
					'filelink' => uri_for("/file/" . $filename),
					'filepath' => 'upload/' . $username . '/' . $filename,
					'permlink' => uri_for("/download/") . $username . '/' . $filename,
					'capcha_dir' => $capcha_dir,
					'md5_file' => md5_file($main_path . 'public/upload/' . $username . '/' . $filename) };
	};

## скачивание файла
any '/file/*' => sub {
	clean_capcha(params->{p_capcha});
	if (params->{s_capcha} eq $capcha->{params->{p_capcha}}) {
		send_file(params->{filepath}, filename => params->{ori_name}) }
	else {
		template "file_fail" };
	};

## размер файла в читабельном формате
sub f_size {
	my $f_size = -s shift;
	my $s_size;
	$s_size = $f_size . ' б' if ($f_size <= 1024);
	$s_size = sprintf("%1d",($f_size / 1024)) . ' Кб'  if ($f_size > 1024 and $f_size < (1024*1024));
	$s_size = sprintf("%1d",($f_size / (1024*1024))) . ' Мб'  if ($f_size > (1024*1024));
	$s_size;
	};

## укорачивание имени файла для отображения	
sub s_name {
	my $name_full = shift;
	my $user_name = shift;
	my $md5_name = shift;
	my $name_short = substr($name_full, 0, 15);
	
	my $addpath = ($log_in eq '' ? 'shared' : $log_in) . '/' if $log_in ne ''; 
	$name_short .= '...' if length($name_full) > 15;
	$name_short = '<a href = "' . uri_for('/download/'.$user_name.'/'.$md5_name) . '">' . $name_short . '</a>'; 
	$name_short;
	};

## переименование загружаемого файла, если файл с таким именем уже есть
sub tmp_name {
	my @alph = (0,1,2,3,4,5,6,7,8,9,'a','b','c','d','e','f');
	my $login_for_file = ($log_in eq '' ? 'shared' : $log_in);
	my $name = '';
	for(1..10) {
		$name .= @alph[int(rand(15))]; }
	$name = tmp_name() if -e $path.$login_for_file.'/'.$name;
	$name;
	};

## подключение к БД
sub connect_dbi {
	$dbh = DBI->connect("dbi:mysql:dbname=FilesHub", "root", "password") or die;
	}

## капча (четыре случайные цифры)
sub capcha {
	my @symbol = ('A','B','C','D');
	my $capch_dir;
	do {
		$capch_dir = '';
		$capch_dir .= $symbol[int(rand(3))] for (1..10);
	} while (-e $path_capcha . $capch_dir . '/');
	
	mkdir $path_capcha . $capch_dir . '/';
	my $capcha = '';
	for (0..3) {
		my $number = int(rand(9));
		copy( $path_capcha . $number . '.JPG' , $path_capcha . $capch_dir . '/' . $symbol[$_].'.JPG');
		$capcha .= $number;
		}; 
	return $capcha, $capch_dir;
	}

## удаление уже ненужных файлов капчи
sub clean_capcha {
	my $capch_dir = shift;
	unlink $path_capcha . $capch_dir . '/' .$_. '.JPG' for ('A','B','C','D');
	rmdir $path_capcha . $capch_dir . '/';
	}

## расчёт md5 для файла
sub md5_file {
	open my $file, '<', shift;
	binmode( $file );
	my $md5_result = Digest::MD5->new->addfile($file)->hexdigest;
	close $file;
	$md5_result;
	}

## расчёт md5 для строки
sub md5_str {
	my $md5 = Digest::MD5->new->add(shift);
	$md5->hexdigest;
	}

## нормализация пути к файлам
sub normal_name {
	my $str = shift;
	$str =~ s/\/bin\/.*/\//gi;
	$str;
	}

# количество строк в БД
sub server_num {
	&connect_dbi();
	my $hashref = $dbh->selectrow_hashref("SELECT COUNT(1) as RowNumber FROM ". shift);
	$dbh->disconnect();
	$hashref->{RowNumber};
	}

## защита от xss
sub antixss {
	my $str = shift;
	$str =~ s/[^A-Za-z0-9\s]+//g;
	$str;
	}

true;
