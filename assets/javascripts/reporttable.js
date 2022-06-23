function setupReportTable() {
    // read columns from empty HTML table rendered by the server
    var columns = [];
    columns.push({ data: 'region', defaultContent: "" });
    columns.push({ data: 'country', defaultContent: "" });
    columns.push({ data: 'url', defaultContent: "" });
    $('#checkboxes label').each(function() {
        var columnName = $(this).text();
        if (columnName == 'Blame') {
            return;
        }
        columnName = columnName.trim().replace(/ /g,"").toLowerCase().replace(/\./g,"");
        if (columnName.match(/^\d/)) {
            columnName = 'c' + columnName;
        }
        columns.push({ data: (columnName + 'score'), defaultContent: "" });
        columns.push({ data: (columnName + 'victim'), defaultContent: "" });
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


    $('#checkboxes').on('change', ':checkbox', function () {
        layoutReportTable();
    });
    layoutReportTable();
}

function layoutReportTable() {
    var dt = $('.reporttable').DataTable();

    var victim = 1;
    if (!$('#victimcheckbox').is(":checked")) {
        victim = 0;
    }
    var existchecked = 0;
    $('#checkboxes label').each(function() {
        var columnName = $(this).text();
        if (columnName == 'Blame') {
            return;
        }
        var vis = 1;
        if ($("[ id='" + columnName + "checkbox' ]").is(":checked")) {
            existchecked = 1;
        }
    });

    var i = 0;
    var firstColumnHack = 0;      // apparently setting .visible() doesn't work for first time,
    var firstColumnIndex = 3;     // so we remember it here and (re-)set at the end again
    $('#checkboxes label').each(function() {
        var lbl = $(this);
        var columnName = lbl.text();
        if (columnName == 'Blame') {
            return;
        }
        var vis = 1;
        if (existchecked && !$("[ id='" + columnName + "checkbox' ]").is(":checked")) {
            vis = 0;
        }
        if (i == 0) {
            firstColumnHack = vis;
        }
        var index = firstColumnIndex + 2*i;
        if (vis != dt.columns(index).visible()) {
            dt.columns(index).visible(vis);
        }
        if (vis && victim != dt.columns(index + 1).visible()) {
            dt.columns(index + 1).visible(victim);
        } else if (!vis && dt.columns(index + 1).visible()) {
            dt.columns(index + 1).visible(vis);
        }
        i = i + 1;
    });
    dt.columns(firstColumnIndex).visible(firstColumnHack);
}
