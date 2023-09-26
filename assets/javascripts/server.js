function setupServerNote(hostname) {
    var table = $('#server_note');
    var dataTable = table.DataTable({
        ajax: {
            url: '/rest/server/note/' + hostname,
        },
        deferRender: true,
        columns: [{data: 'dt'}, {data: 'acc'}, {data: 'kind'}, {data: 'msg'}],
        order: [[0, 'desc']],
        initComplete: function () {
            this.api()
                .columns()
                .every(function () {
                    var column = this;
                    var colheader = this.header();
                    var title = $(colheader).text().trim();
                    if (title !== 'Kind') {
                        return false;
                    }

                    var select = $('<select id="select_kind"><option value="">All</option></select>')
                        .appendTo($(column.header()).empty())
                        .on('change', function () {
                            var val = $.fn.dataTable.util.escapeRegex($(this).val());
                            column
                                // .search( val ? '^'+val+'$' : '', true, false )
                                .search(val ? val : '', true, false)
                                .draw();
                        });

                    select.append('<option value="Note">Note</option>');
                    select.append('<option value="Email">Email</option>');
                    select.append('<option value="Ftp">Ftp</option>');
                    select.append('<option value="Rsync">Rsync</option>');
                });
        }
    });
}

function setupServerIncident(server_id) {
    var table = $('#server_incident').DataTable({
        ajax: {
            url: '/rest/server/check/' + server_id,
        },
        deferRender: true,
        columns: [{data: 'dt'}, {data: 'capability'}, {data: 'extra'}],
        order: [[0, 'desc']],
    });
}

function addServerNote(hostname, kind, msg) {
    $.ajax({
        type: 'POST',
        url: '/rest/server/note/' + hostname,
        data: {
            kind: kind,
            msg: msg
        },
        success: function(data) {
            location.reload();
        },
        error: function(xhr, ajaxOptions, thrownError) {
            var error_message = 'An error occurred while adding server ' + kind + ': ';
            if (xhr.responseJSON && xhr.responseJSON.error)
                error_message += xhr.responseJSON.error;
                addFlash('danger', error_message);
        }
    });
}

function addServerNoteButtonStatus() {
    if(document.getElementById("new-note-text").value==="") {
        document.getElementById('new-note-submit').disabled = true;
    } else {
        document.getElementById('new-note-submit').disabled = false;
    }
}
