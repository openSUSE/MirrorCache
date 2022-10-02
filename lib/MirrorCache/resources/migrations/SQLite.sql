--
-- These are the migrations for the SQLite MirrorCache backend. They are only used for upgrades to the latest version.
-- Downgrades may be used to clean up the database, but they do not have to work with old versions of MirrorCache.
--
-- 1 up
create table if not exists folder (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    path varchar(512) UNIQUE NOT NULL,
    wanted            timestamp(3) NULL DEFAULT NULL, -- last day when it was requested by client, refreshed once in 24 hours
    sync_requested    timestamp(3) NULL DEFAULT NULL, -- when it was determined that sync is needed
    sync_scheduled    timestamp(3) NULL DEFAULT NULL, -- when sync job was created (scheduled)
    sync_last         timestamp(3) NULL DEFAULT NULL, -- when sync job started
    scan_requested    timestamp(3) NULL DEFAULT NULL, -- when it was determined that scan is needed
    scan_scheduled    timestamp(3) NULL DEFAULT NULL, -- when scan job was created (scheduled)
    scan_last         timestamp(3) NULL DEFAULT NULL, -- when scan job started
    hash_last_import  timestamp(3) NULL DEFAULT NULL,
    files             int,
    size              bigint
);

create table if not exists file (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    folder_id bigint,
    name varchar(512) NOT NULL,
    size bigint,
    mtime bigint,
    dt timestamp(3) NULL DEFAULT NULL,
    target varchar(512),
    unique(folder_id, name),
    constraint `fk_file_folder` FOREIGN KEY(folder_id) references folder(id) on delete cascade
);

create table if not exists redirect (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    pathfrom varchar(512) UNIQUE NOT NULL,
    pathto   varchar(512) NOT NULL
);

create table if not exists server (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
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
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    folder_id bigint not null,
    hash varchar(40),
    dt timestamp(3) NULL DEFAULT NULL,
    constraint `fk_diff_folder` FOREIGN KEY(folder_id) references folder(id) on delete cascade
);

create table if not exists folder_diff_file (
    folder_diff_id bigint not null,
    file_id bigint not null, -- no foreign key to simplify deletion of files
    constraint `fk_diff_file_diff` FOREIGN KEY(folder_diff_id) references folder_diff(id) on delete cascade
);

create table if not exists folder_diff_server (
    folder_diff_id bigint not null,
    server_id INTEGER not null,
    dt timestamp(3) NULL DEFAULT NULL,
    PRIMARY KEY (server_id, folder_diff_id),
    constraint `fk_diff_server_diff` FOREIGN KEY(folder_diff_id) references folder_diff(id) on delete cascade,
    constraint `fk_diff_server` FOREIGN KEY(server_id) references server(id) on delete cascade
);

create table if not exists server_capability_declaration (
    server_id INTEGER not null,
    capability TEXT CHECK( capability IN ('http', 'https', 'ftp', 'ftps', 'rsync','ipv4', 'ipv6','country','region','as_only', 'prefix', 'hasall') ),
    enabled boolean,
    extra varchar(256),
    PRIMARY KEY(server_id, capability),
    constraint `fk_capability_declaration_server` FOREIGN KEY(server_id) references server(id) on delete cascade
);

create table if not exists server_capability_check (
    server_id INTEGER not null,
    capability TEXT CHECK( capability IN ('http', 'https', 'ftp', 'ftps', 'rsync','ipv4', 'ipv6','country','region','as_only', 'prefix', 'hasall') ),
    dt timestamp(3) NULL DEFAULT NULL,
    -- success boolean,
    extra varchar(1024),
    constraint `fk_capability_check_server` FOREIGN KEY(server_id) references server(id) on delete cascade
);
create UNIQUE INDEX if not exists server_capability_check_uk on server_capability_check(server_id, capability, dt);

create table if not exists server_capability_force (
    server_id INTEGER not null,
    capability TEXT CHECK( capability IN ('http', 'https', 'ftp', 'ftps', 'rsync','ipv4', 'ipv6','country','region','as_only', 'prefix', 'hasall') ),
    dt timestamp(3) NULL DEFAULT NULL,
    extra varchar(1024),
    PRIMARY KEY(server_id, capability),
    constraint `fk_capability_force_server` FOREIGN KEY(server_id) references server(id) on delete cascade
);

create table if not exists subsidiary (
    region  varchar(2),
    hostname  varchar(128) NOT NULL,
    uri varchar(128) default '',
    local boolean
);
create UNIQUE INDEX if not exists subsidiary_uk on subsidiary(region, hostname);

create table if not exists audit_event (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    user_id INTEGER,
    name varchar(64),
    event_data text,
    tag int,
    dt timestamp(3) NULL DEFAULT NULL
);

create table if not exists acc (
  id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
  username varchar(64) NOT NULL,
  email varchar(128),
  fullname varchar(128),
  nickname varchar(64),
  is_operator integer DEFAULT 0 NOT NULL,
  is_admin integer DEFAULT 0 NOT NULL,
  t_created timestamp(3) NOT NULL,
  t_updated timestamp(3) NOT NULL,
  CONSTRAINT acc_username UNIQUE (username)
);

