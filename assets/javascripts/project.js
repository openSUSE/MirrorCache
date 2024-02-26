function setupProjectPropagation(id) {
    var table = $('#project_propagation');
    var dataTable = table.DataTable({
        ajax: {
            url: '/rest/project/propagation/' + id,
        },
        deferRender: true,
        columns: [{data: 'dt'}, {data: 'prefix'}, {data: 'version'}, {data: 'mirrors'}],
        order: [[0, 'desc']],
    });
}
