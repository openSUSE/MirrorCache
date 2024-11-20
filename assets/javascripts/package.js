
var pkg_param_pkg;
var pkg_param_arch;
var pkg_param_official;
var pkg_param_os;
var pkg_param_os_ver;
var pkg_param_repo;

function initPackageParams() {

    const queryString = window.location.search;
    const urlParams = new URLSearchParams(queryString);


    pkg_param_pkg = urlParams.get('pkg');
    pkg_param_arch = urlParams.get('arch');
    pkg_param_official = urlParams.get('official');
    pkg_param_os = urlParams.get('os');
    pkg_param_os_ver = urlParams.get('os_ver');
    pkg_param_repo = urlParams.get('repo');

    if (pkg_param_pkg) {
        ( document.getElementById("packag") || {} ).value = pkg_param_pkg;
    }
    if (pkg_param_arch) {
        document.getElementById("arch").value = pkg_param_arch;
    }
    if (pkg_param_official) {
        document.getElementById("official").checked = pkg_param_official ? 1 : 0;
    }
    if (pkg_param_os) {
        document.getElementById("os").value = pkg_param_os;
    }
    if (pkg_param_os_ver) {
        document.getElementById("os_ver").value = pkg_param_os_ver;
    }
    if (pkg_param_repo) {
        document.getElementById("repo").value = pkg_param_repo;
    }

}

function setupPackages() {
    var table    = $('#packages');


    if (typeof table.data !== 'undefined') {
        table.DataTable().destroy();
    }

    pkg_param_pkg      = document.getElementById("packag").value;
    pkg_param_arch     = document.getElementById("arch").value;
    pkg_param_official = document.getElementById("official").checked ? 1 : '';
    pkg_param_os       = document.getElementById("os").value;
    pkg_param_os_ver   = document.getElementById("os_ver").value;
    pkg_param_repo     = document.getElementById("repo").value;

    var dataTable = table.DataTable({
        ajax: {
            url: '/rest/search/packages',
            data: {
                "package":  pkg_param_pkg,
                "arch":     pkg_param_arch,
                "official": pkg_param_official,
                "os":       pkg_param_os,
                "os_ver":   pkg_param_os_ver,
                "repo":     pkg_param_repo
            },
        },
        deferRender: true,
        columns: [{
            data: 'name',
            render: function(data, type, row) {
                if (type !== 'display') {
                    return data ? data : '';
                }
                if (data) {
                    var get = [];
                    if (pkg_param_arch) {
                        get.push(['arch', htmlEscape(pkg_param_arch)]);
                    }
                    if (pkg_param_official) {
                        get.push(['official', htmlEscape(pkg_param_official)]);
                    }
                    if (pkg_param_os) {
                        get.push(['os', htmlEscape(pkg_param_os)]);
                    }
                    if (pkg_param_os_ver) {
                        get.push(['os_ver', htmlEscape(pkg_param_os_ver)]);
                    }
                    if (pkg_param_repo) {
                        get.push(['repo', htmlEscape(pkg_param_repo)]);
                    }
                    var getstr = '';
                    for (var i = 0; i < get.length; i++) {
                        if (getstr) {
                            getstr = getstr.concat('&');
                        }
                        getstr = getstr.concat(get[i][0], "=", get[i][1]);
                    }
                    data = htmlEscape(data);

                    if (getstr) {
                        getstr = '?' + getstr;
                    }
                    return '<a href="/app/package/'+ data + getstr + '">' + data + '</>';
                }
                return '';
            }
        }, // { data: 'dt' }
        ],
        lengthMenu: [
            [100, 1000, 10, -1],
            [100, 1000, 10, 'All'],
        ]
    });
}

function setupPackageLocations(name) {
    var table    = $('#package_locations');


    if (typeof table.data !== 'undefined') {
        table.DataTable().destroy();
    }

    pkg_param_arch     = document.getElementById("arch").value;
    pkg_param_official = document.getElementById("official").checked ? 1 : '';
    pkg_param_os       = document.getElementById("os").value;
    pkg_param_os_ver   = document.getElementById("os_ver").value;
    pkg_param_repo     = document.getElementById("repo").value;

    var dataTable = table.DataTable({
        ajax: {
            url: '/rest/search/package_locations',
            data: {
                "package":  pkg_name,
                "arch":     pkg_param_arch,
                "official": pkg_param_official,
                "os":       pkg_param_os,
                "os_ver":   pkg_param_os_ver,
                "repo":     pkg_param_repo
            },
        },
        deferRender: true,
        columns: [
        {
            data: 'path',
            render: function(data, type, row) {
                if (type !== 'display') {
                    return data ? data : '';
                }
                data = data? htmlEscape(data) : '';
                return data? '<a href="' + data + '/">' + data + '</>' : '';
            }
        }, {
            data: 'file',
            defaultContent: "",
            type: "version-string",
            render: function (data, type, row, meta) {
                if(type === 'display'){
                    path = row['path'] + '/';
                    var d = data;
                    var t = '';
                    if(row['name'].slice(-1) === '/') {
                        d = data.slice(0,-1);
                        t = '/';
                    }
                    data = '<a href="' + path + encodeComponentExceptColon(d) + t + '">' + data + '</a>';
                }
                return data;
            }
        }, {
            data: 'time',
            className: 'mtime',
            defaultContent: "",
            render: function (data, type, row, meta) {
                if(type === 'display' && data > 0){
                    path = row['path'] + '/';
                    data = new Date(data * 1000).toLocaleString().replace(/.\d+$/, "").replace(/:\d\d (AM|PM)$/, " $1");
                    if(row['name'].slice(-1) != '/') {
                        data = '<a href="' + path + encodeComponentExceptColon(row['file']) + '.mirrorlist">' + data + '</a>';
                    } else {
                        data = '<a href="' + path + encodeComponentExceptColon(row['file'].slice(0,-1)) + '/">' + data + '</a>';
                    }
                }
                return data;
            }
        }, {
            data: 'size',
            className: 'size',
            defaultContent: "",
            render: function (data, type, row, meta) {
                if(type === 'display') {
                    path = row['path'] + '/';
                    if (data === null) {
                        data = '...';
                    } else if (Math.abs(data) > 1024) {
                        const units = ['kB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
                        let u = -1;

                        do {
                            data /= 1024;
                            ++u;
                        } while (Math.round(Math.abs(data) * 10) >= 1024 && u < units.length - 1);
                        data = data.toFixed(1) + ' ' + units[u];
                    }
                    data = '<a href="' + path + encodeComponentExceptColon(row['file']) + '.mirrorlist">' + data + '</a>';
                }
                return data;
            }
        }],
        lengthMenu: [
            [100, 1000, 10, -1],
            [100, 1000, 10, 'All'],
        ],
    });
}
