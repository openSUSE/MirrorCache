function setupProjectPropagation(id) {
    var table = $('#project_propagation');
    var dataTable = table.DataTable({
        ajax: {
            url: '/rest/project/propagation/' + id,
        },
        deferRender: true,
        columns: [{data: 'dt'}, {data: 'prefix'}, {
            data: 'version',
            render: function(data, type, row) {
                if (type !== 'display') {
                    return data ? data : '';
                }
                return data? '<a href="/app/rollout_server/'+ data +'">' + htmlEscape(data) + '</>' : '';
            }
        }, {data: 'mirrors'}],
        order: [[0, 'desc']],
    });
}

