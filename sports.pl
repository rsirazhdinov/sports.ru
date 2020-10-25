#!/usr/bin/env perl

use Mojolicious::Lite;
use Mojo::SQLite;

# connect to database
use DBI;


my $dbh = DBI->connect("dbi:SQLite:database.db","","") or die "Could not connect";

my $sql = Mojo::SQLite->new('sqlite:database.db');
my $migrations = Mojo::SQLite::Migrations->new(sqlite => $sql);
$migrations = $migrations->from_data;
# Reset database
$migrations->migrate(0)->migrate;
# shortcut for use in template
helper db => sub { $dbh }; 

helper select_users => sub {
  my $self = shift;
  my $sth = eval { $self->db->prepare('SELECT login, name FROM users') } || return undef;
  $sth->execute;
  return $sth->fetchall_arrayref;
};

helper select_rooms => sub {
  my $self = shift;
  my $sth = eval { $self->db->prepare('SELECT room FROM rooms') } || return undef;
  $sth->execute;
  return $sth->fetchall_arrayref;
};

helper validate => sub {
  my $self = shift;
  my ($user, $room, $reserve_date, $time_begin, $time_end) = @_;
  return "Start time must be less than end time" if $time_begin >= $time_end;

  my @ary = @{ $dbh->selectall_arrayref("select users.name from reservation inner join users on reservation.login = users.login where reservation.reserve_date = ? and reservation.room = ? and ((reservation.time_begin <= ? and reservation.time_end >= ?) or (reservation.time_begin <= ? and reservation.time_end >= ?) or (reservation.time_begin >= ? and reservation.time_end <= ?))", undef,$reserve_date, $room, $time_begin, $time_begin, $time_end, $time_end, $time_begin, $time_end) };
  my @error = map {$_->[0]} @ary;
  my $error = join ' and ', @error;
  return "Meeting room \"$room\" from $time_begin to $time_end reserved by ". $error if $error;
  return undef;
};

helper select_reservation => sub {
  my $self = shift;
  my $sth = eval { $self->db->prepare('
  SELECT reservation.room,
       users.name,
       reservation.reserve_date,
       reservation.time_begin,
       reservation.time_end
FROM reservation
INNER JOIN users ON reservation.login = users.login
ORDER BY reservation.room,
         reservation.reserve_date,
         reservation.time_begin') } || return undef;
  $sth->execute;
  return $sth->fetchall_arrayref;
};

# setup base route
# any '/' => 'index';
any '/' => sub {
  my $self = shift;
  my $select_users = $self->select_users;
  my $select_rooms = $self->select_rooms;
  my $select_reservation = $self->select_reservation;
  my $error = $self->param('error');
  $self->stash( error => $error,
                select_users => $select_users,
                select_reservation => $select_reservation,
                select_rooms => $select_rooms );
  $self->render('index');
};


my $insert;
while (1) {
  # create insert statement
  $insert = eval { $dbh->prepare('INSERT INTO reservation (room, login, reserve_date, time_begin, time_end) VALUES  (?,?,?,?,?)') };
  last if $insert;

  # if statement didn't prepare, assume its because the table doesn't exist
  # warn "Creating table 'people'\n";
  # $dbh->do('CREATE TABLE people (name varchar(255), age int);');
}


# setup route which receives data and returns to /
post '/insert' => sub {
  my $self = shift;
  my $user = $self->param('user');
  my $room = $self->param('room');
  my $reserve_date = $self->param('reserve_date');
  my $time_begin = $self->param('time_begin');
  my $time_end = $self->param('time_end');

  my $error = $self->validate($user, $room, $reserve_date, $time_begin, $time_end);
  $insert->execute($room, $user, $reserve_date, $time_begin, $time_end) if not $error;

  my $url = $self->url_for("/");
  $self->redirect_to($url->query(error => $error));
};

app->start;

__DATA__
@@ index.html.ep
<!DOCTYPE html>
<html>
<head><title>People</title></head>
<body>
  <form action="<%=url_for('insert')->to_abs%>" method="post">
  <fieldset style="display: inline-block; padding: 10px">
   <legend>To book a room, make a choice and click book</legend>
    <label for="user">Users:</label>
       <select name="user" id="user">
       % foreach my $row_ref (@$select_users) {
          <option value=<%= $row_ref->[0] %>><%= $row_ref->[1] %></option>
        % }
      </select><br><br>

     <label for="room">Rooms:</label>
       <select name="room" id="room">
       % foreach my $row_ref (@$select_rooms) {
          <option value=<%= $row_ref->[0] %>><%= $row_ref->[0] %></option>
        % }
      </select><br><br>

      <label for="reserve_date">Date:</label>
     <input type="date" id="reserve_date" name="reserve_date"
       value="2020-10-22"
       min="2020-01-01" max="2020-12-31"><br><br>

    <label for="time_begin">Time_begin:</label>
    <input name="time_begin" id="time_begin" type="time" value="11:12"><br><br>

    <label for="time_end">Time_end:</label>
    <input name="time_end" id="time_end" type="time" value="12:13"><br><br>

    <input type="submit" value="Book">
    </fieldset>
  </form>
  <br>
  %if($error){
    <p style="font-weight: bold; color:red;"><%= $error %></p>
  %}

  Already reserved meeting rooms: <br>
  <table border="1">
    <tr>
      <th>Room</th>
      <th>Reserved by</th>
      <th>Date reservation</th>
      <th>Time begin</th>
      <th>Time end</th>
    </tr>

    % foreach my $row (@$select_reservation) {
      <tr>
        % for my $text (@$row) {
          <td><%= $text %></td>
        % }
      </tr>
    % }
  </table>
</body>
</html>


@@ migrations
-- 1 up
create table rooms (room text primary key);
insert into rooms values ('yellow');
insert into rooms values ('green');
insert into rooms values ('blue');

create table users(login text primary key, name text, password text);
insert into users(login, name, password) values ('ivanov','Ivanov I.G.','sdf3342423');
insert into users(login, name, password) values ('petrov','Petrov P.S.','sfseseww3');
insert into users(login, name, password) values ('alekseev','Alekseev B.I.','sdfwsdfsfs');
insert into users(login, name, password) values ('chizhov','Chizhov E.M.','34gfgwwewe');

create table reservation(id integer primary key, room text, login text, reserve_date text, time_begin text, time_end text);

-- 1 down
drop table if exists rooms;
drop table if exists users;
drop table if exists reservation;