create table if not exists stat (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    ip_sha1 char(40),
    agent varchar(1024),
    path varchar(1024) NOT NULL,
    country char(2),
    dt timestamp(3) NOT NULL,
    mirror_id INTEGER,
    folder_id bigint,
    file_id bigint,
    secure boolean NOT NULL,
    ipv4 boolean NOT NULL,
    metalink boolean default '0',
    head boolean default '0',
    mirrorlist boolean default '0',
    pid INTEGER,
    execution_time int
);

create index if not exists stat_dt_mirror on stat(dt, mirror_id, secure, ipv4);
create index if not exists stat_mirror    on stat(mirror_id);
create index if not exists stat_client_dt on stat(ip_sha1, dt);

create table if not exists stat_agg (
    dt timestamp(3) NOT NULL,
    period TEXT CHECK( period IN ('minute', 'hour', 'day', 'month', 'year', 'total', 'uptime')) NOT NULL,
    mirror_id INTEGER NOT NULL,
    hit_count bigint NOT NULL
);

create index if not exists stat_agg_dt_period on stat_agg(dt, period, mirror_id);
-- 2 up
-- 3 up
-- 4 up
create table if not exists hash (
    file_id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    mtime bigint,
    size bigint NOT NULL,
    md5 char(32),
    sha1 char(40),
    sha256 char(64),
    piece_size int,
    pieces longblob,
    target varchar(512),
    dt timestamp(3) NOT NULL,
    constraint `fk_hash_file` FOREIGN KEY(file_id) references file(id) on delete cascade
);
create index if not exists hash_file_id_size on hash(file_id, size);
create index if not exists hash_sha256 on hash(sha256);
-- 5 up
create index if not exists audit_event_dt on audit_event(dt, name);
-- 6 up
create index if not exists stat_id_mirror_folder on stat(id, mirror_id, folder_id);
-- 7 up
create index if not exists stat_dt_ip_mirror on stat(dt, ip_sha1, mirror_id, secure, ipv4);
-- 8 up
create table if not exists project (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    name varchar(64) unique not null,
    path varchar(512) unique not null,
    etalon int NULL,
    db_sync_last timestamp(3) NULL DEFAULT NULL,
    db_sync_every int default 1,
    db_sync_full_every int default 4,
    constraint `fk_project_etalon` FOREIGN KEY(etalon) references server(id) on delete cascade
);
-- 9 up
-- 10 up
-- 11 up
create index if not exists file_folder_id_idx on file(folder_id);
create index if not exists folder_diff_folder_id_idx on folder_diff(folder_id);
create index if not exists folder_diff_server_folder_diff_id_idx on folder_diff_server(folder_diff_id);
-- 12 up
-- 13 up
drop table if exists demand;
drop table if exists demand_mirrorlist;
-- 14 up
create index if not exists folder_sync_requested_idx on folder(sync_requested, wanted, sync_scheduled);
create index if not exists folder_scan_requested_idx on folder(scan_requested, wanted, scan_scheduled);
-- 15 up
-- 16 up
-- 17 up
create table if not exists server_project (
    server_id  int NOT NULL,
    project_id INTEGER NOT NULL,
    state int, -- -1 - disabled, 0 - missing, 1 - present
    extra varchar(1024),
    dt timestamp(3) NULL DEFAULT NULL,
    constraint `fk_project_server` FOREIGN KEY(server_id) references server(id) on delete cascade,
    constraint `fk_project_project` FOREIGN KEY(project_id) references project(id) on delete cascade
);
-- 18 up
-- 19 up
alter table subsidiary
    add column weight int default '1';
-- 20 up
create index if not exists folder_diff_id_index on folder_diff_file(folder_diff_id);
-- 21 up
create table if not exists server_stability (
    server_id INTEGER not null,
    capability TEXT CHECK( capability IN ('http', 'https', 'ftp', 'ftps', 'rsync','ipv4', 'ipv6','country','region','as_only', 'prefix', 'hasall') ),
    dt timestamp(3) NULL DEFAULT NULL,
    rating int, -- 0 - bad, 1 - unknown, 10 - some issues last hour, 100 - some issues last 24 hours, 1000 - no issues recorder last 24 hours.
    PRIMARY KEY(server_id, capability),
    constraint `fk_stability_server` FOREIGN KEY(server_id) references server(id) on delete cascade
);
-- 22 up
create index if not exists folder_diff_file_2 on folder_diff_file(file_id, folder_diff_id);
-- 23 up
create unique index acc_nickname_uk on acc(nickname);
create table if not exists server_admin (
    server_id INTEGER not null,
    username varchar(64) not null,
    primary key(server_id,username),
    constraint `fk_server_admin` FOREIGN KEY(server_id) references server(id) on delete cascade
);
-- 24 up
create table if not exists report (
    id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
    title       varchar(64),
    description varchar(256),
    interval_seconds int DEFAULT 3600
);
insert into report select 1, 'Mirrors', NULL, 15*60;
create table if not exists report_body (
    report_id INTEGER,
    dt timestamp,
    body text,
    constraint `fk_report_body_report` FOREIGN KEY(report_id) references report(id) on delete cascade
);
create index if not exists report_content_dt_inx on report_body(report_id, dt);
-- 25 up
alter table project add column redirect varchar(512);
-- 26 up
alter table project add column prio int;
alter table server add column sponsor varchar(64);
alter table server add column sponsor_url varchar(64);

