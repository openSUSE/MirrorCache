function setupReportDownloadTable(column) {
    // read columns from empty HTML table rendered by the server
    var columns = [];
    columns.push({
        data: 'dt',
        defaultContent: "",
        render: function (data) {
            var date = new Date(data);
            return date.toLocaleDateString();
        }
    });
    columns.push({ data: column, defaultContent: "" });
    columns.push({ data: 'total_requests', defaultContent: "" });
    columns.push({ data: 'known_files_requested', defaultContent: "" });
    columns.push({ data: 'known_files_redirected', defaultContent: "" });
    columns.push({
        data: 'bytes_redirected',
        defaultContent: "",
        render: function (data) {
            if (Math.abs(data) < 1024) {
                return data;
            }
            const units = ['kB', 'MB', 'GB', 'TB', 'PB', 'EB', 'ZB', 'YB'];
            let u = -1;

            do {
                data /= 1024;
                ++u;
            } while (Math.round(Math.abs(data) * 10) >= 1024*1024 && u < units.length - 1);


            return data.toFixed(2) + ' ' + units[u];
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
        search: {
            regex: true,
        },
    });
    dataTable.rowData = [];
}

