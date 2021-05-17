// jshint multistr: true
// jshint esversion: 6

var audit_url;
var audit_ajax_url;

function loadAuditLogTable() {
    $('#audit_log_table').DataTable({
        processing: true,
        serverSide: true,
        searchDelay: 1000,
        search: { search: searchquery },
        ajax: { url: audit_ajax_url, type: "GET", dataType: 'json' },
        columns: [{ data: 'event_time' }, { data: 'user' }, { data: 'event' }, { data: 'event_data' }],
        order: [
            [0, 'desc']
        ],
        columnDefs: [
            { targets: 0, // event_time
                render: function(data, type, row) {
                    if (type === 'display')
                        return '<a href="' + audit_url + '?event_id=' + row.id + '" title=' + data + '>' + jQuery.timeago(data + " UTC") + '</a>';
                    else
                        return data;
                }
            },
            { targets: 1, // user
                render: function(data, type, row) {
                    if (type === 'display')
                        return '<a href="' + audit_url + '?user_id=' + row.user_id + '" title="See all user actions"' + '>' + data + '</a>';
                    else
                        return data;
                }
            },
            { targets: 3, // event_data
                width: "50%",
                render: function(data, type, row) {
                    if (type === 'display' && data) {
                        var parsed_data;
                        try {
                            parsed_data = JSON.stringify(JSON.parse(data), null, 2);
                        } catch (e) {
                            parsed_data = data;
                        }
                        return '<span class="audit_event_data" title="' + htmlEscape(parsed_data) + '">' + htmlEscape(parsed_data) + '</span>';
                    } else {
                        return data;
                    }
                }
            },
        ],
    });
}
