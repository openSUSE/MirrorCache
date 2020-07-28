
create table folder (
    id serial NOT NULL PRIMARY KEY,
    path varchar(512) UNIQUE NOT NULL,
    db_sync_last timestamp,
    db_sync_scheduled timestamp,
    db_sync_priority int NOT NULL DEFAULT 10,
    -- scan_last timestamp,
    -- scan_scheduled timestamp,
    -- scan_priority int,
    files int,
    size bigint
);

create table file (
    id bigserial primary key,
    folder_id bigint references folder,
    name varchar(512),
    dt timestamp,
    unique(folder_id, name)
);

create table server (
    id serial NOT NULL PRIMARY KEY,
    hostname  varchar(128) NOT NULL,
    urldir    varchar(128) NOT NULL,
    enabled  boolean NOT NULL,
    region  varchar(2) NOT NULL,
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
    file_id bigint references file
);

create table folder_diff_server (
    folder_diff_id bigint references folder_diff not null,
    server_id int references server on delete cascade not null
);

ALTER TABLE folder_diff_server ADD PRIMARY KEY (server_id, folder_diff_id);

create type server_capability_t as enum('http', 'https', 'ftp', 'rsync',
'no_ipv4', 'no_ipv6',
'yes_country', 'no_country',
'yes_region',
'as_only', 'prefix_only');

create table server_capability (
    server_id int,
    capability server_capability_t,
    extra varchar(256)
);


create table audit_event (
    id bigserial primary key,
    user_id int,
    name varchar(64),
    event_data text,
    tag int,
    dt timestamp
);

