perlrepo:
  pkgrepo.managed:
    - humanname: Perl repo
    - mirrorlist: http://mirrorcache.opensuse.org/download/repositories/devel:/languages:/perl/openSUSE_Leap_15.2/
    - gpgcheck: 0

mirrorcache:
  pkgrepo.managed:
    - humanname: MirrorCache repo
    - mirrorlist: http://mirrorcache.opensuse.org/download/repositories/home:/andriinikitin/openSUSE_Leap_15.2/
    - gpgcheck: 0

  pkg.latest:
    - name: MirrorCache
    - refresh: False
