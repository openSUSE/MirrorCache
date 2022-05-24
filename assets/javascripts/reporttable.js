
function setupReportTable() {
    // read columns from empty HTML table rendered by the server
    var columns = [];
    var thElements = $('.reporttable thead th').each(function() {
        var th = $(this);

        // add column
        var columnName;
        columnName = th.text().trim().replace(/ /g,"").toLowerCase();
        columns.push({ data: columnName });
    });

    var url = $("#reporttable_api_url").val();
    var table = $('.reporttable');
    var dataTable = table.DataTable({
        order: [
            [0, 'asc']
        ],
        ajax: {
            url: url,
            dataSrc: 'report'
        },
        columns: columns,
        search: {
            regex: true,
        },
    });
    dataTable.rowData = [];
}
