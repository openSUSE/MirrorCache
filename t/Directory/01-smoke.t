use Mojo::Base -strict;

use Test::More;

use Directory::Scanner::OBSMediaVersion;

sub test_cases {
    my $cases = shift;
    my %cases = %$cases;
    for my $rpm (sort keys %cases) {
        my $expect = $cases{$rpm};
        my $got = Directory::Scanner::OBSMediaVersion::parse_version($rpm);
        is $got, $expect, "correct version for $rpm";
    }

}

subtest 'packages' => sub {

my %cases = (
    "/tumbleweed/repo/oss/noarch/apparmor-docs-3.0.7-3.1.noarch.rpm" => "3.0.7",
    "/tumbleweed/repo/oss/x86_64/cargo1.64-1.64.0-1.1.x86_64.rpm"    => "1.64.0",
    "/distribution/leap/15.3/repo/oss/noarch/python-pyOpenSSL-doc-17.5.0-3.9.1.noarch.rpm" => "17.5.0",
    "/repositories/multimedia:/apps/15.4/x86_64/qjackctl-0.9.7-lp154.59.30.x86_64.rpm" => "0.9.7",
);
    test_cases(\%cases);

};


subtest 'isos' => sub {

my %cases = (
    "/iso/openSUSE-Tumbleweed-XFCE-Live-x86_64-Snapshot20240427-Media.iso" => "20240427",
    "/appliances/openSUSE-MicroOS.x86_64-16.0.0-ContainerHost-kvm-and-xen-Snapshot20240427.qcow2" => "20240427",
    "/tumbleweed/appliances/opensuse-tumbleweed-image.x86_64-1.0.0-lxc-Snapshot20240427.tar.xz" => "20240427",
);
    test_cases(\%cases);
};


subtest 'Centos' => sub {

my %cases = (
    "bwm-ng-0.6-6.el6.2.x86_64" => "0.6",
    "dhcp-4.1.1-49.P1.el6.centos.x86_64" => "4.1.1",
    "ipsec-tools-0.8.0-25.3.x86_64" => "0.8.0",
    "iscsi-initiator-utils-6.2.0.873-14.el6.x86_64" => "6.2.0.873",
    "quagga-0.99.23.1-2014082501.x86_64" => "0.99.23.1",
);

    test_cases(\%cases);
};

subtest 'deb' => sub {

my %cases = (
    "opsi-utils_4.2.0.184-1_amd64.deb" => "4.2.0.184",
    "libethercat_1.5.2-33_arm64.deb" => "1.5.2",
);

    test_cases(\%cases);
};


done_testing();
