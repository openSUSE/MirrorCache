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
-- 23 up
create unique index acc_nickname_uk on acc(nickname);
create table server_admin (
    server_id int references server on delete cascade,
    username varchar(64) not null,
    primary key(server_id,username)
);
-- 24 up
create table report (
    id serial NOT NULL PRIMARY KEY,
    title       varchar(64),
    description varchar(256),
    interval_seconds int DEFAULT 3600
);
insert into report select 1, 'Mirrors', NULL, 15*60;
create table report_body (
    report_id int references report on delete cascade,
    dt timestamp,
    body text
);
create index if not exists report_content_dt_inx on report_body(report_id, dt);
-- 25 up
alter table project add column if not exists redirect varchar(512);
-- 26 up
alter table project add column if not exists prio int;
alter table server add column if not exists sponsor varchar(64), add column if not exists sponsor_url varchar(64);
-- 27 up
alter table server alter column sponsor type varchar(128);

create table popular_file_type (
    id serial NOT NULL PRIMARY KEY,
    name varchar(64) UNIQUE,
    mask varchar(256)
);
insert into popular_file_type(name) values
('rpm'),('gz'),('drpm'),('content'),('deb'),('xml'),('media'),('iso'),('Packages'),('asc'),('txt'),('key'),('xz'),('dsc'),('repo'),('Sources'),('db'),('qcow2'),('InRelease'),('sha256');

create table popular_os (
    id serial NOT NULL PRIMARY KEY,
    name varchar(64) UNIQUE,
    mask varchar(256),
    version varchar(256),
    neg_mask varchar(256)
);

insert into popular_os(id, name, mask, version, neg_mask) values
(1, 'factory',    '.*/(openSUSE_)?[Ff]actory/.*', NULL, '.*microos.*'),
(2, 'tumbleweed', '.*/(openSUSE_)?[Tt]umbleweed(-non-oss)?/.*', NULL, NULL),
(3, 'microos',    '.*microos.*', NULL, NULL),
(4, 'leap',       '.*[lL]eap(/|_)(([1-9][0-9])(\.|_)([0-9])?(-test|-Current)?)/.*|(.*\/(15|12|43|42)\.(1|2|3|4|5)\/.*)', '\3\8.\5\6\9', '.*leap-micro.*'),
(5, 'leap-micro', '.*leap-micro(-current)?((/|-)(([1-9][0-9]?)(\.|_|-)([0-9])))?.*', '\5.\7', ''),
(100, 'xubuntu',  '.*xUbuntu(-|_)([a-zA-Z]+|[1-9][0-9]\.[0-9]*).*', '\2', NULL),
(101, 'debian',   '.*[Dd]ebian(-|_)?([a-zA-Z]+|[1-9]?[0-9](\.[0-9]+)?).*', '\2', '.*[Uu]buntu.*'),
(102, 'ubuntu',   '.*[Uu]buntu(-|_)([a-zA-Z]+|[1-9][0-9]?(\.[0-9]*)?).*', '\2', '.*x[Uu]buntu.*'),
(200, 'rhel',     '.*(RHEL|rhel)(-|_)([a-zA-Z]+|([1-9]))/.*', '\3', '.*CentOS.*'),
(201, 'centos',   '.*(CentOS|centos|EPEL)(-|_|\:\/)?([a-zA-Z]+|([1-9]([\._]([0-9]+|[a-zA-Z]+)+)?)):?\/.*', '\3', ''),
(202, 'fedora',   '.*[Ff]edora_?(([0-9]|_|[a-zA-Z])*)/.*', '\1', '');

create table popular_arch (
    id serial NOT NULL PRIMARY KEY,
    name varchar(64) UNIQUE,
    mask varchar(256),
    neg_mask varchar(256)
);

