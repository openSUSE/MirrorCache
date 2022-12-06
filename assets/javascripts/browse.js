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
        render: function (data, type, row, meta) {
            if(type === 'display'){
                data = '<a href="' + path + data + '">' + data + '</a>';
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
                data = new Date(data * 1000).toLocaleString().replace(/.\d+$/g, "");;
            }
            return data;
        }
    });
    columns.push({
        data: 'size',
        className: 'size',
        defaultContent: "",
        render: function (data, type, row, meta) {
            if(type === 'display' && data > 0){
                if(row['name'].slice(-1) == '/') {
                    return '';
                }
                if (Math.abs(data) < 1024) {
                    return data;
                }
                const units = ['kB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
                let u = -1;

                do {
                    data /= 1024;
                    ++u;
                } while (Math.round(Math.abs(data) * 10) >= 1024 && u < units.length - 1);
                return data.toFixed(1) + ' ' + units[u];
            }
            return data;
        }
    });
    columns.push({
        data: 'name',
        defaultContent: "",
        render: function (data, type, row, meta) {
            if(type === 'display'){
                if(data.slice(-1) == '/') {
                    return '';
                }
                if(type === 'display'){
                    data = '<a href="' + path + data + '.mirrorlist">Details</a>';
                }
            }
            return data;
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

