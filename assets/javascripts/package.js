
var pkg_param_pkg;
var pkg_param_arch;
var pkg_param_official;
var pkg_param_os;
var pkg_param_os_ver;
var pkg_param_repo;
var pkg_param_ign_path;
var pkg_param_ign_file;
var pkg_param_strict;

var pkg_stat_first_seen;
var pkg_stat_dl_todate = ''; // total excluding today
var pkg_stat_dl_today  = ''; // today excluding last hour
var pkg_stat_dl_curr   = ''; // last hour

function initPackageParams() {

    const queryString = window.location.search;
    const urlParams = new URLSearchParams(queryString);


    pkg_param_pkg = urlParams.get('pkg');
    pkg_param_arch = urlParams.get('arch');
    pkg_param_official = urlParams.get('official');
    pkg_param_os = urlParams.get('os');
    pkg_param_os_ver = urlParams.get('os_ver');
    pkg_param_repo = urlParams.get('repo');
    pkg_param_ign_path = urlParams.get('ignore_path');
    pkg_param_ign_file = urlParams.get('ignore_file');
    pkg_param_strict = urlParams.get('strict');

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
    if (pkg_param_ign_path) {
        document.getElementById("ign_path").value = pkg_param_ign_path;
    }
    if (pkg_param_ign_file) {
        document.getElementById("ign_file").value = pkg_param_ign_file;
    }
    if (pkg_param_strict) {
        ( document.getElementById("strict") || {} ).checked = pkg_param_strict? 1 : 0;
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
    pkg_param_ign_path = document.getElementById("ign_path").value;
    pkg_param_ign_file = document.getElementById("ign_file").value;

    var dataTable = table.DataTable({
        ajax: {
            url: '/rest/search/packages',
            data: {
                "package":  pkg_param_pkg,
                "arch":     pkg_param_arch,
                "official": pkg_param_official,
                "os":       pkg_param_os,
                "os_ver":   pkg_param_os_ver,
                "repo":     pkg_param_repo,
                "ignore_path": pkg_param_ign_path,
                "ignore_file": pkg_param_ign_file,
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
                    if (pkg_param_ign_path) {
                        get.push(['ignore_path', htmlEscape(pkg_param_ign_path)]);
                    }
                    if (pkg_param_ign_file) {
                        get.push(['ignore_file', htmlEscape(pkg_param_ign_file)]);
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
    pkg_param_ign_path = document.getElementById("ign_path").value;
    pkg_param_ign_file = document.getElementById("ign_file").value;
    pkg_param_strict   = document.getElementById("strict").checked ? 1 : '';

    var dataTable = table.DataTable({
        ajax: {
            url: '/rest/search/package_locations',
            data: {
                "package":  pkg_name,
                "arch":     pkg_param_arch,
                "official": pkg_param_official,
                "os":       pkg_param_os,
                "os_ver":   pkg_param_os_ver,
                "repo":     pkg_param_repo,
                "ignore_path": pkg_param_ign_path,
                "ignore_file": pkg_param_ign_file,
                "strict"     : pkg_param_strict,
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
            orderSequence: ['desc','asc'],
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




function setupDownloadStatUI() {
    if (typeof pkg_stat_first_seen != 'undefined') {
        res = pkg_stat_first_seen;
        if ( +parseInt(pkg_stat_first_seen) > 0) {
            res = new Date(+parseInt(pkg_stat_first_seen)*1000).toISOString();
            // truncate seconds
            res = res.substring(0, 16) + res.substr(23)
        }
        document.getElementById("download-stat-first-seen").textContent = res;
    }
    if (typeof pkg_stat_dl_todate != 'undefined') {
        var res = pkg_stat_dl_todate;
        if ( +parseInt(pkg_stat_dl_today) > 0) {
            res = +res + +parseInt(pkg_stat_dl_today);
        }
        if ( +parseInt(pkg_stat_dl_curr) > 0) {
            res = +res + +parseInt(pkg_stat_dl_curr);
        }
        document.getElementById("download-stat-total").textContent = res;
    }
    if (typeof pkg_stat_dl_today != 'undefined') {
        var res = pkg_stat_dl_today;
        if ( +parseInt(pkg_stat_dl_curr) > 0) {
            res = +res + +parseInt(pkg_stat_dl_curr);
        }
        document.getElementById("download-stat-today").textContent = res;
    }
    if (typeof pkg_stat_dl_today != 'undefined') {
        var res = pkg_stat_dl_curr;
        document.getElementById("download-stat-curr").textContent = res;
    }
}

function setupPackageStatDownload(id) {
    $.ajax({
        url: '/rest/package/' + id + '/stat_download',
        method: 'GET',
        success: function(response) {
            var data = response.data[0];
            if (typeof data === 'undefined') {
                return;
            }
            var c = data.cnt_total;
            if (typeof c !== 'undefined' && c > 0) {
                pkg_stat_dl_todate = c;
            }
            c = data.cnt_today;
            if (typeof c !== 'undefined' && c > 0) {
                pkg_stat_dl_today = c;
            }
            c = data.first_seen;
            if (typeof c !== 'undefined' && c > 0) {
                pkg_stat_first_seen = c;
            }
            setupDownloadStatUI();
        },
        error: handleAjaxError,
    });
}

function setupPackageStatDownloadCurr(package_name) {
    $.ajax({
        url: '/rest/package/' + package_name + '/stat_download_curr',
        method: 'GET',
        success: function(response) {
            var data = response.data[0];
            if (typeof data === 'undefined') {
                return;
            }
            var c = data.cnt_curr;
            if (typeof c !== 'undefined' && c > 0) {
                pkg_stat_dl_curr = c;
            }
            setupDownloadStatUI();
        },
        error: handleAjaxError,
    });
}
