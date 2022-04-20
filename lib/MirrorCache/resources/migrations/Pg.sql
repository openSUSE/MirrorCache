--
-- These are the migrations for the PostgreSQL MirrorCache backend. They are only used for upgrades to the latest version.
-- Downgrades may be used to clean up the database, but they do not have to work with old versions of MirrorCache.
--
-- 1 up
create table if not exists folder (
    id serial NOT NULL PRIMARY KEY,
    path varchar(512) UNIQUE NOT NULL,
    wanted            timestamp, -- last day when it was requested by client, refreshed once in 24 hours
    sync_requested    timestamp, -- when it was determined that sync is needed
    sync_scheduled    timestamp, -- when sync job was created (scheduled)
    sync_last         timestamp, -- when sync job started
    scan_requested    timestamp, -- when it was determined that scan is needed
    scan_scheduled    timestamp, -- when scan job was created (scheduled)
    scan_last         timestamp, -- when scan job started
    hash_last_import  timestamp,
    files             int,
    size              bigint
);

create table if not exists file (
    id bigserial primary key,
    folder_id bigint references folder,
    name varchar(512) NOT NULL,
    size bigint,
    mtime bigint,
    dt timestamp,
    target varchar(512),
    unique(folder_id, name)
);

create table if not exists redirect (
    id serial NOT NULL PRIMARY KEY,
    pathfrom varchar(512) UNIQUE NOT NULL,
    pathto   varchar(512) NOT NULL
);

create table if not exists server (
    id serial NOT NULL PRIMARY KEY,
    hostname  varchar(128) NOT NULL UNIQUE,
    hostname_vpn varchar(128) UNIQUE,
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

create table if not exists folder_diff (
    id bigserial primary key,
    folder_id bigint references folder on delete cascade,
    hash varchar(40),
    dt timestamp
);

create table if not exists folder_diff_file (
    folder_diff_id bigint references folder_diff,
    file_id bigint -- no foreign key to simplify deletion of files
);

CREATE INDEX if not exists folder_diff_file_index ON folder_diff_file(file_id);

create table if not exists folder_diff_server (
    folder_diff_id bigint references folder_diff not null,
    server_id int references server on delete cascade not null,
    dt timestamp,
    PRIMARY KEY (server_id, folder_diff_id)
);

DO $$
BEGIN
IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'server_capability_t') THEN
create type server_capability_t as enum('http', 'https', 'ftp', 'ftps', 'rsync',
'ipv4', 'ipv6',
'country',
'region',
'as_only', 'prefix');
END IF;

IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'stat_period_t') THEN
create type stat_period_t as enum('minute', 'hour', 'day', 'month', 'year', 'total', 'uptime');
END IF;
END$$;

create table if not exists server_capability_declaration (
    server_id int references server on delete cascade,
    capability server_capability_t,
    enabled boolean,
    extra varchar(256)
);

create table if not exists server_capability_check (
    server_id int references server on delete cascade,
    capability server_capability_t,
    dt timestamp,
    -- success boolean,
    extra varchar(1024)
);

create index if not exists server_capability_check_1 on server_capability_check(server_id, capability, dt);

create table if not exists server_capability_force (
    server_id int references server on delete cascade,
    capability server_capability_t,
    dt timestamp,
    extra varchar(1024)
);

create table if not exists subsidiary (
    region  varchar(2) PRIMARY KEY,
    hostname  varchar(128) NOT NULL,
    uri varchar(128) default '',
    local boolean default 'f'
);

create table if not exists audit_event (
    id bigserial primary key,
    user_id int,
    name varchar(64),
    event_data text,
    tag int,
    dt timestamp
);

