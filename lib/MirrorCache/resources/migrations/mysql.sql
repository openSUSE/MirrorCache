--
-- These are the migrations for the PostgreSQL MirrorCache backend. They are only used for upgrades to the latest version.
-- Downgrades may be used to clean up the database, but they do not have to work with old versions of MirrorCache.
--
-- 1 up
create table if not exists folder (
    id bigint NOT NULL PRIMARY KEY AUTO_INCREMENT,
    path varchar(512) character set utf8mb4 collate utf8mb4_bin UNIQUE NOT NULL,
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
    id bigint AUTO_INCREMENT primary key,
    folder_id bigint,
    name varchar(512) character set utf8mb4 collate utf8mb4_bin NOT NULL,
    size bigint,
    mtime bigint,
    dt timestamp(3) NULL DEFAULT NULL,
    target varchar(512) character set utf8mb4 collate utf8mb4_bin,
    unique(folder_id, name),
    constraint `fk_file_folder` FOREIGN KEY(folder_id) references folder(id) on delete cascade
);

create table if not exists redirect (
    id int AUTO_INCREMENT NOT NULL PRIMARY KEY,
    pathfrom varchar(512) character set utf8mb4 collate utf8mb4_bin UNIQUE NOT NULL,
    pathto   varchar(512) character set utf8mb4 collate utf8mb4_bin NOT NULL
);

create table if not exists server (
    id int AUTO_INCREMENT NOT NULL PRIMARY KEY,
    hostname  varchar(128) NOT NULL UNIQUE,
    hostname_vpn varchar(128) UNIQUE,
    urldir    varchar(128) character set utf8mb4 collate utf8mb4_bin NOT NULL,
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
    id bigint AUTO_INCREMENT primary key,
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
    server_id int not null,
    dt timestamp(3) NULL DEFAULT NULL,
    PRIMARY KEY (server_id, folder_diff_id),
    constraint `fk_diff_server_diff` FOREIGN KEY(folder_diff_id) references folder_diff(id) on delete cascade,
    constraint `fk_diff_server` FOREIGN KEY(server_id) references server(id) on delete cascade
);

create table if not exists server_capability_declaration (
    server_id int not null,
    capability enum('http', 'https', 'ftp', 'ftps', 'rsync','ipv4', 'ipv6','country','region','as_only', 'prefix', 'hasall'),
    enabled boolean,
    extra varchar(256),
    PRIMARY KEY(server_id, capability),
    constraint `fk_capability_declaration_server` FOREIGN KEY(server_id) references server(id) on delete cascade
);

create table if not exists server_capability_check (
    server_id int not null,
    capability enum('http', 'https', 'ftp', 'ftps', 'rsync','ipv4', 'ipv6','country','region','as_only', 'prefix', 'hasall'),
    dt timestamp(3) NULL DEFAULT NULL,
    -- success boolean,
    extra varchar(1024),
    unique index server_capability_check_uk(server_id, capability, dt),
    constraint `fk_capability_check_server` FOREIGN KEY(server_id) references server(id) on delete cascade
);

create table if not exists server_capability_force (
    server_id int not null,
    capability enum('http', 'https', 'ftp', 'ftps', 'rsync','ipv4', 'ipv6','country','region','as_only', 'prefix', 'hasall'),
    dt timestamp(3) NULL DEFAULT NULL,
    extra varchar(1024),
    PRIMARY KEY(server_id, capability),
    constraint `fk_capability_force_server` FOREIGN KEY(server_id) references server(id) on delete cascade
);

create table if not exists subsidiary (
    region  varchar(2),
    hostname  varchar(128) NOT NULL,
    uri varchar(128) default '',
    local boolean,
    unique key(region, hostname)
);

create table if not exists audit_event (
    id bigint AUTO_INCREMENT primary key,
    user_id int,
    name varchar(64),
    event_data text,
    tag int,
    dt timestamp(3) NULL DEFAULT NULL
);

