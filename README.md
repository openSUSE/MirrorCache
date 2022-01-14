Welcome to MirrorCache!
-----------------------

MirrorCache is a Web Server for files download, which will route download requests to an appropriate mirror.
MirrorCache doesn't store files and instead keeps in DB list of files from the `Main Server`.

According to Wikipedia "Cache - is a component that stores data so that future requests for that data can be served faster".
In this regard MirrorCache is a cache of (meta)information about geographical location of files.

"Cache hit" means that MirrorCache was able to redirect to proper (the closest) mirror.
"Cache miss" means that MirrorCache had to redirect request to the `Main Server`.

Output below domonstrates a cache miss, so the download request will be redirected to the `Main Server` (in this case download.opensuse.org):


```
> curl -I http://mirrorcache.opensuse.org/download/update/openSUSE-current/x86_64/alsa-1.1.5-lp152.8.6_lp152.9.4.1.x86_64.drpm
HTTP/1.1 302 Found
location: http://download.opensuse.org/update/openSUSE-current/x86_64/alsa-1.1.5-lp152.8.6_lp152.9.4.1.x86_64.drpm
date: Wed, 29 Jul 2020 08:37:07 GMT
```

Then background jobs will collect info about the hottest misses and scan predefined mirrors for presence of these files. Further requests will be redirected to one of the mirrors that has the file:


```
> curl -I http://mirrorcache.opensuse.org/download/update/openSUSE-current/x86_64/alsa-1.1.5-lp152.8.6_lp152.9.4.1.x86_64.drpm
HTTP/1.1 302 Found
location: http://ftp.gwdg.de/pub/opensuse/update/openSUSE-current/x86_64/alsa-1.1.5-lp152.8.6_lp152.9.4.1.x86_64.drpm
date: Wed, 29 Jul 2020 08:40:00 GMT
```

The project was implemented as a quick hack with some amount of shortcuts to make things going.
The goal is to improve it over time with the main focus to do the job.

## Motivation

The motivation behind this project is to rethink architecture of mirrorbrain https://github.com/poeml/mirrorbrain with following features:
- job queue;
- web UI;
- fileless approach means that application doesn't require physical access to managed files;
- properly handle http/https and ipv4/ipv6 requests by picking a mirror which is able to serve that;
- geo-cluster feature allows to configure an instance per region, where each instance scan only mirrors from own region.

## How to report issues or ask questions:

Write an email to andrii.nikitin on domain suse.com or use the issue tracker at https://github.com/openSUSE/MirrorCache/
