
create table folder (
    id serial NOT NULL PRIMARY KEY,
    path varchar(512) UNIQUE NOT NULL,
    db_sync_last timestamp,
    db_sync_scheduled timestamp,
    db_sync_priority int NOT NULL DEFAULT 10,
    db_sync_for_country varchar(2), -- empty means all mirrors needs to be rescanned, otherwise - only one country
    files int,
    size bigint
);

create table file (
    id bigserial primary key,
    folder_id bigint references folder,
    name varchar(512) NOT NULL,
    size bigint,
    mtime bigint,
    dt timestamp,
    unique(folder_id, name)
);

create table redirect (
    id serial NOT NULL PRIMARY KEY,
    pathfrom varchar(512) UNIQUE NOT NULL,
    pathto   varchar(512) NOT NULL
);

create table server (
    id serial NOT NULL PRIMARY KEY,
    hostname  varchar(128) NOT NULL,
    urldir    varchar(128) NOT NULL,
    enabled  boolean NOT NULL,
    region  varchar(2),
    country varchar(2) NOT NULL,
    score   smallint,
    comment text,
    public_notes  varchar(512),
    lat numeric(6, 3),
    lng numeric(6, 3)
);

create table folder_diff (
    id bigserial primary key,
    folder_id bigint references folder on delete cascade,
    hash varchar(40),
    dt timestamp
);

create table folder_diff_file (
    folder_diff_id bigint references folder_diff,
    file_id bigint -- no foreign key to simplify deletion of files
);

CREATE INDEX folder_diff_file_index ON folder_diff_file(file_id); 

create table folder_diff_server (
    folder_diff_id bigint references folder_diff not null,
    server_id int references server on delete cascade not null
);

ALTER TABLE folder_diff_server ADD PRIMARY KEY (server_id, folder_diff_id);

create type server_capability_t as enum('http', 'https', 'ftp', 'ftps', 'rsync',
'ipv4', 'ipv6',
'country',
'region',
'as_only', 'prefix');

create table server_capability_declaration (
    server_id int references server on delete cascade,
    capability server_capability_t,
    enabled boolean,
    extra varchar(256)
);

create table server_capability_check (
    server_id int references server on delete cascade,
    capability server_capability_t,
    dt timestamp,
    success boolean,
    extra varchar(1024)
);

create index server_capability_check_1 on server_capability_check(server_id, capability, dt);

create table server_capability_force (
    server_id int references server on delete cascade,
    capability server_capability_t,
    dt timestamp,
    extra varchar(1024)
);

create table subsidiary (
    region  varchar(2) PRIMARY KEY,
    hostname  varchar(128) NOT NULL,
    uri varchar(128) default ''
);

create table audit_event (
    id bigserial primary key,
    user_id int,
    name varchar(64),
    event_data text,
    tag int,
    dt timestamp
);

create table acc (
  id serial NOT NULL,
  username varchar(64) NOT NULL,
  email varchar(128),
  fullname varchar(128),
  nickname varchar(64),
  is_operator integer DEFAULT 0 NOT NULL,
  is_admin integer DEFAULT 0 NOT NULL,
  t_created timestamp NOT NULL,
  t_updated timestamp NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT acc_username UNIQUE (username)
);

create table stat (
    id bigserial primary key,
    ip_sha1 char(40),
    agent varchar(1024),
    path varchar(1024) NOT NULL,
    country char(2),
    dt timestamp NOT NULL,
    mirror_id int,
    secure boolean NOT NULL,
    ipv4 boolean NOT NULL
);

create index stat_dt_mirror on stat(dt, mirror_id, secure, ipv4);
create index stat_mirror    on stat(mirror_id);
create index stat_client_dt on stat(ip_sha1, dt);

create type stat_period_t as enum('minute', 'hour', 'day', 'month', 'year', 'total', 'uptime');

create table stat_agg (
    dt timestamp NOT NULL,
    period stat_period_t NOT NULL,
    mirror_id int NOT NULL,
    hit_count bigint NOT NULL
);

create index stat_agg_dt_period on stat_agg(dt, period, mirror_id);
