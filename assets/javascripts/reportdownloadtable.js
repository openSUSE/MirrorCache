function setupReportDownloadTable(column) {
    // read columns from empty HTML table rendered by the server
    var columns = [];
    var keys = column.split(',');
    columns.push({
        data: 'dt',
        defaultContent: "",
        render: function (data, type, row, meta) {
            if(type === 'display') {
                var date = new Date(data);
                return date.toLocaleDateString();
            }
            return data;
        }
    });
    columns.push({
        data: column,
        defaultContent: "",
        render: function (data, type, row, meta) {
            data = "";
            for (let i = 0; i < keys.length; i++) {
                if (data != "") {
                    data = data + ',';
                }
                data = data + row[keys[i]];
            }
            return data;
        }
    });
    columns.push({ data: 'total_requests', defaultContent: "" });
    columns.push({ data: 'known_files_requested', defaultContent: "" });
    columns.push({ data: 'known_files_redirected', defaultContent: "" });
    columns.push({
        data: 'bytes_redirected',
        defaultContent: "",
        render: function (data, type, row, meta) {
            if(type === 'display') {
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

    var url = $("#reporttable_api_url").val();
    var table = $('.reporttable');
    var dataTable = table.DataTable({
        order: [
            [0, 'desc']
        ],
        ajax: {
            url: url,
        },
        columns: columns,
        lengthMenu: [
            [100, 1000, 10, -1],
            [100, 1000, 10, 'All'],
        ],
        search: {
            regex: true,
        },
    });
    dataTable.rowData = [];
}

