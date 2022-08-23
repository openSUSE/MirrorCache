function updateTextArea(textArea) {
    textArea.style.height = 'auto';
    textArea.style.height = Math.min(textArea.scrollHeight + 5, 300) + 'px';
}

function extendAdminTableSearch(searchTerm) {
    window.adminTable.search('((' + window.adminTable.search() + ')|(' + searchTerm + '))');
}

var newRowId = 'new row';

function showAdminTableRow(row) {
    var adminTable = window.adminTable;

    // set pagination to the page containing the new row
    var pageInfo = adminTable.page.info();
    var rowPosition = adminTable.rows({ search: 'applied' })[0].indexOf(row.index());
    if (rowPosition < 0) {
        // extend the search if the row to be shown would otherwise be filtered out
        var rowData = row.data();
        extendAdminTableSearch(!rowData.id ? newRowId : rowData.id);
        rowPosition = adminTable.rows({ search: 'applied' })[0].indexOf(row.index());
    }
    if (rowPosition < 0) {
        // handle case when updating the regex does not work
        addFlash('info', 'The added/updated row has been filtered out.');
        return;
    }
    if (rowPosition < pageInfo.start || rowPosition >= pageInfo.end) {
        adminTable.page(Math.floor(rowPosition / adminTable.page.len())).draw(false);
    }

    // scroll to the new row
    $('html').animate({ scrollTop: $(row.node()).offset().top }, 250);
}

function addAdminTableRow() {
    var adminTable = window.adminTable;

    // add new row
    var newRow = adminTable.row.add(adminTable.emptyRow);
    var newRowIndex = newRow.index();
    adminTable.rowData[newRowIndex] = jQuery.extend({ isEditing: true }, adminTable.emptyRow);
    newRow.invalidate().draw();

    showAdminTableRow(newRow);
}

function isEditingAdminTableRow(meta) {
    var rowData = window.adminTable.rowData;
    var rowIndex = meta.row;
    return rowIndex < rowData.length && rowData[rowIndex].isEditing;
}

function setEditingAdminTableRow(tdElement, editing, submitted) {
    // get the data table row for the tdElement
    var adminTable = window.adminTable;
    var rowData = adminTable.rowData;
    var row = adminTable.row(tdElement);
    if (!row) {
        addFlash('danger', 'Internal error: invalid table row/cell specified');
        return;
    }

    // get the buffered row data updated from editor elements before submitting and set the 'isEditing' flag there
    var rowIndex = row.index();
    if (rowIndex < rowData.length) {
        var data = rowData[rowIndex];
        data.isEditing = editing;

        // pass the buffered row data from editor elements to the data table
        // note: This applies submitted changes or restores initial values when editing is cancelled by the user.
        if (submitted) {
            row.data(data);
        }
    }

    // invalidate the table row not resetting the pagination (false parameter to draw())
    row.invalidate().draw(false);
}

function refreshAdminTableRow(tdElement) {
    window.adminTable.row(tdElement).invalidate().draw();
}

function handleAdminTableApiError(request, status, error) {
    if (request.responseJSON != undefined && request.responseJSON.error) {
        error += ': ' + request.responseJSON.error;
    }
    addFlash('danger', error);
}

function handleAdminTableSubmit(tdElement, response, id) {
    // leave editing mode
    setEditingAdminTableRow(tdElement, false, true);

    // query affected row again so changes applied by the server (removing invalid chars from settings keys) are visible
    $.ajax({
        url: $("#admintable_api_url").val() + "/" + id,
        type: "GET",
        dataType: 'json',
        success: function(resp) {
            var rowData = resp[Object.keys(resp)[0]];
            if (rowData) {
                rowData = rowData[0];
            }
            if (!rowData) {
                addFlash('danger', 'Internal error: server replied invalid row data.');
                return;
            }

            var adminTable = window.adminTable;
            var row = adminTable.row(tdElement);
            var rowIndex = row.index();
            if (rowIndex >= adminTable.rowData.length) {
                return;
            }
            row.data(adminTable.rowData[rowIndex] = rowData).draw(false);
            showAdminTableRow(row);
        },
        error: handleAdminTableApiError,
    });
}

function handleServerLocationSubmit(tdElement, response, id) {
    $(location).attr('href', '/minion/jobs?id=' + response.job_id);
}

function getAdminTableRowData(trElement, dataToSubmit, internalRowData) {
    var tableHeadings = trElement.closest('table').find('th');
    trElement.find('td').each(function() {
        var th = tableHeadings.eq(this.cellIndex);
        var name = th.text().trim().toLowerCase().replace(/ /g, '_');
        var value;
        if (th.hasClass("col_value")) {
            value = $(this).find("input").val();
            if (name === 'enabled' && value === "") {
                value = "0";
            }
            if (dataToSubmit) {
                dataToSubmit[name] = value;
            }
            if (internalRowData) {
                internalRowData[name] = value;
            }
        }
    });
}