insert into popular_arch(id, name) values
(1, 'x86_64'),
(2, 'noarch'),
(3, 'ppc64'),
(4, 'aarch64'),
(5, 'arm64'),
(6, 'amd64'),
(7, 's390'),
(8, 'i386'),
(9, 'i486'),
(10, 'i586'),
(11, 'i686'),
(100, 'src');

create table agg_download (
    period     stat_period_t NOT NULL,
    dt         timestamp NOT NULL,
    project_id int NOT NULL,
    country    varchar(2),
    mirror_id  int NOT NULL,
    file_type  int,
    os_id      int,
    os_version varchar(16),
    arch_id    smallint,
    meta_id    bigint,
    cnt        bigint,
    cnt_known  bigint,
    bytes      bigint,
    primary key(period, dt, project_id, country, mirror_id, file_type, os_id, os_version, arch_id, meta_id)
);
-- 28 up
-- do nothing
-- 29 up
alter table hash add column if not exists sha512 varchar(128);
-- 30 up
alter table report_body add column if not exists tag varchar(16);
-- 31 up
create table server_note (
    hostname  varchar(128) NOT NULL,
    dt        timestamp NOT NULL,
    acc       varchar(32),
    kind      varchar(16),
    msg       varchar(512),
    primary key(hostname, dt)
);
-- 32 up
-- create table project_rollout (
-- create table project_rollout_server (
-- 33 up
drop table if exists project_rollout_server;
drop table if exists project_rollout;

create table rollout (
    id bigserial primary key,
    project_id int NOT NULL references project on delete cascade,
    epc int NOT NULL,
    dt timestamp,
    version varchar(32),
    filename varchar(256),
    prefix varchar(256),
    unique(project_id, epc, prefix)
);

create table rollout_server (
    rollout_id bigint NOT NULL references rollout on delete cascade,
    server_id  int NOT NULL references server on delete cascade,
    dt timestamp,
    primary key(rollout_id, server_id)
);
-- 34 up
alter table rollout_server add column if not exists scan_dt timestamp;
create index if not exists rollout_version_inx on rollout(version);
-- 35 up
alter table folder_diff add column if not exists realfolder_id bigint;
-- 36 up
alter table project drop column etalon;
-- 37 up
alter table project
            add column if not exists size     bigint,
            add column if not exists file_cnt bigint,
            add column if not exists lm       bigint;
-- 38 up
-- noop
-- 39 up
create table if not exists metapkg (
    id serial NOT NULL PRIMARY KEY,
    name varchar(512) UNIQUE NOT NULL,
    t_created  timestamp default current_timestamp
);

create table if not exists pkg (
    id serial NOT NULL PRIMARY KEY,
    metapkg_id bigint NOT NULL,
    folder_id  bigint NOT NULL,
    os_id      int,
    os_version varchar(16),
    arch_id    smallint,
    repository varchar(128),
    t_created  timestamp default current_timestamp,
    CONSTRAINT pkg_folder UNIQUE (folder_id, metapkg_id)
);

create index if not exists pkg_metapkg_id_idx on pkg(metapkg_id);
-- 40 up
update popular_os set mask = '.*[lL]eap(/|_)(([1-9][0-9])(.|_)([0-9])?(-test|-Current)?)/.*|(.*/(16|15|12|43|42).(0|1|2|3|4|5|6)/.*)' where id = 4;
insert into popular_os(id,name,mask) select 10, 'slowroll', '.*/[Ss]lowroll/.*' on conflict do nothing;
-- 41 up
alter table stat_agg add primary key (period, dt, mirror_id);
-- 42 up
create table if not exists agg_download_pkg (
    period     stat_period_t NOT NULL,
    dt         timestamp NOT NULL,
    metapkg_id bigint NOT NULL,
    folder_id  bigint NOT NULL,
    country    varchar(2),
    cnt        bigint,
    primary key(period, dt, metapkg_id, folder_id, country)
);
-- 43 up
alter table stat add column if not exists pkg varchar(512);
create index if not exists stat_dt_pkg_folder_id_country_idx on stat(dt, pkg, folder_id, country);