create table if not exists acc (
  id int AUTO_INCREMENT primary key NOT NULL,
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
    id bigint AUTO_INCREMENT primary key,
    ip_sha1 char(40),
    agent varchar(1024),
    path varchar(1024) character set utf8mb4 collate utf8mb4_bin NOT NULL,
    country char(2),
    dt timestamp(3) NOT NULL,
    mirror_id int,
    folder_id bigint,
    file_id bigint,
    secure boolean NOT NULL,
    ipv4 boolean NOT NULL,
    metalink boolean default '0',
    head boolean default '0',
    mirrorlist boolean default '0',
    pid int,
    execution_time int
);

create index if not exists stat_dt_mirror on stat(dt, mirror_id, secure, ipv4);
create index if not exists stat_mirror    on stat(mirror_id);
create index if not exists stat_client_dt on stat(ip_sha1, dt);

create table if not exists stat_agg (
    dt timestamp(3) NOT NULL,
    period enum('minute', 'hour', 'day', 'month', 'year', 'total', 'uptime') NOT NULL,
    mirror_id int NOT NULL,
    hit_count bigint NOT NULL
);

create index if not exists stat_agg_dt_period on stat_agg(dt, period, mirror_id);
-- 2 up
alter table stat add column if not exists metalink boolean default '0', add column if not exists head boolean default '0';
-- 3 up
alter table folder drop column if exists db_sync_for_country;
-- 4 up
create table hash (
    file_id bigint NOT NULL AUTO_INCREMENT primary key,
    mtime bigint,
    size bigint NOT NULL,
    md5 char(32),
    sha1 char(40),
    sha256 char(64),
    piece_size int,
    pieces longblob,
    target varchar(512) character set utf8mb4 collate utf8mb4_bin ,
    dt timestamp(3) NOT NULL,
    constraint `fk_hash_file` FOREIGN KEY(file_id) references file(id) on delete cascade
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
    id int AUTO_INCREMENT NOT NULL primary key,
    name varchar(64) unique not null,
    path varchar(512) character set utf8mb4 collate utf8mb4_bin unique not null,
    etalon int NULL,
    db_sync_last timestamp(3) NULL DEFAULT NULL,
    db_sync_every int default 1,
    db_sync_full_every int default 4,
    constraint `fk_project_etalon` FOREIGN KEY(etalon) references server(id) on delete cascade
);
alter table stat add column if not exists mirrorlist boolean default '0';
-- 9 up
alter table server add column if not exists hostname_vpn varchar(128) UNIQUE;
-- 10 up
-- 11 up
create index if not exists file_folder_id_idx on file(folder_id);
create index if not exists folder_diff_folder_id_idx on folder_diff(folder_id);
create index if not exists folder_diff_server_folder_diff_id_idx on folder_diff_server(folder_diff_id);
-- 12 up
-- 13 up
drop table if exists demand;
drop table if exists demand_mirrorlist;
alter table folder
    drop column if exists db_sync_last,
    drop column if exists db_sync_scheduled,
    drop column if exists db_sync_priority,
    add column if not exists wanted            timestamp(3) NULL DEFAULT NULL,
    add column if not exists sync_requested    timestamp(3) NULL DEFAULT NULL,
    add column if not exists sync_scheduled    timestamp(3) NULL DEFAULT NULL,
    add column if not exists sync_last         timestamp(3) NULL DEFAULT NULL,
    add column if not exists scan_requested    timestamp(3) NULL DEFAULT NULL,
    add column if not exists scan_scheduled    timestamp(3) NULL DEFAULT NULL,
    add column if not exists scan_last         timestamp(3) NULL DEFAULT NULL;