function submitAdminTableRow(tdElement, id) {
    var adminTable = window.adminTable;
    var rowIndex = adminTable.row(tdElement).index();
    if (rowIndex === undefined) {
        addFlash('danger', 'Internal error: invalid table cell specified');
        return;
    }
    var rowData = adminTable.rowData[rowIndex];
    if (!rowData) {
        addFlash('danger', 'Internal error: row data is missing');
        return;
    }

    var dataToSubmit = {};
    try {
        getAdminTableRowData($(tdElement).parent('tr'), dataToSubmit, rowData);
    } catch (e) {
        if (e.type !== 'invalid line') {
            throw e;
        }
        addFlash('danger', 'Line ' + e.lineNo + ' of settings is invalid: ' + e.text);
        return;
    }
    // window.alert(JSON.stringify(dataToSubmit));
    var url = $("#admintable_api_url").val();
    if (id) {
        // update
        $.ajax({
            url: url + "/" + id,
            type: "POST",
            dataType: 'json',
            data: dataToSubmit,
            headers: {
                'X-HTTP-Method-Override': 'PUT'
            },
            success: function(response) {
                handleAdminTableSubmit(tdElement, response, id);
            },
            error: handleAdminTableApiError
        });
    } else {
        // create new
        $.ajax({
            url: url,
            type: "POST",
            dataType: 'json',
            data: dataToSubmit,
            success: function(response) {
                handleAdminTableSubmit(tdElement, response, response.id);
            },
            error: handleAdminTableApiError
        });
    }
}

function submitServerLocationRow(tdElement, id) {
    $.ajax({
        url: '/rest/server/location/' + id,
        type: "PUT",
        dataType: 'json',
        success: function(response) {
            handleServerLocationSubmit(tdElement, response, response.id);
        },
        error: handleAdminTableApiError
   });
}

function removeAdminTableRow(tdElement) {
    var adminTable = window.adminTable;
    var row = adminTable.row(tdElement);
    var rowIndex = row.index();
    if (rowIndex !== undefined && rowIndex < adminTable.rowData.length) {
        adminTable.rowData.splice(rowIndex, 1);
    }
    row.remove().draw();
}

function deleteTableRow(tdElement, id) {
    if (!confirm("Really delete?")) {
        return;
    }

    // delete unsubmitted row
    if (!id) {
        removeAdminTableRow(tdElement);
        return;
    }

    $.ajax({
        url: $("#admintable_api_url").val() + "/" + id,
        type: "DELETE",
        dataType: 'json',
        success: function() {
            removeAdminTableRow(tdElement);
        },
        error: handleAdminTableApiError
    });
}

function renderAdminTableValue(data, type, row, meta) {
    if (type !== 'display') {
        return data ? data : '';
    }
    if (isEditingAdminTableRow(meta)) {
        return '<input type="text" value="' + htmlEscape(data) + '"/>';
    }
    return htmlEscape(data);
}

function renderAdminTableSettingsList(data, type, row, meta) {
    var plainText = type !== 'display';
    var edit = isEditingAdminTableRow(meta);
    var result = '';
    if (edit) {
        result += '<textarea class="key-value-pairs" oninput="updateTextArea(this);">';
    }
    for (var j = 0; j < data.length; j++) {
        var keyValuePair = data[j];
        var key = htmlEscape(keyValuePair.key);
        var value = htmlEscape(keyValuePair.value);
        if (edit || plainText) {
            result += key + '=' + value + '\n';
        } else {
            result += '<span class="key-value-pair"><span class="key">' + key +
                '</span>=<span class="value">' + value + '</span></span><br/>';
        }
    }
    if (edit) {
        result += '</textarea>';
    }
    return result;
}

function renderAdminTableDescription(data, type, row, meta) {
    if (type !== 'display') {
        return data ? data : '';
    }
    if (isEditingAdminTableRow(meta)) {
        return '<textarea class="description">' + htmlEscape(data) + '</textarea>';
    }
    return htmlEscape(data);
}

function renderAdminTableActions(data, type, row, meta) {
    if (type !== 'display') {
        return data ? data : newRowId;
    }
    if (isEditingAdminTableRow(meta)) {
        return renderEditableAdminTableActions(data, type, row, meta);
    }
    if (!window.editable) {
        return '';
    }
    var url = $("#admintable_api_url").val();
    res = '<button type="submit" class="btn" alt="Edit" title="Edit" onclick="setEditingAdminTableRow(this.parentElement, true, false);"><i class="far fa-edit"></i></button>';
    if (url == '/rest/server' && data) {
        return res + '<button type="submit" class="btn" alt="UpdateLocation" title="Update Location" onclick="submitServerLocationRow(this.parentElement, ' + data + ');"><i class="far fa-bookmark"></i></button>';
    } else {
        return res
    }
}