create table if not exists acc (
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

create table if not exists stat (
    id bigserial primary key,
    ip_sha1 char(40),
    agent varchar(1024),
    path varchar(1024) NOT NULL,
    country char(2),
    dt timestamp NOT NULL,
    mirror_id int,
    folder_id bigint,
    file_id bigint,
    secure boolean NOT NULL,
    ipv4 boolean NOT NULL,
    metalink boolean default 'f',
    head boolean default 'f',
    mirrorlist boolean default 'f',
    pid int,
    execution_time int
);

create index if not exists stat_dt_mirror on stat(dt, mirror_id, secure, ipv4);
create index if not exists stat_mirror    on stat(mirror_id);
create index if not exists stat_client_dt on stat(ip_sha1, dt);

create table if not exists stat_agg (
    dt timestamp NOT NULL,
    period stat_period_t NOT NULL,
    mirror_id int NOT NULL,
    hit_count bigint NOT NULL
);

create index if not exists stat_agg_dt_period on stat_agg(dt, period, mirror_id);
-- 2 up
alter table stat add column if not exists metalink boolean default 'f', add column if not exists head boolean default 'f';
-- 3 up
alter table folder drop column if exists db_sync_for_country;
-- 4 up
create table hash (
    file_id bigint NOT NULL primary key references file on delete cascade,
    mtime bigint,
    size bigint NOT NULL,
    md5 char(32),
    sha1 char(40),
    sha256 char(64),
    piece_size int,
    pieces text,
    target varchar(512),
    dt timestamp NOT NULL
);
create index hash_file_id_size on hash(file_id, size);
create index hash_sha256 on hash(sha256);
-- 5 up
create index audit_event_dt on audit_event(dt, name);
-- 6 up
alter table stat add column if not exists folder_id bigint, add column if not exists file_id bigint;
create index if not exists stat_id_mirror_folder on stat(id, mirror_id, folder_id);
-- 7 up
create index if not exists stat_dt_ip_mirror on stat(dt, ip_sha1, mirror_id, secure, ipv4);
-- 8 up
create table project (
    id serial NOT NULL primary key,
    name varchar(64) unique not null,
    path varchar(512) unique not null,
    etalon int NULL references server,
    db_sync_last timestamp,
    db_sync_every int default 1,
    db_sync_full_every int default 4
);
alter table stat add column if not exists mirrorlist boolean default 'f';
-- 9 up
alter table server add column if not exists hostname_vpn varchar(128) UNIQUE;
-- 10 up
-- 11 up
create index if not exists file_folder_id_idx on file(folder_id);
create index if not exists folder_diff_folder_id_idx on folder_diff(folder_id);
create index if not exists folder_diff_server_folder_diff_id_idx on folder_diff_server(folder_diff_id);
-- 12 up
alter type server_capability_t add value 'hasall'; -- mirror always has all files - no scan is performed
-- 13 up
drop table if exists demand;
drop table if exists demand_mirrorlist;
alter table folder
    drop column if exists db_sync_last,
    drop column if exists db_sync_scheduled,
    drop column if exists db_sync_priority,
    add column if not exists wanted            timestamp,
    add column if not exists sync_requested    timestamp,
    add column if not exists sync_scheduled    timestamp,
    add column if not exists sync_last         timestamp,
    add column if not exists scan_requested    timestamp,
    add column if not exists scan_scheduled    timestamp,
    add column if not exists scan_last         timestamp;
-- 14 up
create index if not exists folder_sync_requested_idx on folder(sync_requested, wanted, sync_scheduled);
create index if not exists folder_scan_requested_idx on folder(scan_requested, wanted, scan_scheduled);
-- 15 up
alter table subsidiary add column if not exists local boolean default 'f';
alter table folder add column if not exists hash_last_import timestamp;
-- 16 up
alter table file add column if not exists target varchar(512);
alter table hash add column if not exists target varchar(512);
-- 17 up
create table server_project (
    server_id  bigint NOT NULL references server on delete cascade,
    project_id bigint NOT NULL references project on delete cascade,
    state int, -- -1 - disabled, 0 - missing, 1 - present
    extra varchar(1024),
    dt timestamp,
    unique(server_id, project_id)
);
-- 18 up
alter table hash
    add column if not exists zlengths varchar(32),
    add column if not exists zblock_size int,
    add column if not exists zhashes bytea;
alter table stat
    add column if not exists pid int,
    add column if not exists execution_time int;
-- 19 up
alter table subsidiary
    drop constraint subsidiary_pkey,
    add column weight int default '1';
-- 20 up
create index if not exists folder_diff_id_index on folder_diff_file(folder_diff_id);
-- 21 up
create table if not exists server_stability (
    server_id int references server on delete cascade,
    capability server_capability_t,
    dt timestamp,
    rating int -- 0 - bad, 1 - unknown, 10 - some issues last hour, 100 - some issues last 24 hours, 1000 - no issues recorder last 24 hours.
);
-- 22 up
create index if not exists folder_diff_file_2 on folder_diff_file(file_id, folder_diff_id);
alter table server_capability_check drop column if exists success;