-- 14 up
create index if not exists folder_sync_requested_idx on folder(sync_requested, wanted, sync_scheduled);
create index if not exists folder_scan_requested_idx on folder(scan_requested, wanted, scan_scheduled);
-- 15 up
alter table subsidiary add column if not exists local boolean default '0';
alter table folder add column if not exists hash_last_import timestamp(3) NULL DEFAULT NULL;
-- 16 up
alter table file add column if not exists target varchar(512) character set utf8mb4 collate utf8mb4_bin;
alter table hash add column if not exists target varchar(512) character set utf8mb4 collate utf8mb4_bin;
-- 17 up
create table server_project (
    server_id  int NOT NULL,
    project_id int NOT NULL,
    state int, -- -1 - disabled, 0 - missing, 1 - present
    extra varchar(1024),
    dt timestamp(3) NULL DEFAULT NULL,
    constraint `fk_project_server` FOREIGN KEY(server_id) references server(id) on delete cascade,
    constraint `fk_project_project` FOREIGN KEY(project_id) references project(id) on delete cascade
);
-- 18 up
alter table hash
    add column if not exists zlengths varchar(32),
    add column if not exists zblock_size int,
    add column if not exists zhashes longblob;
alter table stat
    add column if not exists pid int,
    add column if not exists execution_time int;
-- 19 up
alter table subsidiary
    add column weight int default '1';
-- 20 up
create index if not exists folder_diff_id_index on folder_diff_file(folder_diff_id);
-- 21 up
create table if not exists server_stability (
    server_id int not null,
    capability enum('http', 'https', 'ftp', 'ftps', 'rsync','ipv4', 'ipv6','country','region','as_only', 'prefix', 'hasall'),
    dt timestamp(3) NULL DEFAULT NULL,
    rating int, -- 0 - bad, 1 - unknown, 10 - some issues last hour, 100 - some issues last 24 hours, 1000 - no issues recorder last 24 hours.
    PRIMARY KEY(server_id, capability),
    constraint `fk_stability_server` FOREIGN KEY(server_id) references server(id) on delete cascade
);
-- 22 up
create index if not exists folder_diff_file_2 on folder_diff_file(file_id, folder_diff_id);
alter table server_capability_check drop column if exists success;
-- 23 up
create unique index acc_nickname_uk on acc(nickname);
create table server_admin (
    server_id int not null,
    username varchar(64) not null,
    primary key(server_id,username),
    constraint `fk_server_admin` FOREIGN KEY(server_id) references server(id) on delete cascade
);
-- 24 up
create table report (
    id int AUTO_INCREMENT NOT NULL PRIMARY KEY,
    title       varchar(64),
    description varchar(256),
    interval_seconds int DEFAULT 3600
);
insert into report select 1, 'Mirrors', NULL, 15*60;
create table report_body (
    report_id int,
    dt timestamp,
    body text,
    constraint `fk_report_body_report` FOREIGN KEY(report_id) references report(id) on delete cascade
);
create index if not exists report_content_dt_inx on report_body(report_id, dt);
-- 25 up
alter table project add column if not exists redirect varchar(512);
-- 26 up
alter table project add column if not exists prio int;
alter table server add column if not exists sponsor varchar(64), add column if not exists sponsor_url varchar(64);
-- 27 up
alter table server modify column sponsor varchar(128);

create table popular_file_type (
    id int AUTO_INCREMENT NOT NULL PRIMARY KEY,
    name varchar(64) UNIQUE,
    mask varchar(256)
);
insert into popular_file_type(name) values
('rpm'),('gz'),('drpm'),('content'),('deb'),('xml'),('media'),('iso'),('Packages'),('asc'),('txt'),('key'),('xz'),('dsc'),('repo'),('Sources'),('db'),('qcow2'),('InRelease'),('sha256');

create table popular_os (
    id int AUTO_INCREMENT NOT NULL PRIMARY KEY,
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
    id int AUTO_INCREMENT NOT NULL PRIMARY KEY,
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
    period     enum('minute', 'hour', 'day', 'month', 'year', 'total', 'uptime') NOT NULL,
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
update popular_os set version = '\\3\\8.\\5\\6\\9' where version = '\3\8.\5\6\9';
update popular_os set version = '\\5.\\7' where version = '\5.\7';
update popular_os set version = '\\1' where version = '\1';
update popular_os set version = '\\2' where version = '\2';
update popular_os set version = '\\3' where version = '\3';
-- 29 up
alter table hash add column if not exists sha512 varchar(128);
-- 30 up
alter table report_body add column if not exists tag varchar(16);