function renderEditableAdminTableActions(data, type, row, meta) {
    if (type !== 'display') {
        return data ? data : newRowId;
    }
    if (!window.editable) {
        return '';
    }
    if (data) {
        // show submit/cancel/delete buttons while editing existing row
        return '<button type="submit" class="btn" alt="Update" title="Update" onclick="submitAdminTableRow(this.parentElement, ' + data +
            ');"><i class="far fa-save"></i></button><button type="submit" class="btn" alt="Cancel" title="Cancel" onclick="setEditingAdminTableRow(this.parentElement, false, true);"><i class="fa fa-undo"></i></button><button type="submit" class="btn" alt="Delete" title="Delete" onclick="deleteTableRow(this.parentElement, ' + data +
            ');"><i class="fa fa-trash-alt"></i></button>';
    } else {
        // show submit/cancel button while adding new row
        return '<button type="submit" class="btn" alt="Add" title="Add" onclick="submitAdminTableRow(this.parentElement);"><i class="far fa-save"></i></button><button type="submit" class="btn" alt="Cancel" title="Cancel" onclick="deleteTableRow(this.parentElement);"><i class="fa fa-undo"></i></button>';
    }
}

function setupAdminTable(editable) {
    // adjust sorting so empty strings come last
    jQuery.extend(jQuery.fn.dataTableExt.oSort, {
        'empty-string-last-asc': function(str1, str2) {
            if (str1 === '') {
                return 1;
            }
            if (str2 === '') {
                return -1;
            }
            return ((str1 < str2) ? -1 : ((str1 > str2) ? 1 : 0));
        },
        'empty-string-last-desc': function(str1, str2) {
            if (str1 === '') {
                return 1;
            }
            if (str2 === '') {
                return -1;
            }
            return ((str1 < str2) ? 1 : ((str1 > str2) ? -1 : 0));
        }
    });

    // read columns from empty HTML table rendered by the server
    var emptyRow = {};
    var columns = [];
    var columnDefs = [];
    var thElements = $('.admintable thead th').each(function() {
        var th = $(this);

        // add column
        var columnName;
        if (th.hasClass('col_action')) {
            columnName = 'id';
        } else {
            columnName = th.text().trim().toLowerCase().replace(/ /g, '_');
        }
        columns.push({ data: columnName });

        // add column definition to customize rendering and sorting and add template for empty row
        var columnDef = {
            targets: columns.length - 1,
            type: 'empty-string-last',
        };
        if (th.hasClass('col_value')) {
            columnDef.render = renderAdminTableValue;
            emptyRow[columnName] = "";
        } else if (th.hasClass('col_settings')) {
            columnDef.render = renderAdminTableSettings;
            emptyRow.settings = {};
        } else if (th.hasClass('col_settings_list')) {
            columnDef.render = renderAdminTableSettingsList;
            columnDef.orderable = false;
            emptyRow.settings = [];
        } else if (th.hasClass('col_description')) {
            columnDef.render = renderAdminTableDescription;
            emptyRow.description = "";
        } else if (th.hasClass('col_action')) {
            columnDef.render = renderAdminTableActions;
            columnDef.orderable = false;
        } else {
            emptyRow[columnName] = "";
        }
        columnDefs.push(columnDef);
    });

    // setup admin table
    var url = $("#admintable_api_url").val();
    var table = $('.admintable');
    var dataTable = table.DataTable({
        order: [
            [0, 'asc']
        ],
        ajax: {
            url: url,
            dataSrc: function(json) {
                // assume the first "key" contains the data
                var rowData = json[Object.keys(json)[0]];
                if (!rowData) {
                    addFlash('danger', 'Internal error: server response misses table data');
                    return (dataTable.rowData = []);
                }
                return (dataTable.rowData = rowData);
            },
        },
        columns: columns,
        columnDefs: columnDefs,
        search: {
            regex: true,
        },
    });
    dataTable.rowData = [];
    dataTable.emptyRow = emptyRow;

    // save the current editor values before redraw so they survive using filtering/sorting/pagination
    dataTable.on('preDraw', function() {
        var rowData = dataTable.rowData;
        table.find('tr').each(function() {
            var row = adminTable.row(this);
            var rowIndex = row.index();
            if (rowIndex === undefined || rowIndex >= rowData.length) {
                return;
            }
            var data = jQuery.extend({}, rowData[rowIndex]);
            if (!data.isEditing) {
                return;
            }
            getAdminTableRowData($(this), undefined, data);
            row.data(data);
        });
    });

    // make the height of text areas fit its contents
    dataTable.on('draw', function() {
        table.find('textarea').each(function() {
            updateTextArea(this);
        });
    });

    // set/update page-global state (there can only be one admin table at a page anyways)
    window.editable = editable;
    window.adminTable = dataTable;

    // prevent sorting when help popover on table heading is clicked
    table.find('th .help_popover').on('click', function(event) {
        event.stopPropagation();
    });
}
