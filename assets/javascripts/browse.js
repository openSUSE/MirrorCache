function setupBrowseTable(path) {
    // read columns from empty HTML table rendered by the server
    var columns = [];
    if (path != '/') {
        path = path + '/';
    }
    columns.push({
        data: 'name',
        className: 'name',
        defaultContent: "",
        type: "version-string",
        render: function (data, type, row, meta) {
            if(type === 'display'){
                var d = data;
                var t = '';
                if(row['name'].slice(-1) === '/') {
                    d = data.slice(0,-1);
                    t = '/';
                }
                var desc = row['desc'];
                if (desc) {
                    data = '<a style="--desc: \'' + desc + '\'" href="' + path + encodeURIComponent(d) + t + '">' + data + '</a>';
                } else {
                    data = '<a href="' + path + encodeURIComponent(d) + t + '">' + data + '</a>';
                }
            }
            if(type === 'sort'){
                if(data.slice(-1) != '/') {
                    data = '~' + data;
                } else {
                    data = '_' + data;
                }
            }
            return data;
        }
    });
    columns.push({
        data: 'mtime',
        className: 'mtime',
        defaultContent: "",
        render: function (data, type, row, meta) {
            if(type === 'display' && data > 0){
                data = new Date(data * 1000).toLocaleString().replace(/.\d+$/, "").replace(/:\d\d (AM|PM)$/, " $1");
                if(row['name'].slice(-1) != '/') {
                    data = '<a href="' + path + encodeURIComponent(row['name']) + '.mirrorlist">' + data + '</a>';
                } else {
                    data = '<a href="' + path + encodeURIComponent(row['name'].slice(0,-1)) + '/">' + data + '</a>';
                }
            }
            return data;
        }
    });
    columns.push({
        data: 'size',
        className: 'size',
        defaultContent: "",
        render: function (data, type, row, meta) {
            if(type === 'display') {
                if(row['name'].slice(-1) == '/') {
                    return '';
                }
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
                data = '<a href="' + path + encodeURIComponent(row['name']) + '.mirrorlist">' + data + '</a>';
            }
            return data;
        }
    });

    jQuery.extend( jQuery.fn.dataTableExt.oSort, {
        "version-string-asc" : function (a, b) {
            return a.localeCompare(b, undefined, { numeric: true, sensitivity: 'base' });
        },
        "version-string-desc" : function (a, b) {
            return b.localeCompare(a, undefined, { numeric: true, sensitivity: 'base' });
        }
    });


    var url = $("#browse_api_url").val();
    var table = $('.browsetable');
    var dataTable = table.DataTable({
        ajax: {
            url: url,
        },
        lengthMenu: [
            [20, 100, 1000, 10, -1],
            [20, 100, 1000, 10, 'All'],
        ],
        columns: columns,
        search: {
            regex: true,
        },
    });
    dataTable.rowData = [];
}

